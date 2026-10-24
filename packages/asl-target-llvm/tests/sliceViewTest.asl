(module asl-target-llvm/tests/sliceViewTest
  :x [runTests]
  :i [(asl-ir/link :a lk)
      (asl-ir/types :a irTy)
      (asl-target-llvm :a llvm)
      (asl-target-llvm/arrayRoute :a ar)
      (asl-target-llvm/tests/rcTest :a rc)])

fn fixture -> String
  "asl/packages/asl-target-llvm/tests/fixtures/sliceView/sliceView.asl"

fn okExpected -> String
  "91766000 91766000\n7.0 1.5 3 0 7\n9223372036854775806\n"

fn calleesOf m: irTy/SsaModule name: String -> (List String)
  (fold (fn [(acc (List String)) (f irTy/SsaFunction)] -> (List String)
          (if (!= f.name name) acc
            (fold (fn [(acc2 (List String)) (b irTy/SsaBlock)] -> (List String)
                    (fold (fn [(acc3 (List String)) (i irTy/SsaInstr)] -> (List String)
                            (match i.op ((irTy/opCall n _) (listAppend acc3 (list n))) (_ acc3)))
                          acc2 b.instrs))
                  acc f.blocks)))
        (list) m.functions)

fn argsOf m: irTy/SsaModule name: String callee: String -> (List (List String))
  (fold (fn [(acc (List (List String))) (f irTy/SsaFunction)] -> (List (List String))
          (if (!= f.name name) acc
            (fold (fn [(acc2 (List (List String))) (b irTy/SsaBlock)] -> (List (List String))
                    (fold (fn [(acc3 (List (List String))) (i irTy/SsaInstr)] -> (List (List String))
                            (match i.op ((irTy/opCall n args) (if (= n callee) (listAppend acc3 (list args)) acc3)) (_ acc3)))
                          acc2 b.instrs))
                  acc f.blocks)))
        (list) m.functions)

fn arr op: String -> String
  (str "asl-target-llvm/arrays." op)

; (:m :ref SLICEVIEW :do "the route fuses a slice read only by readers in its block into them, and keeps the copy for a slice that escapes into a list or one an effect separates from its first reader")
fn ! testRoute -> Bool
  (match (lk/linkEntry! (fixture))
    ((err ds) (do (assert false (str "fixture links: " (rc/diagText ds))) false))
    ((ok m)
      (match (ar/routeLinked m)
        ((err ds) (do (assert false (str "fixture routes: " (rc/diagText ds))) false))
        ((ok routed)
          (let [(r routed.result)
                (fusedCalls (calleesOf r "sliceView.fused"))
                (sums (argsOf r "sliceView.fused" (arr "i64ArraySum")))
                (plainSums (argsOf r "sliceView.copied" (arr "i64ArraySum")))]
            (do (refute (listContains? fusedCalls (arr "i64ArraySlice")) (str "fused: no slice copy is called: " (stringJoin fusedCalls " ")))
                (assert (= (listLength sums) 1) "fused: one sum")
                (assert (= (listLength (optionOr (listHead sums) (list))) 3) "fused: the sum takes the parent and the window")
                (assert (listContains? (calleesOf r "sliceView.copied") (arr "i64ArraySlice")) "copied: a slice kept in a list is still copied")
                (assert (= (listLength (optionOr (listHead plainSums) (list))) 3) "copied: the whole-array sum takes a Unit window")
                (assert (listContains? (calleesOf r "sliceView.ordered") (arr "i64ArraySlice")) "ordered: a slice an effect separates from its reader is still copied")
                (refute (listContains? (calleesOf r "sliceView.kinds") (arr "f64ArraySlice")) "kinds: an F64Array slice fuses")
                (refute (listContains? (calleesOf r "sliceView.kinds") (arr "i8ArraySlice")) "kinds: an I8Array slice fuses")
                true))))))

fn ! buildExe! libs: rc/Libs dir: String mode: String -> (Result String String)
  (match (lk/linkEntry! (fixture))
    ((err ds) (err (str "fixture links: " (rc/diagText ds))))
    ((ok m)
     (match (llvm/emitLlvmProgramNativeWith! m (str m.name ".main") mode)
       ((err ds) (err (str "fixture emits in mode " mode ": " (rc/diagText ds))))
       ((ok code)
        (let [(ll (str dir "/sliceView." mode ".ll"))
              (exe (str dir "/sliceView." mode))]
          (match (fileWrite ll code)
            ((err e) (err (str "cannot write " ll ": " e)))
            ((ok _)
             (let [(linked (rc/sh (rc/linkCmd libs mode ll exe)))]
               (if (!= linked.exitCode 0) (err (str "fixture " mode " links: " linked.stderr)) (ok exe))))))))))

fn ! runMode exe: String arg: String -> rc/Captured
  (rc/sh (str (rc/shellQuote exe) " " arg))

; (:m :ref SLICEVIEW :do "a fused slice allocates no element storage: of the ok run's large objects only the five generated arrays and the 1000 slices kept in a list remain (2008 with copying slices), every one freed, nothing pinned or stuck, the output equal to copy semantics under tracing, RC and RC with ASan")
fn ! testRun libs: rc/Libs dir: String -> Bool
  (match (buildExe! libs dir "0")
    ((err e) (do (assert false e) false))
    ((ok traced)
      (match (buildExe! libs dir "notrace")
        ((err e) (do (assert false e) false))
        ((ok counted)
          (match (buildExe! libs dir "asanNotrace")
            ((err e) (do (assert false e) false))
            ((ok asan)
              (let [(t (runMode traced "ok"))
                    (c (runMode counted "ok"))
                    (a (runMode asan "ok"))
                    (stats c.stderr)]
                (do (assert (= t.exitCode 0) (str "tracing exits 0: " t.stderr))
                    (assert (= t.stdout (okExpected)) (str "tracing output: " t.stdout))
                    (assert (= c.exitCode 0) (str "RC exits 0: " c.stderr))
                    (assert (= c.stdout (okExpected)) (str "RC output: " c.stdout))
                    (assert (= a.exitCode 0) (str "RC ASan exits 0: " a.stderr))
                    (assert (= a.stdout (okExpected)) (str "RC ASan output: " a.stdout))
                    (refute (stringContains? a.stderr "Sanitizer") (str "ASan reports nothing: " a.stderr))
                    (assert (= (rc/statOf stats "large") 1005) (str "only the generated arrays and the listed copies are large objects: " stats))
                    (assert (= (rc/statOf stats "largeFreed") 1005) (str "every large object, the parents included, is freed: " stats))
                    (assert (= (rc/statOf stats "pinned") 0) (str "nothing pinned: " stats))
                    (assert (= (rc/statOf stats "stuck") 0) (str "nothing stuck: " stats))
                    (testErrors traced counted)))))))))

; (:m :ref SLICEVIEW :do "a fused slice raises as the copy did: its range error under its own name before an effect that follows it, a read past the view against the view's length, a partial sum that leaves int64 although the total fits")
fn ! testErrors traced: String counted: String -> Bool
  (fold (fn [(acc Bool) (exe String)] -> Bool
          (let [(range (runMode exe "range"))
                (get (runMode exe "get"))
                (ovf (runMode exe "ovf"))
                (order (runMode exe "order"))]
            (do (assert (and (!= range.exitCode 0) (stringContains? range.stderr "ERR_RANGE: i64ArraySlice [5, 2) outside length 1000")) (str exe " range: " range.stderr))
                (assert (and (!= get.exitCode 0) (stringContains? get.stderr "ERR_RANGE: i64ArrayGet index 4 outside length 2")) (str exe " get: " get.stderr))
                (assert (and (!= ovf.exitCode 0) (stringContains? ovf.stderr "ERR_INT_OVERFLOW: i64ArraySum leaves int64")) (str exe " ovf: " ovf.stderr))
                (assert (and (!= order.exitCode 0) (stringContains? order.stderr "ERR_RANGE: i64ArraySlice [5, 2) outside length 1000")) (str exe " order: " order.stderr))
                (refute (stringContains? order.stdout "between") (str exe " order: the slice raises before the effect after it: " order.stdout))
                acc)))
        true (list traced counted))

fn ! clean dir: String -> Bool
  (do (map (fn [(e String)] -> Bool (ok? (pathRemove (str dir "/" e)))) (resultOr (dirList dir) (list)))
      (ok? (pathRemove dir)))

fn ! runTests -> Bool
  (let [(dir (str (optionOr (envGet "TMPDIR") "/tmp") "/sliceViewTest." (procSelf) "." (monotonicNs)))
        (made (dirCreate dir))]
    (do (assert (ok? made) "work directory created")
        (assert (testRoute) "the route fuses read-only slices and copies the others")
        (match (rc/runtimes!)
          ((err e) (assert false (str "runtimes: " e)))
          ((ok libs) (assert (testRun libs dir) "fused slices run as copies do, allocating no element storage")))
        (clean dir)
        true))
