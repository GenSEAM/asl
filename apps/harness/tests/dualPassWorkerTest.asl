(module aslHarness/dualPassWorkerTest
  :x [runTests RunTests]
  :i [(multiLensPipeline :a mlp)])

fn testThreePointCausalityEvaluation -> Bool
  (let [(cfg (mlp/makeDualPassConfig 3 true))
        (resClean (mlp/evaluateThreePointCausality false true false))
        (resVacuousPass (mlp/evaluateThreePointCausality true true false))
        (resNoRevertFail (mlp/evaluateThreePointCausality false true true))
        (resImplFail (mlp/evaluateThreePointCausality false false false))]
    (assert resClean.isGenuineCleanPass "Genuine causality passes when discard=FAIL, apply=PASS, revert=FAIL")
    (assert (not resVacuousPass.isGenuineCleanPass) "Vacuous baseline pass is rejected")
    (assert (not resNoRevertFail.isGenuineCleanPass) "Failure to fail on revert is rejected")
    (assert (not resImplFail.isGenuineCleanPass) "Failed implementation apply is rejected")
    (assert (= resVacuousPass.defectType "ERR_BASELINE_VACUOUS_PASS") "Defect type correctly classified for vacuous pass")
    (assert (= resNoRevertFail.defectType "ERR_NO_REVERT_FAILURE") "Defect type correctly classified for revert failure")
    (refute (not resClean.isGenuineCleanPass) "Refutation: Genuine causality must pass")
    (refute resVacuousPass.isGenuineCleanPass "Refutation: Vacuous pass must fail")
    true)

fn runTests -> Bool
  (testThreePointCausalityEvaluation)

fn RunTests -> Bool
  (runTests)
