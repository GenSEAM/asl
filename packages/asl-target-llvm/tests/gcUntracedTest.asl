(module asl-target-llvm/tests/gcUntracedTest
  :x [runTests]
  :i [(asl-ir/link :a lk)
      (asl-target-llvm :a llvm)
      (asl-target-llvm/libc :a libc)
      (asl-target-llvm/target :a target)
      (asl-target-llvm/gcRoute :a gr)
      (asl-target-llvm/tests/rcTest :a rc)])

fn fixture -> String
  "asl/packages/asl-target-llvm/tests/fixtures/gcUntraced/gcUntraced.asl"

; (:m :ref RINGSOA :do "oracle from the fixture: a million two-field records, about 80 MB of cells, past the 32 MiB first threshold; the sum of a + b = 4i over i below 1000000")
fn want -> String
  "1999998000000 1000000\n"

fn never -> String
  "%never = bitcast i64 9223372036854775807 to i64"

fn ! hostTriple -> String
  (let [(k (stringTrim (rc/sh "uname -s").stdout)) (m (stringTrim (rc/sh "uname -m").stdout))]
    (cond
      ((and (= k "Darwin") (= m "arm64")) "darwin-arm64")
      ((and (= k "Linux") (= m "x86_64")) "linux-x86_64")
      ((and (= k "Linux") (or (= m "aarch64") (= m "arm64"))) "linux-aarch64")
      (else "")))

; (:m :ref RINGSOA :do "the untraced runtime's init stores a threshold no allocated count reaches, so the inline fast path never turns to the slow path for a collection that never runs; the traced runtime keeps its ASL_GC_MIN_MIB threshold")
fn ! testThreshold -> Bool
  (match (libc/libcFacts (hostTriple))
    ((none) (do (assert false "libc facts for this host") false))
    ((some facts)
      (let [(tf (target/nativeTargetFacts facts.triple))]
        (match (gr/collectorTextWith facts tf true)
          ((err _) (do (assert false "untraced collector text") false))
          ((ok untraced) (match (gr/collectorTextWith facts tf false)
                           ((err _) (do (assert false "traced collector text") false))
                           ((ok traced) (do (assert (stringContains? untraced (never)) "the untraced runtime builds a threshold past any allocated count")
                                            (assert (stringContains? untraced "store i64 %never, ptr %w6.p.gep") "the untraced runtime's init stores it as the threshold")
                                            (refute (stringContains? traced (never)) "the traced runtime keeps a finite threshold")
                                            true))))))))

fn ! build! libs: rc/Libs dir: String mode: String -> (Result rc/Captured String)
  (match (lk/linkEntry! (fixture))
    ((err ds) (err (str "fixture links: " (rc/diagText ds))))
    ((ok m) (match (llvm/emitLlvmProgramNativeWith! m (str m.name ".main") mode)
              ((err ds) (err (str "fixture emits in mode " mode ": " (rc/diagText ds))))
              ((ok code)
                (let [(ll (str dir "/gcUntraced." mode ".ll")) (exe (str dir "/gcUntraced." mode))]
                  (match (fileWrite ll code)
                    ((err e) (err (str "cannot write " ll ": " e)))
                    ((ok _) (let [(linked (rc/sh (rc/linkCmd libs mode ll exe)))]
                              (if (!= linked.exitCode 0)
                                (err (str "fixture " mode " links: " linked.stderr))
                                (ok (rc/sh (rc/shellQuote exe))))))))))))

fn ! testMode libs: rc/Libs dir: String mode: String -> Bool
  (match (build! libs dir mode)
    ((err e) (do (assert false e) false))
    ((ok run) (do (assert (= run.exitCode 0) (str mode " exits 0: " run.stderr))
                  (assert (= run.stdout (want)) (str mode " prints the oracle past the first threshold: " run.stdout))
                  true)))

fn ! clean dir: String -> Bool
  (let [(names (resultOr (dirList dir) (list)))]
    (do (fold (fn [(acc Bool) (n String)] -> Bool (and (ok? (pathRemove (str dir "/" n))) acc)) true names)
        (ok? (pathRemove dir))))

fn ! runTests -> Bool
  (let [(dir (str (optionOr (envGet "TMPDIR") "/tmp") "/gcUntracedTest." (procSelf) "." (monotonicNs)))
        (made (dirCreate dir))]
    (do (assert (ok? made) "work directory created")
        (assert (testThreshold) "untraced threshold")
        (match (rc/runtimes!)
          ((err e) (assert false (str "runtimes: " e)))
          ((ok libs) (do (assert (testMode libs dir "0") "tracing build")
                         (assert (testMode libs dir "notrace") "untraced RC build")
                         (assert (testMode libs dir "asanNotrace") "untraced RC build under ASan"))))
        (assert (clean dir) "work directory removed")
        true))
