(module aslHarness/workerTest :x [testProcessReceiptStructure testProcessReceiptTokenCeiling testProcessReceiptErrorSummary testWorkerConfigInit testWorkerStateLifecycle testPathInBoundariesMatching testPathInBoundariesPrefix testPathInBoundariesRejected testWorkItemCreation testPhaseRecordCreation testPhasePollingClaimedLease testPhasePollingClaimedStatus testPhasePollingEmpty testSequentialExecutionAllPass testSequentialExecutionEarlyHalt testBlastRadiusWithinBoundaries testBlastRadiusExternalViolation testPreCommitSafetyAudit testPreCommitSafetyBlockedByBlast testPreCommitSafetyBlockedByGate testCommitPhaseDiffSuccess testCommitPhaseDiffRejected testWorkerStepCompleteSuccess testWorkerStepItemFailure testWorkerStepIdle testRunWorkerLoopBounded testDiagnosticReceipt runTests] :i [(worker :a w)])

fn testProcessReceiptStructure -> Bool
  (let [(r (w/makeProcessReceipt 0 42 16 "/tmp/spool_1.log" "Gate passed cleanly"))] (do (assert (= r.exitCode 0)) (assert (= r.durationMs 42)) (assert (= r.peakRssMb 16)) (assert (= r.spoolPath "/tmp/spool_1.log")) (assert (= r.summary "Gate passed cleanly")) (assert (> r.tokens 0)) true))

fn testProcessReceiptTokenCeiling -> Bool
  (let [(r (w/makeProcessReceipt 0 85 24 "/tmp/spool_gate.log" "All 4 plan item gates evaluated and passed cleanly")) (rendered (w/renderProcessReceipt r)) (toks (w/estimateReceiptTokens rendered))] (do (assert (< toks 80)) (assert (> toks 0)) (assert (stringContains? rendered ":receipt")) (assert (stringContains? rendered ":exit 0")) (assert (stringContains? rendered ":ms 85")) true))

fn testProcessReceiptErrorSummary -> Bool
  (let [(r (w/makeProcessReceipt 1 120 30 "/tmp/fail.log" "Gate failed with exit code 1: asl test"))] (do (assert (= r.exitCode 1)) (assert (< r.tokens 80)) (assert (stringContains? r.summary "Gate failed")) true))

fn testWorkerConfigInit -> Bool
  (let [(owns (list "harness/src/worker.asl" "harness/tests/worker_test.asl")) (cfg (w/makeWorkerConfig "worker-daemon-test" true 5 250 owns)) (tr (w/ThinkingResult :thought "test" :confidence 1.0)) (tcr (w/ToolCallResult :toolName "t" :arguments "a" :rawOutput "o"))] (do (assert (= cfg.agentId "worker-daemon-test")) (assert cfg.continuous) (assert (= cfg.maxCycles 5)) (assert (= cfg.idleIntervalMs 250)) (assert cfg.strictGates) (assert (= (listLength cfg.ownsBoundaries) 2)) (assert (= tr.thought "test") "ThinkingResult matches") (assert (= tcr.toolName "t") "ToolCallResult matches") (refute (= tr.thought "wrong") "Refute ThinkingResult thought") true))

fn testWorkerStateLifecycle -> Bool
  (let [(cfg (w/makeWorkerConfig "worker-daemon-1" false 1 500 (list "harness/src/worker.asl"))) (st (w/initWorkerState cfg))] (do (assert (= st.status "idle")) (assert (= st.cycleCount 0)) (assert (= st.activePhaseId "")) (assert (listEmpty? st.completedPhases)) (assert (listEmpty? st.receipts)) (assert (= st.lastError "")) true))

fn testPathInBoundariesMatching -> Bool
  (let [(bounds (list "harness/src/worker.asl" "harness/manifest.asn"))] (do (assert (w/pathInBoundaries? "harness/src/worker.asl" bounds)) (assert (w/pathInBoundaries? "harness/manifest.asn" bounds)) true))

fn testPathInBoundariesPrefix -> Bool
  (let [(bounds (list "harness/src/" "harness/tests/"))] (do (assert (w/pathInBoundaries? "harness/src/worker.asl" bounds)) (assert (w/pathInBoundaries? "harness/tests/worker_test.asl" bounds)) true))

fn testPathInBoundariesRejected -> Bool
  (let [(bounds (list "harness/src/worker.asl"))] (do (assert (not (w/pathInBoundaries? "asl/packages/asl-agent-bus/src/ambient.asl" bounds))) (assert (not (w/pathInBoundaries? "engine/engine.asl" bounds))) true))

fn testWorkItemCreation -> Bool
  (let [(item (w/makeWorkItem "item-1" "Worker Loop" "pending" "asl test worker_test.asl"))] (do (assert (= item.id "item-1")) (assert (= item.name "Worker Loop")) (assert (= item.status "pending")) (assert (= item.gate "asl test worker_test.asl")) true))

fn testPhaseRecordCreation -> Bool
  (let [(it1 (w/makeWorkItem "item-1" "Item 1" "pending" "asl test")) (it2 (w/makeWorkItem "item-2" "Item 2" "pending" "asl gate")) (phase (w/makePhaseRecord "phase-298" "Autonomous Worker" "pending" "Wave E" "asl gate" (list it1 it2)))] (do (assert (= phase.id "phase-298")) (assert (= phase.name "Autonomous Worker")) (assert (= phase.status "pending")) (assert (= phase.wave "Wave E")) (assert (= (listLength phase.items) 2)) true))

fn testPhasePollingClaimedLease -> Bool
  (let [(it (w/makeWorkItem "item-1" "Loop" "pending" "asl test")) (phase (w/makePhaseRecord "phase-298" "Worker" "claimed" "Wave E" "asl gate" (list it))) (lease (w/makeLeaseRecord "phase-298" "worker-daemon-1" 1000 60000)) (rm (w/RoadmapRecord :iteration "iter-42" :phases (list phase) :leases (list lease) :version 1)) (polled (w/pollClaimedPhase rm "worker-daemon-1"))] (mt polled ((some p) (do (assert (= p.id "phase-298")) true)) ((none) (do (assert false "testPhasePollingClaimedLease failed: expected some, got none") false))))

fn testPhasePollingClaimedStatus -> Bool
  (let [(it (w/makeWorkItem "item-1" "Loop" "pending" "asl test")) (phase (w/makePhaseRecord "phase-298" "Worker" "claimed" "Wave E" "asl gate" (list it))) (rm (w/RoadmapRecord :iteration "iter-42" :phases (list phase) :leases (list) :version 1)) (polled (w/pollClaimedPhase rm "worker-daemon-2"))] (mt polled ((some p) (do (assert (= p.id "phase-298")) true)) ((none) (do (assert false "testPhasePollingClaimedStatus failed: expected some, got none") false))))

fn testPhasePollingEmpty -> Bool
  (let [(it (w/makeWorkItem "item-1" "Loop" "completed" "asl test")) (phase (w/makePhaseRecord "phase-297" "Prior" "completed" "Wave E" "asl gate" (list it))) (rm (w/RoadmapRecord :iteration "iter-42" :phases (list phase) :leases (list) :version 1)) (polled (w/pollClaimedPhase rm "worker-daemon-1"))] (mt polled ((some _) (do (assert false "testPhasePollingEmpty failed: expected none, got some") false)) ((none) true)))

fn testSequentialExecutionAllPass -> Bool
  (let [(it1 (w/makeWorkItem "item-1" "Step 1" "pending" "gate-1")) (it2 (w/makeWorkItem "item-2" "Step 2" "pending" "gate-2")) (it3 (w/makeWorkItem "item-3" "Step 3" "pending" "gate-3")) (res (w/executePhaseItems (list it1 it2 it3) (list 0 0 0)))] (do (assert res.allPassed) (assert (= res.executedCount 3)) (assert (= res.failedItemId "")) (assert (= (listLength res.receipts) 3)) true))

fn testSequentialExecutionEarlyHalt -> Bool
  (let [(it1 (w/makeWorkItem "item-1" "Step 1" "pending" "gate-1")) (it2 (w/makeWorkItem "item-2" "Step 2" "pending" "gate-2")) (it3 (w/makeWorkItem "item-3" "Step 3" "pending" "gate-3")) (res (w/executePhaseItems (list it1 it2 it3) (list 0 1 0)))] (do (assert (not res.allPassed)) (assert (= res.executedCount 2)) (assert (= res.failedItemId "item-2")) (assert (= (listLength res.receipts) 2)) true))

fn testBlastRadiusWithinBoundaries -> Bool
  (let [(affected (list "harness/src/worker.asl" "harness/tests/worker_test.asl")) (owns (list "harness/src/worker.asl" "harness/tests/worker_test.asl" "asl/asl")) (guard (w/verifyBlastRadius (list "worker") affected owns))] (do (assert guard.isSafe) (assert (listEmpty? guard.violations)) (assert (stringContains? guard.details "zero boundary violations")) true))

fn testBlastRadiusExternalViolation -> Bool
  (let [(affected (list "harness/src/worker.asl" "engine/engine.asl")) (owns (list "harness/src/worker.asl" "harness/tests/worker_test.asl")) (guard (w/verifyBlastRadius (list "worker") affected owns))] (do (assert (not guard.isSafe)) (assert (= (listLength guard.violations) 1)) (assert (stringContains? guard.details "Blast-radius violation")) true))

fn testPreCommitSafetyAudit -> Bool
  (let [(guard (w/BlastRadiusGuard :isSafe true :violations (list) :affectedSymbols (list) :details "Clean"))] (do (assert (w/auditPreCommitSafety guard true true)) (assert (not (w/auditPreCommitSafety guard false true))) true))

fn testPreCommitSafetyBlockedByBlast -> Bool
  (let [(guard (w/BlastRadiusGuard :isSafe false :violations (list "mem/engine.asl") :affectedSymbols (list) :details "Violation"))] (do (assert (not (w/auditPreCommitSafety guard true true))) (assert (w/auditPreCommitSafety (w/BlastRadiusGuard :isSafe true :violations (list) :affectedSymbols (list) :details "Clean") true true)) true))

fn testPreCommitSafetyBlockedByGate -> Bool
  (let [(guard (w/BlastRadiusGuard :isSafe true :violations (list) :affectedSymbols (list) :details "Clean"))] (do (assert (not (w/auditPreCommitSafety guard true false))) (assert (not (w/auditPreCommitSafety guard false true))) true))

fn testCommitPhaseDiffSuccess -> Bool
  (let [(cfg (w/makeWorkerConfig "worker-1" false 1 500 (list "harness/src/worker.asl"))) (st (w/initWorkerState cfg)) (guard (w/BlastRadiusGuard :isSafe true :violations (list) :affectedSymbols (list) :details "Clean")) (res (w/commitPhaseDiff st guard "phase-298" 0))] (do (assert (= res.status "committed")) (assert (= (listLength res.completedPhases) 1)) (assert (= (listLength res.receipts) 1)) (assert (= res.lastError "")) true))

fn testCommitPhaseDiffRejected -> Bool
  (let [(cfg (w/makeWorkerConfig "worker-1" false 1 500 (list "harness/src/worker.asl"))) (st (w/initWorkerState cfg)) (guard (w/BlastRadiusGuard :isSafe false :violations (list "intel/src/intel.asl") :affectedSymbols (list) :details "Boundary violation")) (res (w/commitPhaseDiff st guard "phase-298" 0))] (do (assert (= res.status "failed")) (assert (listEmpty? res.completedPhases)) (assert (stringContains? res.lastError "Boundary violation")) true))

fn testWorkerStepCompleteSuccess -> Bool
  (let [(cfg (w/makeWorkerConfig "worker-1" false 1 500 (list "harness/src/worker.asl"))) (st (w/initWorkerState cfg)) (it (w/makeWorkItem "item-1" "Step 1" "pending" "gate-1")) (phase (w/makePhaseRecord "phase-298" "Autonomous" "claimed" "Wave E" "asl gate" (list it))) (rm (w/RoadmapRecord :iteration "iter-1" :phases (list phase) :leases (list) :version 1)) (outcome (w/workerStep st rm (list 0) (list "harness/src/worker.asl") 0))] (do (assert outcome.allPassed) (assert (= outcome.action "committed")) (assert (= outcome.phaseId "phase-298")) (assert (= outcome.workerState.status "committed")) true))

fn testWorkerStepItemFailure -> Bool
  (let [(cfg (w/makeWorkerConfig "worker-1" false 1 500 (list "harness/src/worker.asl"))) (st (w/initWorkerState cfg)) (it (w/makeWorkItem "item-1" "Step 1" "pending" "gate-1")) (phase (w/makePhaseRecord "phase-298" "Autonomous" "claimed" "Wave E" "asl gate" (list it))) (rm (w/RoadmapRecord :iteration "iter-1" :phases (list phase) :leases (list) :version 1)) (outcome (w/workerStep st rm (list 1) (list "harness/src/worker.asl") 0))] (do (assert (not outcome.allPassed)) (assert (= outcome.action "failed")) (assert (= outcome.workerState.status "failed")) (assert (stringContains? outcome.workerState.lastError "item-1")) true))

fn testWorkerStepIdle -> Bool
  (let [(cfg (w/makeWorkerConfig "worker-1" false 1 500 (list "harness/src/worker.asl"))) (st (w/initWorkerState cfg)) (rm (w/RoadmapRecord :iteration "iter-1" :phases (list) :leases (list) :version 1)) (outcome (w/workerStep st rm (list) (list) 0))] (do (assert outcome.allPassed) (assert (= outcome.action "idle")) (assert (= outcome.workerState.status "idle")) true))

fn testRunWorkerLoopBounded -> Bool
  (let [(cfg (w/makeWorkerConfig "worker-1" false 2 500 (list "harness/src/worker.asl"))) (st (w/initWorkerState cfg)) (rm (w/RoadmapRecord :iteration "iter-1" :phases (list) :leases (list) :version 1)) (finalSt (w/runWorkerLoop st rm 3))] (do (assert (= finalSt.status "idle")) (assert (> finalSt.cycleCount 0)) true))

fn testDiagnosticReceipt -> Bool
  (let [(diag (w/emitStringNotFoundReceipt "(:old-fn)" "(:old-fn-def)" "src/main.asl")) (rendered (w/formatDiagnosticReceipt diag))] (do (assert (= diag.code "ERR_STRING_NOT_FOUND") "Diagnostic code must be ERR_STRING_NOT_FOUND") (assert (= diag.failedSeek "(:old-fn)") "Failed seek must match") (assert (= diag.hint "(:old-fn-def)") "Hint must match") (assert (stringContains? diag.action ":read") "Action must recommend targeted read") (assert (stringContains? rendered ":diagnostic :code :ERR_STRING_NOT_FOUND") "Rendered must have diagnostic code") (assert (stringContains? rendered ":failed-seek \"(:old-fn)\"") "Rendered must have failed-seek") (assert (stringContains? rendered ":hint \"(:old-fn-def)\"") "Rendered must have hint") true))

fn runTests -> Bool
  (do (assert (testProcessReceiptStructure) "t1: receipt structure") (assert (testProcessReceiptTokenCeiling) "t2: token ceiling") (assert (testProcessReceiptErrorSummary) "t3: error summary") (assert (testWorkerConfigInit) "t4: config init") (assert (testWorkerStateLifecycle) "t5: state lifecycle") (assert (testPathInBoundariesMatching) "t6: boundaries match") (assert (testPathInBoundariesPrefix) "t7: boundaries prefix") (assert (testPathInBoundariesRejected) "t8: boundaries rejected") (assert (testWorkItemCreation) "t9: work item") (assert (testPhaseRecordCreation) "t10: phase record") (assert (testPhasePollingClaimedLease) "t11: poll lease") (assert (testPhasePollingClaimedStatus) "t12: poll status") (assert (testPhasePollingEmpty) "t13: poll empty") (assert (testSequentialExecutionAllPass) "t14: seq all pass") (assert (testSequentialExecutionEarlyHalt) "t15: seq early halt") (assert (testBlastRadiusWithinBoundaries) "t16: blast safe") (assert (testBlastRadiusExternalViolation) "t17: blast violation") (assert (testPreCommitSafetyAudit) "t18: precommit audit") (assert (testPreCommitSafetyBlockedByBlast) "t19: audit blast block") (assert (testPreCommitSafetyBlockedByGate) "t20: audit gate block") (assert (testCommitPhaseDiffSuccess) "t21: commit success") (assert (testCommitPhaseDiffRejected) "t22: commit rejected") (assert (testWorkerStepCompleteSuccess) "t23: worker step success") (assert (testWorkerStepItemFailure) "t24: worker step failure") (assert (testWorkerStepIdle) "t25: worker step idle") (assert (testRunWorkerLoopBounded) "t26: worker loop") (assert (testDiagnosticReceipt) "t27: diagnostic receipt") true)
