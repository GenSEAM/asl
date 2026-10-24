(module asl-target-llvm/tests/listReverseTest
  :x [runTests]
  :i [(asl-ir/link :a lk)
      (asl-target-llvm :a llvm)
      (asl-target-llvm/tests/rcTest :a rc)])

fn fixture -> String
  "asl/packages/asl-target-llvm/tests/fixtures/listReverse/listReverse.asl"

; (:m :ref RINGSOA :do "oracle from the List semantics: big is 0..99999 so the weighted sum is the sum of squares below 100000; a prefix of unique cells over a shared tail, a shared list, strings, a double reverse and the empty list")
fn want -> String
  "333328333350000 100000\n3,2,1,8,9 3,2,1 1,2,3\nc,b3,a 4,3,2,1,0 0\n"

fn ownedCall -> String
  "call tailcc %Val @aslRc.reverseOwned("

fn ! build! libs: rc/Libs dir: String mode: String -> (Result (Pair String rc/Captured) String)
  (match (lk/linkEntry! (fixture))
    ((err ds) (err (str "fixture links: " (rc/diagText ds))))
    ((ok m) (match (llvm/emitLlvmProgramNativeWith! m (str m.name ".main") mode)
              ((err ds) (err (str "fixture emits in mode " mode ": " (rc/diagText ds))))
              ((ok code)
                (let [(ll (str dir "/listReverse." mode ".ll")) (exe (str dir "/listReverse." mode))]
                  (match (fileWrite ll code)
                    ((err e) (err (str "cannot write " ll ": " e)))
                    ((ok _) (let [(linked (rc/sh (rc/linkCmd libs mode ll exe)))]
                              (if (!= linked.exitCode 0)
                                (err (str "fixture " mode " links: " linked.stderr))
                                (ok (pair code (rc/sh (rc/shellQuote exe)))))))))))))

fn ! testMode libs: rc/Libs dir: String mode: String routed: Bool -> Bool
  (match (build! libs dir mode)
    ((err e) (do (assert false e) false))
    ((ok built)
      (let [(code (pairFirst built)) (run (pairSecond built))]
        (do (assert (= run.exitCode 0) (str mode " exits 0: " run.stderr))
            (assert (= run.stdout (want)) (str mode " prints what the List semantics give: " run.stdout))
            (refute (stringContains? run.stderr "Sanitizer") (str mode " reads no released cell and changes no shared one: " run.stderr))
            (if routed
              (assert (stringContains? code (ownedCall)) (str mode " routes listReverse calls to the owned reverse"))
              (refute (stringContains? code (ownedCall)) (str mode " keeps the copying listReverse")))
            true))))

; (:m :ref RINGSOA :do "reversing a unique list relinks its cells: the copying reverse resets one cell per element and reuses it for the new cons, so the ASan-mode reset and fbip counts reach the 100000 cells of big (base 1bb9e4c0: resets 100026, fbip 100020); the owned one resets none of them")
fn ! testRelink libs: rc/Libs dir: String -> Bool
  (match (build! libs dir "asanNotrace")
    ((err e) (do (assert false e) false))
    ((ok built)
      (let [(run (pairSecond built)) (resets (rc/statOf run.stderr "resets")) (fbip (rc/statOf run.stderr "fbip"))]
        (do (assert (= run.stdout (want)) (str "asanNotrace prints the oracle: " run.stdout))
            (assert (and (>= resets 0) (< resets 1000)) (str "a unique list is reversed in place, no cell reset: resets " resets ", base 100026, in " run.stderr))
            (assert (and (>= fbip 0) (< fbip 1000)) (str "a unique list is reversed in place, no cell reused for a new cons: fbip " fbip ", base 100020, in " run.stderr))
            true))))

fn ! clean dir: String -> Bool
  (let [(names (resultOr (dirList dir) (list)))]
    (do (fold (fn [(acc Bool) (n String)] -> Bool (and (ok? (pathRemove (str dir "/" n))) acc)) true names)
        (ok? (pathRemove dir))))

fn ! runTests -> Bool
  (let [(dir (str (optionOr (envGet "TMPDIR") "/tmp") "/listReverseTest." (procSelf) "." (monotonicNs)))
        (made (dirCreate dir))]
    (do (assert (ok? made) "work directory created")
        (match (rc/runtimes!)
          ((err e) (assert false (str "runtimes: " e)))
          ((ok libs) (do (assert (testMode libs dir "0" false) "tracing build")
                         (assert (testMode libs dir "notrace" true) "untraced RC build")
                         (assert (testMode libs dir "asanNotrace" true) "untraced RC build under ASan")
                         (assert (testRelink libs dir) "untraced RC reverses a unique list in place"))))
        (assert (clean dir) "work directory removed")
        true))
