(module asl-ir/tests/quadScaleTest
  :x [wideModule workloadBytes main runTests]
  :i [(asl-ir/types :a ty)
      (asl-ir/link :a lk)
      (asl-ir/verify :a vfy)
      (asl-ir/printer :a prn)
      (tools/nativeTest :a nt)
      (tools/fleet/run :a fr)])

fn thisFile -> String
  "asl/packages/asl-ir/tests/quadScaleTest.asl"

fn leafFunction i: Int64 -> ty/SsaFunction
  (ty/ssaFunction (str "f" i) (list) (list (ty/ssaParam "x" (ty/tyVal))) (ty/tyVal)
                  (list (ty/ssaBlock "entry" (list) (list (ty/ssaInstr "%r" (ty/tyVal) (ty/opCall "g" (list "x")))) (ty/termReturn "%r"))))

fn callInstr i: Int64 -> ty/SsaInstr
  (ty/ssaInstr (str "%c" i) (ty/tyVal) (ty/opCall (str "f" i) (list "x")))

fn builtinInstr i: Int64 -> ty/SsaInstr
  (ty/ssaInstr (str "%b" i) (ty/tyVal) (ty/opBuiltin "wide" (list "x")))

fn wideFunction n: Int64 -> ty/SsaFunction
  (ty/ssaFunction "main" (list) (list (ty/ssaParam "x" (ty/tyVal))) (ty/tyVal)
                  (list (ty/ssaBlock "entry" (list) (listAppend (map callInstr (range 0 n)) (map builtinInstr (range 0 n))) (ty/termReturn "x"))))

fn wideModule n: Int64 -> ty/SsaModule
  (ty/ssaModule "q/wide" (list)
                (map (fn [(i Int64)] -> ty/SsaTypeDecl (ty/ssaTypeDecl (str "T" (/ i 2)) (list (ty/ssaVariant "v" 0)))) (range 0 n))
                (map (fn [(i Int64)] -> ty/SsaRecordDecl (ty/ssaRecordDecl (str "R" (/ i 2)) (list "a"))) (range 0 n))
                (list) (list)
                (cons (ty/ssaFunction "g" (list) (list (ty/ssaParam "x" (ty/tyVal))) (ty/tyVal) (list (ty/ssaBlock "entry" (list) (list) (ty/termReturn "x"))))
                      (cons (wideFunction n) (map leafFunction (range 0 n)))))

fn workload m: ty/SsaModule -> Int64
  (let [(mainFn (optionOr (listHead (filter (fn [(f ty/SsaFunction)] -> Bool (= f.name "main")) m.functions)) (wideFunction 0)))
        (perModule (map (fn [(f ty/SsaFunction)] -> ty/SsaModule (ty/ssaModule f.name (list) (list) (list) (list) (list) (list f))) m.functions))
        (rewritten (lk/rewriteModuleBuiltins (mapSet (mapEmpty) "wide" "g") m))]
    (+ (listLength (lk/firstByName m.types))
       (+ (listLength (lk/firstRecordByName m.records))
          (+ (listLength (lk/allFunctions perModule))
             (+ (listLength (lk/functionBuiltinRefs mainFn))
                (+ (listLength (vfy/verifySsaDiags rewritten))
                   (stringLength (prn/printSsa rewritten))))))))

; (:m :ref HLAUDIT-LOWS :do "SCALE-TESTS-LOAD-20261017: testWorkloadIsLinear used to compare procRusage CPU-microsecond deltas (measureOnce/cpuUs, dropped); that is a wall/CPU-time assertion, and it was already borderline red running alone (n=3000 68225us vs n=6000 171168us, ratio 2.509 against an 'above 2.5x' gate, confirmed by hand before this fix), the same class of flake the audit saw go red under a loaded train and green alone; workloadBytes below replaces it with the GC's own :bytesAllocated count (ASL_GC_STATS=1 on a self-built child, the same tools/nativeTest/tools/fleet/run pattern asl-ir/tests/lowerAllocTest.asl and this package's own lowerScaleTest.asl already use), a deterministic function of n and the algorithm, not of scheduling or system load")
fn ! statsLine text: String -> String
  (optionOr (listHead (filter (fn [(line String)] -> Bool (stringStartsWith? line "(:gcStats ")) (stringSplit text "\n"))) "")

fn ! bytesAllocated line: String -> Int64
  (let [(tokens (filter (fn [(t String)] -> Bool (not (stringEmpty? t))) (stringSplit line " ")))]
    (match (listIndexOf tokens ":bytesAllocated")
      ((some i) (optionOr (stringToInt64 (stringReplace (optionOr (listGet tokens (+ i 1)) "") ")" "")) -1))
      ((none) -1)))

fn ! main args: (List String) -> (Result Int64 String)
  (let [(n (optionOr (stringToInt64 (optionOr (listGet args 0) "")) -1))]
    (if (< n 0)
      (err "usage: quadScaleTest N")
      (let [(size (workload (wideModule n)))]
        (do (println (str "(quadScale :n " n " :size " size ")")) (ok 0)))))

fn ! workloadBytes n: Int64 -> Int64
  (let [(built (nt/prepareRun (thisFile) (nt/fingerprint)))]
    (match built.binary
      ((none) (do (assert false (str "quadScaleTest builds natively: " built.reason)) -1))
      ((some bin)
       (let [(done (fr/runOneLimited (fr/job (list bin (stringFromInt64 n)) "." (fr/childEnv (list "ASL_GC_STATS=1"))) (fr/limits 300 4)))]
         (do (assert (and (= done.exit 0) (stringContains? done.out (str "(quadScale :n " n " "))) (str n " run exits 0 (" done.verdict "): " done.out))
             (bytesAllocated (statsLine done.out)))))))

fn ! testWorkloadShape -> Bool
  (let [(m (wideModule 6))
        (rewritten (lk/rewriteModuleBuiltins (mapSet (mapEmpty) "wide" "g") m))
        (mainFn (optionOr (listHead (filter (fn [(f ty/SsaFunction)] -> Bool (= f.name "main")) rewritten.functions)) (wideFunction 0)))
        (text (prn/printSsa rewritten))]
    (do (assert (= (map (fn [(d ty/SsaTypeDecl)] -> String d.name) (lk/firstByName m.types)) (list "T0" "T1" "T2")) "firstByName keeps the first of each name in order")
        (assert (= (map (fn [(d ty/SsaRecordDecl)] -> String d.name) (lk/firstRecordByName m.records)) (list "R0" "R1" "R2")) "firstRecordByName keeps the first of each name in order")
        (assert (= (listLength (lk/functionBuiltinRefs (wideFunction 6))) 6) "every builtin instruction is a builtin reference")
        (assert (= (listLength mainFn.blocks) 1) "the rewritten main keeps one block")
        (assert (stringContains? text "(let %b5 val (call g x))") (str "the builtin calls are rewritten to the resolved function in order:\n" text))
        (assert (= (map (fn [(d ty/IrDiag)] -> String d.locus) (vfy/verifySsaDiags rewritten)) (list "q/wide/T0" "q/wide/T1" "q/wide/T2" "q/wide/R0" "q/wide/R1" "q/wide/R2"))
                (str "verify reports each repeated type and record once, in declaration order: " (vfy/verifySsaDiags rewritten)))
        true))

fn ! testWorkloadIsLinear -> Bool
  (let [(small (workloadBytes 3000))
        (large (workloadBytes 6000))]
    (do (assert (> small 0) "the 3000-wide workload is measured")
        (assert (<= (* large 10) (* small 23))
                (str "link merge, builtin rewrite, verify and print of a module with n functions, n types and a 2n-instruction block scale linearly: 2x n allocates "
                     large " bytes vs " small " bytes, above 2.3x"))
        true))

fn ! runTests -> Bool
  (do (assert (testWorkloadShape) "testWorkloadShape")
      (assert (testWorkloadIsLinear) "testWorkloadIsLinear")
      true)
