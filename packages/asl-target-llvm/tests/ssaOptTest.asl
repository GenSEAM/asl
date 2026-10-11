(module asl-target-llvm/tests/ssaOptTest
  :x [runTests]
  :i [(asl-ir/types :a irTy)
      (asl-ir/link :a lk)
      (asl-ir/verify :a vfy)
      (asl-target-llvm :a nat)
      (asl-target-llvm/ssa :a llvm)
      (asl-target-llvm/ssaOpt :a opt)
      (asl-target-llvm/libc :a libc)
      (asl-target-llvm/sysRoute :a route)
      (tools/nativeTest :a nt)
      (tools/fleet/run :a run)])

fn probeSource -> String
  (str "(module probe\n  :x [main pick again nothing adder apply]\n  :i [])\n\n"
       "enum Shade\n  (shadeDark)\n  (shadeLight)\n  (shadeTinted level: Int64)\n\n"
       "fn pick n: Int64 -> Shade\n  (if (> n 0) (shadeDark) (shadeTinted n))\n\n"
       "fn again -> Shade\n  (shadeDark)\n\n"
       "fn nothing -> (Option Int64)\n  (none)\n\n"
       "fn adder k: Int64 -> (fn [Int64] -> Int64)\n  (fn [(x Int64)] -> Int64 (+ x k))\n\n"
       "fn inc x: Int64 -> Int64\n  (+ x 1)\n\n"
       "fn apply f: (fn [Int64] -> Int64) x: Int64 -> Int64\n  (f x)\n\n"
       "fn main -> Int64\n  (+ (apply inc 1) (+ (apply (fn [(x Int64)] -> Int64 (* x 2)) 3) (apply (adder 4) 5)))\n")

fn libSource -> String
  "(module probeLib\n  :x [nothing]\n  :i [])\n\nfn nothing -> (Option Int64)\n  (none)\n"

fn ! lowered src: String -> (Result irTy/SsaModule String)
  (mt (fileReadString (lk/preludePath))
    ((err e) (err (str "cannot read the prelude: " e)))
    ((ok preludeSrc) (mt (lk/lowerSourceWith src preludeSrc)
                       ((err ds) (err (stringJoin (map (fn [(d irTy/IrDiag)] -> String (str d.locus ": " d.message)) ds) "; ")))
                       ((ok m) (ok m)))))

fn userInstrs m: irTy/SsaModule -> (List irTy/SsaInstr)
  (let [(prefix (opt/singletonPrefix m.name))]
    (fold (fn [(acc (List irTy/SsaInstr)) (f irTy/SsaFunction)] -> (List irTy/SsaInstr)
            (if (stringStartsWith? f.name prefix) acc
              (fold (fn [(a (List irTy/SsaInstr)) (b irTy/SsaBlock)] -> (List irTy/SsaInstr) (listAppend a b.instrs)) acc f.blocks)))
          (list) m.functions))

fn countOps m: irTy/SsaModule pred: (fn [irTy/SsaOp] -> Bool) -> Int64
  (listLength (filter (fn [(i irTy/SsaInstr)] -> Bool (pred i.op)) (userInstrs m)))

fn nullaryConstruct? op: irTy/SsaOp -> Bool
  (mt op ((irTy/opConstruct _ _ fields) (listEmpty? fields)) (_ false))

fn fieldedConstruct? op: irTy/SsaOp -> Bool
  (mt op ((irTy/opConstruct _ _ fields) (not (listEmpty? fields))) (_ false))

fn capturelessClosure? op: irTy/SsaOp -> Bool
  (mt op ((irTy/opMakeClosure _ caps) (listEmpty? caps)) (_ false))

fn capturingClosure? op: irTy/SsaOp -> Bool
  (mt op ((irTy/opMakeClosure _ caps) (not (listEmpty? caps))) (_ false))

fn singletonRead? op: irTy/SsaOp -> Bool
  (mt op ((irTy/opGlobal name) (stringContains? name ".@ssaOpt$")) (_ false))

fn distinctKeys m: irTy/SsaModule -> Int64
  (listLength (fold (fn [(acc (List String)) (i irTy/SsaInstr)] -> (List String)
                      (mt (opt/constantKey i) ((some k) (if (listContains? acc k) acc (cons k acc))) ((none) acc)))
                    (list) (userInstrs m)))

fn entryOf m: irTy/SsaModule -> String
  (optionOr (listHead (filter (fn [(n String)] -> Bool (or (= n "main") (stringEndsWith? n ".main"))) (map (fn [(f irTy/SsaFunction)] -> String f.name) m.functions))) "main")

fn diagsText res: (Result String (List irTy/IrDiag)) -> String
  (mt res ((ok _) "ok") ((err ds) (stringJoin (map (fn [(d irTy/IrDiag)] -> String (str d.locus ": [" d.code "] " d.message)) ds) "; ")))

fn occurrences text: String needle: String -> Int64
  (- (listLength (stringSplit text needle)) 1)

fn outsideInits text: String needle: String -> Int64
  (fold (fn [(acc Int64) (seg String)] -> Int64
          (if (stringContains? (optionOr (listHead (stringSplit seg "\n")) "") "ssaOpt") acc (+ acc (occurrences seg needle))))
        0 (stringSplit text "\ndefine "))

fn mainBody text: String -> String
  (mt (stringIndexOf text "define i32 @main(")
    ((none) "")
    ((some i) (let [(rest (optionOr (stringSlice text i (stringLength text)) ""))]
                (optionOr (stringSlice rest 0 (optionOr (stringIndexOf rest "\n}\n") (stringLength rest))) ""))))

fn ! testRewrite -> Bool
  (mt (lowered (probeSource))
    ((err e) (do (assert false (str "probe lowers: " e)) false))
    ((ok m)
      (let [(h (opt/hoistConstants m))
            (keys (distinctKeys m))
            (inits (filter (fn [(f irTy/SsaFunction)] -> Bool (stringStartsWith? f.name (opt/singletonPrefix m.name))) h.functions))]
        (do (assert (>= (countOps m nullaryConstruct?) 3) "the probe builds nullary constructors at three sites before the pass")
            (assert (>= (countOps m capturelessClosure?) 2) "the probe makes captureless closures before the pass")
            (assert (= (countOps h nullaryConstruct?) 0) "no nullary constructor is built outside a singleton initialiser after the pass")
            (assert (= (countOps h capturelessClosure?) 0) "no captureless closure is made outside a singleton initialiser after the pass")
            (assert (= (countOps h singletonRead?) (+ (countOps m nullaryConstruct?) (countOps m capturelessClosure?))) "every rewritten site reads a singleton global")
            (assert (= (countOps h capturingClosure?) (countOps m capturingClosure?)) "closures with captures still allocate per evaluation")
            (assert (= (countOps h fieldedConstruct?) (countOps m fieldedConstruct?)) "constructors with fields still allocate per evaluation")
            (assert (< keys (+ (countOps m nullaryConstruct?) (countOps m capturelessClosure?))) "the two shadeDark sites share one singleton")
            (assert (= (listLength inits) keys) "one initialiser per distinct constant")
            (assert (= (listLength h.globals) (+ (listLength m.globals) keys)) "one global per distinct constant")
            (assert (= (listTake (map (fn [(g irTy/SsaGlobal)] -> String g.init) h.globals) keys) (map (fn [(f irTy/SsaFunction)] -> String f.name) inits)) "singleton globals come first, so module init fills them before any other global initialiser runs")
            (assert (listAll? (fn [(f irTy/SsaFunction)] -> Bool (and (listEmpty? f.params) (listEmpty? f.captures))) inits) "initialisers take no params and no captures")
            (assert (ok? (vfy/verifySsa h)) "the rewritten module verifies")
            (assert (= (opt/hoistConstants h) h) "the pass is idempotent")
            (assert (= (opt/hoistConstants (irTy/ssaModule "empty" (list) (list) (list) (list) (list) (list))) (irTy/ssaModule "empty" (list) (list) (list) (list) (list) (list))) "a module without constants is returned unchanged")
            true))))

fn ! testEmitted -> Bool
  (mt (lowered (probeSource))
    ((err e) (do (assert false (str "probe lowers: " e)) false))
    ((ok m)
      (let [(keysCtor (listLength (filter (fn [(i irTy/SsaInstr)] -> Bool (nullaryConstruct? i.op)) (userInstrs m))))
            (beforeRes (llvm/emitLlvmProgram m (entryOf m)))
            (afterRes (nat/emitLlvmProgram m (entryOf m)))
            (before (resultOr beforeRes ""))
            (after (resultOr afterRes ""))
            (ctorAlloc "@gcAsl.allocFast.0(i32 3, i64 16)")
            (fnAlloc "@gcAsl.allocFast.1(i32 4, i64 24)")]
        (do (assert (and (> (stringLength before) 0) (> (stringLength after) 0)) (str "the probe emits with and without the pass: " (diagsText beforeRes) " / " (diagsText afterRes)))
            (assert (>= (occurrences before ctorAlloc) keysCtor) "without the pass every nullary constructor site allocates")
            (assert (= (occurrences after ctorAlloc) 2) "with the pass the nullary constructors allocate once per singleton (shadeDark, none)")
            (assert (= (outsideInits after ctorAlloc) 0) "with the pass no function but a singleton initialiser allocates a nullary constructor")
            (assert (>= (outsideInits before fnAlloc) 2) "without the pass inc and the doubling lambda allocate a closure where they are used")
            (assert (= (outsideInits after fnAlloc) 0) (str "with the pass captureless closures allocate only in initialisers, got " (outsideInits after fnAlloc)))
            (refute (stringContains? (mainBody before) "call void @init.probe()") "a module without globals had no init call in main")
            (assert (stringContains? (mainBody after) "call void @init.probe()") "main runs the module init that fills the singletons")
            (assert (< (optionOr (stringIndexOf (mainBody after) "call void @init.probe()") 1000000) (optionOr (stringIndexOf (mainBody after) "call tailcc") 0)) "the init runs before the entry function")
            true))))

fn ! hostFacts -> (Result libc/TripleFacts String)
  (mt (run/shellOut "uname -s -m" 10000)
    ((err e) (err e))
    ((ok out) (mt (route/hostFactsOf (stringTrim out))
                ((err e) (err e))
                ((ok o) (mt o
                          ((none) (err (str "no triple facts for " (stringTrim out))))
                          ((some f) (ok f)))))))

fn ! testSeparateModule -> Bool
  (mt (lowered (libSource))
    ((err e) (do (assert false (str "probeLib lowers: " e)) false))
    ((ok m)
      (mt (hostFacts)
        ((err e) (do (assert false (str "host facts: " e)) false))
        ((ok f)
          (let [(plain (resultOr (llvm/emitLlvmModule m) ""))
                (text (resultOr (nat/emitLlvmModuleFor f m) ""))
                (entry "define i32 @main() {\nbb.entry:\n  call void @rterr.reportInit()\n  ret i32 0\n}\n")
                (linked (resultOr (llvm/linkInits entry (list "prelude" m.name)) ""))]
            (do (refute (llvm/definesInit? plain m.name) "without the pass a module with no top-level expression defines no init")
                (assert (llvm/definesInit? text m.name) "a separately compiled module (the --compile-units path) defines the init that fills its singletons, so its compile result records an init name")
                (assert (stringContains? linked "call void @init.probeLib()") "the entry links that init before it runs anything")
                true))))))

fn statsField text: String field: String -> Int64
  (let [(line (optionOr (listHead (filter (fn [(l String)] -> Bool (stringStartsWith? l "(:gcStats ")) (stringSplit text "\n"))) ""))
        (tokens (filter (fn [(t String)] -> Bool (not (stringEmpty? t))) (stringSplit line " ")))]
    (mt (listIndexOf tokens field)
      ((some i) (optionOr (stringToInt64 (stringReplace (optionOr (listGet tokens (+ i 1)) "") ")" "")) -1))
      ((none) -1)))

fn fixture name: String -> String
  (str "asl/packages/asl-target-llvm/tests/fixtures/ssaOpt/" name ".asl")

fn ! runBuilt built: nt/Built env: (List String) -> run/Done
  (mt built.binary
    ((none) (run/Done :idx 0 :exit 127 :out built.reason :ms 0 :verdict "notBuilt"))
    ((some bin) (run/runOneLimited (run/job (list bin) "." (run/childEnv env)) (run/limits 120 4))))

fn semanticsLines -> String
  (str "init true dark true false 42\n"
       "init true dark true false 42\n"
       "eq true true true false false false\n"
       "mt none none some7 light tinted3\n"
       "fn 3 4 18 11,12\n"
       "par true light 3|true dark 4|true dark 5\n"
       "parLambda some1,none,none\n")

fn ! testNative -> Bool
  (let [(workDir (str ".asl/cache/ssaOptTest-" (monotonicNs)))
        (cDir (str workDir "/cache"))
        (_ (dirCreate cDir))
        (spin (runBuilt (nt/prepareIn cDir (fixture "spin") "fp_ssaOpt" "run") (list "ASL_GC_STATS=1")))
        (objects (statsField spin.out ":objectsAllocated"))
        (sem (runBuilt (nt/prepareIn cDir (fixture "semantics") "fp_ssaOpt" "run") (list)))
        (wrapped (runBuilt (nt/prepareIn cDir (fixture "semanticsTest") "fp_ssaOpt" "test") (list)))
        (_ (pathRemove workDir))]
    (do (assert (= spin.exit 0) (str "spin exits 0: " spin.out))
        (assert (stringContains? spin.out "spin 1000000\n") "spin computes 1e6 through the singleton none and the hoisted lambda")
        (assert (and (>= objects 0) (< objects 10000)) (str "spin allocates O(1) objects over 1e6 evaluations, got " objects))
        (assert (= sem.exit 0) (str "semantics main exits 0: " sem.out))
        (assert (stringContains? sem.out (semanticsLines)) (str "main entry: module init, =, mt, function values and parMap workers agree with asl-host: " sem.out))
        (assert (= wrapped.exit 0) (str "semanticsTest under the test wrapper passes: " wrapped.out))
        (assert (stringContains? wrapped.out "init true dark true false 42") "the test wrapper entry runs the imported module init")
        true))

fn ! runTests -> Bool
  (and (testRewrite) (testNative) (testEmitted) (testSeparateModule))
