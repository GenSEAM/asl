(module asl-tools/fleet/tests/gateVerdictTest
  :x [runTests]
  :i [(asl-tools/fleet/run :a fr)])

; (:m :ref GATEINTEGRITY-TIMEOUT-PASSES :do "gateVerdict over real runs and built ones: a run the runner ended at its timeout is timeout, never red, and so is a failed run that reports a timeout below it; only a run that ended by itself non-zero is red evidence. Also the pure parts of the load gate and the wall fit")

fn done exit: Int64 verdict: String out: String -> fr/Done
  (fr/Done :idx 0 :exit exit :out out :ms 1 :verdict verdict)

fn ! runTests -> Bool
  (let [(late (fr/runOneLimited (fr/job (list "sh" "-c" "echo FAIL x.asl: ERR_ASSERT: early; sleep 43") "/" (fr/childEnv (list))) (fr/limits 1 8)))
        (red (fr/runOneLimited (fr/job (list "sh" "-c" "exit 3") "/" (fr/childEnv (list))) (fr/limits 30 8)))
        (pass (fr/runOneLimited (fr/job (list "true") "/" (fr/childEnv (list))) (fr/limits 30 8)))
        (left (stringContains? (fr/runOneLimited (fr/job (list "ps" "-A" "-o" "args=") "/" (fr/childEnv (list))) (fr/limits 10 8)).out "sleep 43"))
        (times (Map String Int64) (mapSet (mapSet (mapEmpty) "a.asl" 1500) "b.asl" 700))]
    (do (assert (= late.exit 124) (str "the run past its 1 s timeout was killed: " late.exit))
        (assert (= (fr/gateVerdict late) "timeout") (str "a timed-out run is verdict timeout though it printed a FAIL line: " (fr/gateVerdict late)))
        (assert (not (fr/redEvidence? late)) "a timed-out run is not red evidence")
        (assert (not left) "its sleep does not survive")
        (assert (and (= (fr/gateVerdict red) "red") (fr/redEvidence? red)) "a run that exits non-zero by itself is red")
        (assert (and (= (fr/gateVerdict pass) "pass") (not (fr/redEvidence? pass))) "a run that exits 0 is pass")
        (assert (= (fr/gateVerdict (done 124 "exit" "")) "timeout") "a gate that itself exits 124 reports a timeout")
        (assert (= (fr/gateVerdict (done 1 "exit" "x\n(:fleetRun :verdict :timeout :pid 7 :desc 0 :timeoutMs 5 :maxDesc 4 :left 0)\n")) "timeout") "a failed gate whose own runner timed out is timeout")
        (assert (= (fr/gateVerdict (done 0 "exit" "(:fleetRun :verdict :timeout :pid 7)")) "pass") "a passing gate that prints such a row stays pass")
        (assert (= (map (fn [(d fr/Done)] -> String (fr/gateVerdict d)) (list (done 125 "runaway" "") (done 124 "tokenWait" "") (done 126 "wallOverBound" "") (done 127 "spawnFailed" ""))) (list "runaway" "tokenWait" "wallOverBound" "spawnFailed")) "runner verdicts pass through")
        (assert (not (listAny? (fn [(d fr/Done)] -> Bool (fr/redEvidence? d)) (list (done 125 "runaway" "") (done 124 "tokenWait" "") (done 126 "wallOverBound" "") (done 127 "spawnFailed" "")))) "none of them is red evidence")
        (assert (= (fr/gateVerdict (done 2 "" "")) "red") "an empty verdict is read by its exit code")
        (assert (= (fr/loadCenti "5.70 8.39 12.87 3/900 4242\n") 570) "/proc/loadavg text in hundredths")
        (assert (= (fr/loadCenti "{ 25.21 28.33 21.55 }\n") 2521) "sysctl vm.loadavg text")
        (assert (= (fr/loadCenti "{ 12,50 1,00 1,00 }") 1250) "a comma decimal")
        (assert (= (map (fn [(t String)] -> Int64 (fr/loadCenti t)) (list "0.05 0 0" "166.4 1 1" "7 1 1")) (list 5 16640 700)) "short and long fractions")
        (assert (= (map (fn [(t String)] -> Int64 (fr/loadCenti t)) (list "" "abc 1 1" "1.2.3 1 1" "{ }")) (list -1 -1 -1 -1)) "an unreadable load is -1")
        (assert (= (fr/wallOver times (list "a.asl" "./b.asl") 2000) (some 2200)) "recorded walls add up and ./ is dropped")
        (assert (none? (fr/wallOver times (list "a.asl" "b.asl") 2200)) "a wall equal to the timeout fits")
        (assert (none? (fr/wallOver times (list "a.asl" "c.asl") 1500)) "an unrecorded file adds nothing")
        (assert (none? (fr/wallOver times (list "a.asl") 0)) "a run without a timeout is never refused")
        (assert (= (map (fn [(m Int64)] -> Int64 (fr/fitTimeoutS m)) (list 5000 1 2000)) (list 8 1 3)) "the fitted timeout is 1.5 x the recorded wall, rounded up to a second")
        true))
