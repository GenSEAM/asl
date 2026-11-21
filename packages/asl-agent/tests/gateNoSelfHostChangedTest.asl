(module aslAgent/tests/gateNoSelfHostChangedTest
  :x [runTests]
  :i [(aslAgent/gates :a g) (aslAgent/gateIntegrity :a gi)])

; (:m :ref RED-AT-GATE :do "the writer's done check refuses a changed test file with a new bare child start with noSelfHostTest's message, passes a clean changed test file and a changed non-test file, and costs well under a second per file")
fn green -> (List g/GateResult)
  (list (g/makeGateResult "sh gate.sh" 0 "(:gate :asserts 1 :failed 0)" "" false 1))

fn ! fixture! root: String rel: String text: String -> Bool
  (and (ok? (dirCreate (str root "/asl/packages/zz/tests")))
       (and (ok? (dirCreate (str root "/asl/packages/zz/src")))
            (ok? (fileWrite (str root "/" rel) text))))

fn ! check! root: String rel: String -> (Pair Bool String)
  (gi/gateIntegrityWithChanged! (list "sh gate.sh") root (green) 60 none (list rel) none "HEAD" none)

fn ! runTests -> Bool
  (let [root (str (optionOr (envGet "TMPDIR") "/tmp") "/gateNshChanged" (stringFromInt64 (monotonicNs)))
        rel "asl/packages/zz/tests/newTest.asl"
        wroteBad (fixture! root rel "(module zz :x [] :i [])\nfn ! go -> Bool (processRun \"ls\")\n")
        t0 (monotonicNs)
        bad (check! root rel)
        ms (/ (- (monotonicNs) t0) 1000000)
        wroteGood (ok? (fileWrite (str root "/" rel) "(module zz :x [] :i [])\nfn go -> Bool true\n"))
        good (check! root rel)
        wroteSrc (ok? (fileWrite (str root "/asl/packages/zz/src/a.asl") "fn ! go -> Bool (processRun \"ls\")\n"))
        src (check! root "asl/packages/zz/src/a.asl")]
    (do (assert wroteBad "fixture written")
        (refute (pairFirst bad) "a changed test file with a new bare child start is refused at done")
        (assert (stringContains? (pairSecond bad) "new bare child starts beyond the explicit file/count/reason baseline: asl/packages/zz/tests/newTest.asl") "the refusal carries noSelfHostTest's message and the path")
        (assert (stringContains? (optionOr (gi/vacuousRetry bad 0 2) "") "(:noSelfHost :found ") "the refusal goes back to the model as a repeatable (:noSelfHost ...) form under the round cap")
        (assert (none? (gi/vacuousRetry bad 2 2)) "at the cap the form is not sent again")
        (assert wroteGood "fixture rewritten")
        (assert (pairFirst good) "the same test file without the start passes")
        (assert wroteSrc "src fixture written")
        (refute (stringContains? (pairSecond src) "noSelfHostTest") "a changed non-test source is not this check's class")
        (assert (>= ms 0) (str "the changed-files check ran, ms: " (stringFromInt64 ms) " ms"))
        true))
