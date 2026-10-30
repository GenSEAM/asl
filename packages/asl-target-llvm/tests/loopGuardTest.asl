(module asl-target-llvm/tests/loopGuardTest
  :x [runTests]
  :i [(asl-ir/link :a lk)
      (asl-ir/types :a irTy)
      (asl-target-llvm :a llvm)
      (asl-target-llvm/ssaOpt :a opt)
      (asl-target-llvm/arrayRoute :a ar)
      (asl-target-llvm/loopGuard :a lg)
      (asl-target-llvm/ssa :a ssa)
      (asl-target-llvm/tests/rcTest :a rc)])

fn fixture -> String
  "asl/packages/asl-target-llvm/tests/fixtures/loopGuard/loopGuard.asl"

; (:m :ref LOOPGUARD :do "recorded from the base build (sh/WAVE2 119a14403, no loopGuard): stdout of the ok run, and exit 1 with the one stderr line of each failing run")
fn okExpected -> String
  (stringJoin (list "bytes 12749680" "bytesFrom 12523603" "bytesEmpty 3" "bytesNearMax 9223372036854126940" "bytesZeroNearMax 9223372036854775800"
                    "bytesNegAcc -9223372036842026127" "bytesEven 6399552" "ints -15291840" "intsFrom -8054489" "intsEmpty 3" "intsBig 49"
                    "intsBigAcc 4611686018412096064" "")
              "\n")

fn failures -> (List (Pair String String))
  (list (pair "bytesPast" "ERR_RANGE: bytesGet: slot 100000 outside 100000 bytes")
        (pair "bytesNeg" "ERR_RANGE: bytesGet: slot -3 outside 100000 bytes")
        (pair "bytesOver" "ERR_INT_OVERFLOW: Int + leaves int64")
        (pair "bytesBehind" "ERR_RANGE: bytesGet: slot 100000 outside 100000 bytes")
        (pair "intsPast" "ERR_RANGE: i64ArrayGet index 100000 outside length 100000")
        (pair "intsNeg" "ERR_RANGE: i64ArrayGet index -3 outside length 100000")
        (pair "intsOver" "ERR_INT_OVERFLOW: Int + leaves int64")
        (pair "intsUnder" "ERR_INT_OVERFLOW: Int + leaves int64")
        (pair "intsHuge" "ERR_INT_OVERFLOW: Int + leaves int64"))

fn named m: irTy/SsaModule name: String -> (Option irTy/SsaFunction)
  (listHead (filter (fn [(f irTy/SsaFunction)] -> Bool (= f.name name)) m.functions))

fn callees f: irTy/SsaFunction -> (List String)
  (listFlatMap (fn [(b irTy/SsaBlock)] -> (List String)
                 (listFlatMap (fn [(i irTy/SsaInstr)] -> (List String) (match i.op ((irTy/opCall n _) (list n)) (_ (list)))) b.instrs))
               f.blocks)

fn prims f: irTy/SsaFunction label: String -> (List String)
  (listFlatMap (fn [(b irTy/SsaBlock)] -> (List String)
                 (if (= b.label label) (listFlatMap (fn [(i irTy/SsaInstr)] -> (List String) (match i.op ((irTy/opPrim n _) (list n)) (_ (list)))) b.instrs) (list)))
               f.blocks)

fn ! guarded name: String m: irTy/SsaModule -> Bool
  (match (named m name)
    ((none) (do (assert false (str name " is in the module")) false))
    ((some f) (do (refute (listContains? (callees f) name) (str name ": the guarded entry no longer calls itself"))
                  (assert (listContains? (callees f) (lg/checkedName name)) (str name ": the guarded entry falls back to the checked loop"))
                  (assert (some? (named m (lg/checkedName name))) (str name ": the checked loop is kept"))
                  true)))

; (:m :ref LOOPGUARD :do "on the routed module: the Bytes and I64Array sums are versioned, the Bytes fast loop adds without the overflow check, the I64Array one calls its kernel; a loop stepping by 2 keeps its shape; the pass is idempotent")
fn ! testShape -> Bool
  (match (lk/linkEntry! (fixture))
    ((err ds) (do (assert false (str "fixture links: " (rc/diagText ds))) false))
    ((ok m)
      (match (ar/routeLinked (opt/nativePrelude m))
        ((err ds) (do (assert false (str "fixture routes: " (rc/diagText ds))) false))
        ((ok routed)
          (let [(h (opt/hoistConstants routed.result))
                (bytes (optionOr (named h "loopGuard.sumBytes") (irTy/ssaFunction "" (list) (list) (irTy/tyI64) (list))))
                (ints (optionOr (named h "loopGuard.sumInts") (irTy/ssaFunction "" (list) (list) (irTy/tyI64) (list))))]
            (do (assert (guarded "loopGuard.sumBytes" h) "sumBytes is versioned")
                (assert (guarded "loopGuard.sumInts" h) "sumInts is versioned")
                (assert (= (prims bytes "lg.body") (list "rawAddI64" "rawAddI64")) (str "the Bytes fast loop adds raw: " (stringJoin (prims bytes "lg.body") " ")))
                (assert (listContains? (callees ints) (lg/kernelName "loopGuard.sumInts")) "the I64Array entry calls its kernel")
                (assert (some? (named h (lg/kernelName "loopGuard.sumInts"))) "the I64Array kernel is added")
                (assert (none? (named h (lg/checkedName "loopGuard.sumEven"))) "a loop stepping by 2 is not versioned")
                (assert (listContains? (callees (optionOr (named h "loopGuard.sumEven") bytes)) "loopGuard.sumEven") "a loop stepping by 2 still calls itself")
                (assert (= (lg/guardLoops h) h) "guardLoops is idempotent")
                true))))))

fn ! write! path: String text: String -> Bool
  (match (fileWrite path text) ((ok _) true) ((err e) (do (assert false (str "cannot write " path ": " e)) false)))

; (:m :do "the lines of the function the text defines under the quoted symbol s, from its define line to its closing brace")
fn bodyOf text: String s: String -> (List String)
  (pairSecond
    (fold (fn [(acc (Pair Int64 (List String))) (l String)] -> (Pair Int64 (List String))
            (cond
              ((= (pairFirst acc) 2) acc)
              ((= (pairFirst acc) 1) (if (= l "}") (pair 2 (pairSecond acc)) (pair 1 (listAppend (pairSecond acc) (list l)))))
              ((and (stringStartsWith? l "define ") (stringContains? l (str s "\"("))) (pair 1 (list l)))
              (else acc)))
          (pair 0 (list)) (stringLines text)))

; (:m :do "the lines of the block labelled vector.body inside a function body, up to the blank line that ends it")
fn vectorBody body: (List String) -> (List String)
  (pairSecond
    (fold (fn [(acc (Pair Int64 (List String))) (l String)] -> (Pair Int64 (List String))
            (cond
              ((= (pairFirst acc) 2) acc)
              ((= (pairFirst acc) 1) (if (stringEmpty? (stringTrim l)) (pair 2 (pairSecond acc)) (pair 1 (listAppend (pairSecond acc) (list l)))))
              ((stringStartsWith? l "vector.body:") (pair 1 (list l)))
              (else acc)))
          (pair 0 (list)) body))

fn ! vectorized text: String name: String -> Bool
  (let [(body (bodyOf text (str "@\"" name)))
        (vec (vectorBody body))]
    (do (assert (> (listLength body) 0) (str name ": the function is in the optimised IR"))
        (assert (> (listLength vec) 1) (str name ": clang -O2 vectorizes the loop (a vector.body block)"))
        (refute (listAny? (fn [(l String)] -> Bool (stringContains? l " call ")) vec) (str name ": the vector body calls nothing (no trap, no runtime)"))
        (refute (listAny? (fn [(l String)] -> Bool (stringContains? l "with.overflow")) vec) (str name ": the vector body has no overflow check"))
        true))

fn ! emit! mode: String -> (Result String String)
  (match (lk/linkEntry! (fixture))
    ((err ds) (err (str "fixture links: " (rc/diagText ds))))
    ((ok m) (match (llvm/emitLlvmProgramNativeWith! m (str m.name ".main") mode)
              ((err ds) (err (str "fixture emits in mode " mode ": " (rc/diagText ds))))
              ((ok code) (ok code)))))

; (:m :ref LOOPGUARD :do "clang -O2 over the emitted module turns the Bytes loop and the I64Array kernel into vector loops with no call and no overflow check; the base build keeps a scalar loop with a range check and an overflow trap per element")
fn ! testIr dir: String -> Bool
  (match (emit! "0")
    ((err e) (do (assert false e) false))
    ((ok code)
      (let [(ll (str dir "/loopGuard.ir.ll")) (opt (str dir "/loopGuard.opt.ll"))]
        (if (not (write! ll code))
          false
          (let [(r (rc/sh (str "/usr/bin/clang -O2 -S -emit-llvm -Wno-override-module -x ir " (rc/shellQuote ll) " -o " (rc/shellQuote opt))))
                (text (resultOr (fileReadString opt) ""))
                (kernel (lg/kernelName "loopGuard.sumInts"))]
            (do (assert (= r.exitCode 0) (str "clang -O2 -emit-llvm exits 0: " r.stderr))
                (assert (vectorized text (ssa/llvmName "loopGuard.sumBytes")) "the Bytes sum is a vector loop")
                (assert (or (> (listLength (vectorBody (bodyOf text (str "@\"" (ssa/llvmName "loopGuard.sumInts"))))) 1)
                            (> (listLength (vectorBody (bodyOf text (str "@\"" (ssa/llvmName kernel))))) 1))
                        "the I64Array sum (its entry or its kernel) is a vector loop")
                true))))))

fn ! buildExe! libs: rc/Libs dir: String mode: String -> (Result String String)
  (match (emit! mode)
    ((err e) (err e))
    ((ok code)
      (let [(ll (str dir "/loopGuard." mode ".ll")) (exe (str dir "/loopGuard." mode))]
        (match (fileWrite ll code)
          ((err e) (err (str "cannot write " ll ": " e)))
          ((ok _) (let [(linked (rc/sh (rc/linkCmd libs mode ll exe)))]
                    (if (!= linked.exitCode 0) (err (str "fixture " mode " links: " linked.stderr)) (ok exe))))))))

; (:m :ref LOOPGUARD :do "under tracing and untraced RC the versioned fixture prints what the base build prints, and every failing run exits 1 with the base build's error line: the same index for a read past either end or behind the bound, the same overflow error")
fn ! testRun libs: rc/Libs dir: String mode: String -> Bool
  (match (buildExe! libs dir mode)
    ((err e) (do (assert false e) false))
    ((ok exe)
      (let [(okRun (rc/sh (str (rc/shellQuote exe) " ok")))]
        (do (assert (= okRun.exitCode 0) (str mode " ok run exits 0: " okRun.stderr))
            (assert (= okRun.stdout (okExpected)) (str mode " ok run prints the base sums: " okRun.stdout))
            (fold (fn [(acc Bool) (c (Pair String String))] -> Bool
                    (let [(r (rc/sh (str (rc/shellQuote exe) " " (pairFirst c))))]
                      (do (assert (= r.exitCode 1) (str mode " " (pairFirst c) " exits 1, got " r.exitCode))
                          (assert (= r.stdout "") (str mode " " (pairFirst c) " prints no sum: " r.stdout))
                          (assert (= (optionOr (listHead (stringLines r.stderr)) "") (pairSecond c)) (str mode " " (pairFirst c) " fails as the base build: " r.stderr))
                          acc)))
                  true (failures))))))

fn ! clean dir: String -> Bool
  (let [(names (resultOr (dirList dir) (list)))]
    (do (fold (fn [(acc Bool) (n String)] -> Bool (and (ok? (pathRemove (str dir "/" n))) acc)) true names)
        (ok? (pathRemove dir))))

fn ! runTests -> Bool
  (let [(dir (str (optionOr (envGet "TMPDIR") "/tmp") "/loopGuardTest." (procSelf) "." (monotonicNs)))
        (made (dirCreate dir))]
    (do (assert (ok? made) "work directory created")
        (assert (testShape) "the sum loops are versioned on the routed module")
        (assert (testIr dir) "the fast loops vectorize")
        (match (rc/runtimes!)
          ((err e) (assert false (str "runtimes: " e)))
          ((ok libs) (do (assert (testRun libs dir "0") "tracing build fails and sums as the base build")
                         (assert (testRun libs dir "notrace") "untraced RC build fails and sums as the base build"))))
        (assert (clean dir) "work directory removed")
        true))
