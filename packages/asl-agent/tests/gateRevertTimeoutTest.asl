(module aslAgent/tests/gateRevertTimeoutTest
  :x [runTests]
  :i [(aslAgent/gates :a gd)])

fn runTests -> Bool
  (let [timedOut (gd/makeGateResult "asl test aTest.asl" 124 "" "killed" true 300)
        asserted (gd/makeGateResult "asl test aTest.asl" 1 "" "ERR_ASSERT: assertion failed: x" false 4)
        tv (gd/gateVerdicts (list timedOut) true)
        av (gd/gateVerdicts (list asserted) true)
        tDecision (gd/gateRevertVerdict (list timedOut) tv (list "src/a.asl") (list))
        aDecision (gd/gateRevertVerdict (list asserted) av (list "src/a.asl") (list))]
    (do
      (assert (= tv (list "timeoutOnRevert")) "a revert run that timed out is timeoutOnRevert")
      (refute (pairFirst tDecision) "integrity does not pass on a revert timeout alone")
      (assert (stringContains? (pairSecond tDecision) ":timeout true") "the integrity message names the timeout")
      (assert (= av (list "failsOnRevert")) "a revert run that exits non-zero without timing out still fails on revert")
      (assert (pairFirst aDecision) "integrity passes when a revert run fails without a timeout")
      true))
