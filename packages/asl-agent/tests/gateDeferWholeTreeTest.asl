(module aslAgent/tests/gateDeferWholeTreeTest
  :x [runTests]
  :i [(aslAgent/gates :a gd)])

fn runTests -> Bool
  (let [noSelf "asl test tools/tests/noSelfHostTest.asl"
        build "bash scripts/build.sh"
        unit "asl test asl/packages/asl-agent/tests/aTest.asl"
        all (list noSelf unit build)
        timedOut (gd/makeGateResult unit 124 "" "killed" true 300)
        tv (gd/gateVerdicts (list timedOut) true)
        tDecision (gd/gateRevertVerdict (list timedOut) tv (list "src/a.asl") (list))
        asserted (gd/makeGateResult unit 1 "" "ERR_ASSERT: x" false 4)
        aDecision (gd/gateRevertVerdict (list asserted) (gd/gateVerdicts (list asserted) true) (list "src/a.asl") (list))]
    (do
      (assert (gd/gateWholeTree? noSelf) "noSelfHostTest is whole-tree")
      (assert (gd/gateWholeTree? build) "build.sh is whole-tree")
      (refute (gd/gateWholeTree? unit) "a unit suite is not whole-tree")
      (assert (= (gd/gatesForTurn all false) (list unit)) "a plain turn runs only the non-whole-tree gates")
      (assert (= (gd/gatesForTurn all true) all) "the done turn runs every gate")
      (assert (= (gd/gatesForTurn (list noSelf build) false) (list noSelf build)) "all-whole-tree gates still run")
      (assert (stringContains? (pairSecond tDecision) ":reason revertTimeout") "a revert timeout names its reason")
      (refute (pairFirst tDecision) "a revert timeout never passes integrity")
      (assert (pairFirst aDecision) "an assert-red revert passes")
      (refute (stringContains? (pairSecond aDecision) "revertTimeout") "a red revert carries no timeout reason")
      true))
