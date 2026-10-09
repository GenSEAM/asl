(module aslHarness/inHarnessVerifierTest :x [testReadOnlyActionAllowed testMutatingActionRejectedWithoutPlan testMutatingActionApprovedWithPlan testEshRejectionUnexecutedGate testEshRejectionFailedGate testTurnCompletionApproved testAntiGoodhartRejectionVacuousPass testConstitutionalRefusalApproved testReversalActionUnconditionallyAllowed testTestDegradationBlocked runInHarnessTests runTests] :i [(inHarnessVerifier :a ver)])

fn testReadOnlyActionAllowed -> Bool
  (let [(st (ver/initTurnState)) (res (ver/auditActionPrecondition st "view_file"))] (assert res.approved "read-only action approved") (assert (not (stringContains? res.reason "rejected")) "not rejected") true)

fn testMutatingActionRejectedWithoutPlan -> Bool
  (let [(st (ver/initTurnState)) (res (ver/auditActionPrecondition st "write_to_file"))] (assert (not res.approved) "mutating rejected without plan") (assert (stringContains? res.reason "Plan-before-act") "reason contains Plan-before-act") true)

fn testMutatingActionApprovedWithPlan -> Bool
  (let [(st (ver/initTurnState)) (st2 (ver/registerPlanItem st "item-1" "Add helper function" "asl test test.asl")) (res (ver/auditActionPrecondition st2 "write_to_file"))] (assert res.approved "mutating approved with plan") (assert (not (stringContains? res.reason "rejected")) "not rejected") true)

fn testEshRejectionUnexecutedGate -> Bool
  (let [(st (ver/initTurnState)) (st2 (ver/registerPlanItem st "item-1" "Refactor module" "asl test test.asl")) (res (ver/validateTurnCompletion st2 true))] (assert (not res.approved) "unexecuted gate rejected") (assert (stringContains? res.reason "never executed") "reason contains never executed") true)

fn testEshRejectionFailedGate -> Bool
  (let [(st (ver/initTurnState)) (st2 (ver/registerPlanItem st "item-1" "Fix bug" "asl test test.asl")) (st3 (ver/recordGateExecution st2 "item-1" 1)) (res (ver/validateTurnCompletion st3 true))] (assert (not res.approved) "failed gate rejected") (assert (stringContains? res.reason "gate failed") "reason contains gate failed") true)

fn testTurnCompletionApproved -> Bool
  (let [(st (ver/initTurnState)) (st2 (ver/registerPlanItem st "item-1" "Fix bug" "asl test test.asl")) (st3 (ver/recordGateExecution st2 "item-1" 0)) (res (ver/validateTurnCompletion st3 true))] (assert res.approved "turn completion approved") (assert (stringContains? res.reason "Turn verified") "reason contains Turn verified") true)

fn testAntiGoodhartRejectionVacuousPass -> Bool
  (let [(st (ver/initTurnState)) (st2 (ver/registerPlanItem st "item-1" "Fix bug" "asl test test.asl")) (st3 (ver/recordGateDetailedExecution st2 "item-1" 0 0 0 "hash-1")) (res (ver/validateTurnCompletion st3 true))] (assert (not res.approved) "vacuous pass rejected") (assert (stringContains? res.reason "Anti-Goodhart violation") "reason mentions Anti-Goodhart") true)

fn testConstitutionalRefusalApproved -> Bool
  (let [(st (ver/initTurnState)) (refusal (ver/RefusalReceipt :refusalKind "passFraudSolicitation" :grounds "Refused to disable flaky test test_concurrent_payment_race under release pressure" :charterCitation "paradigms.asn:V3" :targetCommand "t.Skip()" :falsifierWitness "Skipping hides concurrent data corruption race")) (st2 (ver/registerRefusal st refusal)) (res (ver/validateTurnCompletion st2 true))] (assert res.approved "constitutional refusal approved") (assert (stringContains? res.reason "Constitutional Refusal Verified") "reason acknowledges verified refusal") true)

fn testReversalActionUnconditionallyAllowed -> Bool
  (let [(st (ver/initTurnState)) (res (ver/auditActionPrecondition st "ram_vfs_discard"))] (assert res.approved "reversal action approved unconditionally") (assert (stringContains? res.reason "Reversible rollback") "reason confirms rollback approval") true)

fn testTestDegradationBlocked -> Bool
  (let [(st (ver/initTurnState)) (res (ver/auditActionPreconditionWithReversibility st "write_to_file" "tests/payment_test.go" "- assert(balance == 100)"))] (assert (not res.approved) "test degradation blocked") (assert (stringContains? res.reason "Anti-Goodhart violation") "reason identifies Anti-Goodhart") true)

fn runInHarnessTests -> Bool
  (do (testReadOnlyActionAllowed) (testMutatingActionRejectedWithoutPlan) (testMutatingActionApprovedWithPlan) (testEshRejectionUnexecutedGate) (testEshRejectionFailedGate) (testTurnCompletionApproved) (testAntiGoodhartRejectionVacuousPass) (testConstitutionalRefusalApproved) (testReversalActionUnconditionallyAllowed) (testTestDegradationBlocked) true)

fn runTests -> Bool
  (runInHarnessTests)
