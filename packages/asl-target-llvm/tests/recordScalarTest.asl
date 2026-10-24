(module asl-target-llvm/tests/recordScalarTest
  :x [runTests]
  :i [(asl-ir/types :a irTy)
      (asl-ir/link :a lk)
      (asl-ir/verify :a vfy)
      (asl-target-llvm :a nat)
      (asl-target-llvm/ssaOpt :a opt)
      (asl-tools/nativeTest :a nt)
      (asl-tools/fleet/run :a run)])

fn fixture name: String -> String
  (str "asl/packages/asl-target-llvm/tests/fixtures/recordScalar/" name ".asl")

fn ! lowered name: String -> (Result irTy/SsaModule String)
  (match (fileReadString (lk/preludePath))
    ((err e) (err (str "cannot read the prelude: " e)))
    ((ok preludeSrc) (match (fileReadString (fixture name))
                       ((err e) (err (str "cannot read the fixture: " e)))
                       ((ok src) (match (lk/lowerSourceWith src preludeSrc)
                                   ((err ds) (err (stringJoin (map (fn [(d irTy/IrDiag)] -> String (str d.locus ": " d.message)) ds) "; ")))
                                   ((ok m) (ok m)))))))

fn baseName name: String -> String
  (optionOr (listLast (stringSplit name ".")) name)

fn named m: irTy/SsaModule name: String -> (Option irTy/SsaFunction)
  (listFind (fn [(f irTy/SsaFunction)] -> Bool (= (baseName f.name) name)) m.functions)

fn workers m: irTy/SsaModule -> (List String)
  (listSort (map (fn [(f irTy/SsaFunction)] -> String (baseName f.name)) (filter (fn [(f irTy/SsaFunction)] -> Bool (stringEndsWith? f.name "$sr")) m.functions)))

fn paramTypes f: (Option irTy/SsaFunction) -> (List String)
  (match f ((some g) (map (fn [(p irTy/SsaParam)] -> String (irTy/ssaTyName p.ty)) g.params)) ((none) (list)))

fn selfCall? f: irTy/SsaFunction ins: irTy/SsaInstr -> Bool
  (match ins.op ((irTy/opCall callee _) (= callee f.name)) (_ false))

fn record? ins: irTy/SsaInstr -> Bool
  (match ins.op ((irTy/opRecord _ _ _) true) (_ false))

; (:m :do "records built in the blocks that make a self call, the per-iteration allocations the pass removes")
fn loopRecords f: (Option irTy/SsaFunction) -> Int64
  (match f
    ((none) -1)
    ((some g) (fold (fn [(acc Int64) (b irTy/SsaBlock)] -> Int64
                      (if (listAny? (fn [(ins irTy/SsaInstr)] -> Bool (selfCall? g ins)) b.instrs) (+ acc (listCount record? b.instrs)) acc))
                    0 g.blocks)))

fn ! testShape -> Bool
  (match (lowered "loops")
    ((err e) (do (assert false (str "loops lowers: " e)) false))
    ((ok m)
      (let [(after (opt/nativePrelude m))
            (escaping (list "keep" "capture" "pass" "same" "rebuilt"))]
        (do (assert (= (workers after) (list "grow$sr" "hold$sr" "step$sr")) (str "exactly the three non-escaping record loops get a worker, got " (stringJoin (workers after) " ")))
            (assert (listAll? (fn [(n String)] -> Bool (and (some? (named m n)) (= (named after n) (named m n)))) escaping) "a record that is stored in a list, captured by a closure, passed to another function, compared or put in a list on exit stays one value: keep, capture, pass, same and rebuilt are unchanged")
            (assert (ok? (vfy/verifySsa after)) (str "the rewritten module verifies: " (match (vfy/verifySsa after) ((ok _) "ok") ((err ds) (stringJoin (map (fn [(d irTy/IrDiag)] -> String (str d.locus ": " d.message)) ds) "; ")))))
            (assert (= (paramTypes (named after "step$sr")) (list "i64" "i64" "i64" "i64")) (str "step's worker takes pos and vel as raw i64, got " (stringJoin (paramTypes (named after "step$sr")) " ")))
            (assert (= (paramTypes (named after "grow$sr")) (list "i64" "i64" "val" "i64" "f64")) (str "grow's worker keeps the String field a Val and unboxes count and ratio, got " (stringJoin (paramTypes (named after "grow$sr")) " ")))
            (assert (= (paramTypes (named after "step")) (paramTypes (named m "step"))) "the wrapper keeps the original signature for outside callers")
            (assert (= (loopRecords (named m "step")) 1) "before the pass the self-calling block of step builds one record per iteration")
            (assert (= (loopRecords (named after "step$sr")) 0) "after the pass the self-calling block of step's worker builds no record")
            (assert (= (loopRecords (named after "hold$sr")) 0) "a loop that passes the record on unchanged on one path and rebuilds it on another builds no record per iteration")
            (assert (= (opt/nativePrelude after) after) "the pass is idempotent")
            true))))

fn entryOf m: irTy/SsaModule -> String
  (optionOr (listHead (filter (fn [(n String)] -> Bool (or (= n "main") (stringEndsWith? n ".main"))) (map (fn [(f irTy/SsaFunction)] -> String f.name) m.functions))) "main")

fn label? line: String -> Bool
  (and (not (stringStartsWith? line " ")) (stringEndsWith? line ":"))

; (:m :do "the LLVM block that ends in the musttail self call of the step loop: its lines after the label")
fn tailBlock text: String -> (List String)
  (let [(lines (stringLines text))
        (at (listFind (fn [(e (Pair Int64 String))] -> Bool (and (stringContains? (pairSecond e) "musttail call") (stringContains? (pairSecond e) "step"))) (enumerate lines)))]
    (match at
      ((none) (list))
      ((some e) (let [(upto (listReverse (listTake lines (pairFirst e))))
                      (inBlock (fold (fn [(acc (Pair Bool (List String))) (l String)] -> (Pair Bool (List String))
                                       (if (or (pairFirst acc) (label? l)) (pair true (pairSecond acc)) (pair false (cons l (pairSecond acc)))))
                                     (pair false (list)) upto))]
                  (listAppend (pairSecond inBlock) (list (pairSecond e)))))))

fn ! testEmitted -> Bool
  (match (lowered "spin")
    ((err e) (do (assert false (str "spin lowers: " e)) false))
    ((ok m)
      (let [(res (nat/emitLlvmProgram m (entryOf m)))
            (text (resultOr res ""))
            (block (tailBlock text))]
        (do (assert (> (stringLength text) 0) "spin emits")
            (assert (> (listLength block) 0) "the step loop ends its iteration in a musttail self call")
            (refute (listAny? (fn [(l String)] -> Bool (stringContains? l "alloc")) block) (str "the block that makes the step loop's tail call allocates nothing: " (stringJoin block "\n")))
            true))))

fn ! runBuilt built: nt/Built env: (List String) -> run/Done
  (match built.binary
    ((none) (run/Done :idx 0 :exit 127 :out built.reason :ms 0 :verdict "notBuilt"))
    ((some bin) (run/runOneLimited (run/job (list bin) "." (run/childEnv env)) (run/limits 120 4))))

fn statsField text: String field: String -> Int64
  (let [(line (optionOr (listHead (filter (fn [(l String)] -> Bool (stringStartsWith? l "(:gcStats ")) (stringSplit text "\n"))) ""))
        (tokens (filter (fn [(t String)] -> Bool (not (stringEmpty? t))) (stringSplit line " ")))]
    (match (listIndexOf tokens field)
      ((some i) (optionOr (stringToInt64 (stringReplace (optionOr (listGet tokens (+ i 1)) "") ")" "")) -1))
      ((none) -1)))

; (:m :do "outputs of loops.asl worked out by hand and step's by bench/native/record.c, so they do not depend on either build")
fn loopsLines -> String
  (str "step 780/-39\n"
       "grow even 21 0.5\n"
       "hold 11007\n"
       "keep 13/2,12/2,11/2,10/2\n"
       "capture 7\n"
       "pass 57\n"
       "same 3\n"
       "rebuilt 13/2,13/2\n")

fn ! testNative -> Bool
  (let [(workDir (str ".asl/cache/recordScalarTest-" (monotonicNs)))
        (cDir (str workDir "/cache"))
        (_ (dirCreate cDir))
        (spin (runBuilt (nt/prepareIn cDir (fixture "spin") "fp_recordScalar" "run") (list "ASL_GC_STATS=1")))
        (objects (statsField spin.out ":objectsAllocated"))
        (loops (runBuilt (nt/prepareIn cDir (fixture "loops") "fp_recordScalar" "run") (list)))
        (_ (pathRemove workDir))]
    (do (assert (= spin.exit 0) (str "spin exits 0: " spin.out))
        (assert (stringContains? spin.out "spin 820 41\n") (str "spin computes what record.c computes for 1e6 steps: " spin.out))
        (assert (and (>= objects 0) (< objects 10000)) (str "spin allocates O(1) objects over 1e6 iterations, got " objects))
        (assert (= loops.exit 0) (str "loops exits 0: " loops.out))
        (assert (stringContains? loops.out (loopsLines)) (str "scalarized and escaping loops print the hand-computed values: " loops.out))
        true))

fn ! runTests -> Bool
  (and (testShape) (testEmitted) (testNative))
