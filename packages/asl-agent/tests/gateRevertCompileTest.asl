(module aslAgent/tests/gateRevertCompileTest
  :x [runTests]
  :i [(aslAgent/gates :a gd)])

fn runTests -> Bool
  (let [compileErr (gd/makeGateResult "asl test aTest.asl" 1 "" "ERR_UNRESOLVED_SYMBOL foo" false 4)
        asserted (gd/makeGateResult "asl test aTest.asl" 1 "" "ERR_ASSERT: assertion failed: x" false 4)
        both (gd/makeGateResult "asl test aTest.asl" 1 "" "ERR_UNRESOLVED_SYMBOL foo ERR_ASSERT: assertion failed: x" false 4)
        cv (gd/gateVerdicts (list compileErr) true)
        av (gd/gateVerdicts (list asserted) true)
        bv (gd/gateVerdicts (list both) true)
        cDecision (gd/gateRevertVerdict (list compileErr) cv (list "src/a.asl") (list))
        aDecision (gd/gateRevertVerdict (list asserted) av (list "src/a.asl") (list))
        bDecision (gd/gateRevertVerdict (list both) bv (list "src/a.asl") (list))]
    (do
      (assert (= cv (list "compileOnRevert")) "a revert run that fails to compile is compileOnRevert")
      (assert (pairFirst cDecision) "a new API cannot compile at HEAD, so a compile-only revert still passes integrity")
      (assert (stringContains? (pairSecond cDecision) ":revertKind compile") "a compile-only revert is marked weak in the integrity message")
      (refute (stringContains? (pairSecond aDecision) ":revertKind compile") "an assertion revert is not marked weak")
      (assert (= av (list "failsOnRevert")) "a revert run that fails an assertion is failsOnRevert")
      (assert (pairFirst aDecision) "integrity passes when a revert run fails an assertion")
      (assert (= bv (list "failsOnRevert")) "a revert run with both compile and assertion errors is failsOnRevert")
      (assert (pairFirst bDecision) "integrity passes when a revert run has both errors")
      true))
