(module aslHarness/tests/autonomousLoopTest
  :x [RunTests runTests]
  :i [(autonomousLoop :a loop)
      (multiLensPipeline :a mlp)])

fn testAutonomousLoopLifecycle -> Bool
  (let [(loop0 (loop/makeAutonomousLoop "task-test-1" "Refactor module"))
        (phase0 loop0.currentPhase)
        (str0 (loop/loopPhaseToString phase0))
        (term0 (loop/isLoopTerminated? loop0))
        (succ0 (loop/isLoopSuccessful? loop0))
        (loop1 (loop/stepAutonomousLoop loop0 true "Reconnaissance complete"))
        (loop2 (loop/stepAutonomousLoop loop1 true "Skill packs bound"))
        (loop3 (loop/stepAutonomousLoop loop2 true "Plan formulated"))
        (loop4 (loop/stepAutonomousLoop loop3 true "Council consensus reached"))
        (loop5 (loop/stepAutonomousLoop loop4 true "Code implemented"))
        (loop6 (loop/stepAutonomousLoop loop5 true "Multi-lens audit clear"))
        (loop7 (loop/stepAutonomousLoop loop6 true "Popperian gates verified green"))
        (phaseFinal loop7.currentPhase)
        (strFinal (loop/loopPhaseToString phaseFinal))
        (termFinal (loop/isLoopTerminated? loop7))
        (succFinal (loop/isLoopSuccessful? loop7))
        (iterFinal loop7.iterationCount)]
    (assert (= str0 "SCOUT") "Initial autonomous loop phase is SCOUT")
    (refute term0 "Refutation: Initial loop must not be terminated")
    (refute succ0 "Refutation: Initial loop must not be successful")
    (assert (= (loop/loopPhaseToString loop1.currentPhase) "SELF_ORG") "Step 1 advances to SELF_ORG")
    (assert (= (loop/loopPhaseToString loop2.currentPhase) "PLAN") "Step 2 advances to PLAN")
    (assert (= (loop/loopPhaseToString loop3.currentPhase) "CONSENSUS") "Step 3 advances to CONSENSUS")
    (assert (= (loop/loopPhaseToString loop4.currentPhase) "IMPL") "Step 4 advances to IMPL")
    (assert (= (loop/loopPhaseToString loop5.currentPhase) "AUDIT") "Step 5 advances to AUDIT")
    (assert (= (loop/loopPhaseToString loop6.currentPhase) "VERIFY") "Step 6 advances to VERIFY")
    (assert (= strFinal "SETTLE") "Step 7 advances to SETTLE")
    (assert termFinal "Settled loop is terminated")
    (assert succFinal "Settled loop is successful")
    (assert (= iterFinal 7) "Total iterations equals 7")
    (refute (!= strFinal "SETTLE") "Refutation: Final phase must be SETTLE")
    (refute (!= iterFinal 7) "Refutation: Iteration count must be exactly 7")
    true)

fn testAutonomousLoopFailure -> Bool
  (let [(loop0 (loop/makeAutonomousLoop "task-test-fail" "Faulty task"))
        (loopFailed (loop/stepAutonomousLoop loop0 false "Invariant violation detected"))
        (phaseF loopFailed.currentPhase)
        (strF (loop/loopPhaseToString phaseF))
        (termF (loop/isLoopTerminated? loopFailed))
        (succF (loop/isLoopSuccessful? loopFailed))]
    (assert (= strF "FAILED") "Failed step transitions directly to FAILED phase")
    (assert termF "Failed loop is terminated")
    (assert (not succF) "Failed loop is not successful")
    (refute succF "Refutation: Failed loop must never report success")
    (refute (!= strF "FAILED") "Refutation: Terminal phase must be FAILED")
    true)

fn testCircuitBreakerTripping -> Bool
  (let [(loop0 (loop/makeAutonomousLoop "task-test-breaker" "Harden circuit breaker"))
        (s1 (loop/recordFailureSignature loop0 "ERR_COMPILE_FAIL"))
        (c1 s1.consecutiveFailures)
        (s2 (loop/recordFailureSignature s1 "ERR_COMPILE_FAIL"))
        (c2 s2.consecutiveFailures)
        (s3 (loop/recordFailureSignature s2 "ERR_COMPILE_FAIL"))
        (c3 s3.consecutiveFailures)
        (term3 (loop/isLoopTerminated? s3))
        (str3 (loop/loopPhaseToString s3.currentPhase))
        (sReset (loop/recordFailureSignature s2 "ERR_DIFFERENT_FAIL"))
        (cReset sReset.consecutiveFailures)]
    (assert (= c1 1) "First failure signature records count=1")
    (assert (= c2 2) "Second identical failure signature records count=2")
    (assert (= c3 3) "Third identical failure signature records count=3")
    (assert term3 "Three identical failures trip circuit breaker into terminated state")
    (assert (= str3 "FAILED") "Tripped circuit breaker phase is FAILED")
    (refute (!= str3 "FAILED") "Refutation: Circuit breaker phase must be FAILED")
    (assert (= cReset 1) "Distinct failure signature resets consecutive count to 1")
    (refute (= cReset 3) "Refutation: Reset signature must not remain at count=3")
    true)

fn testBasinTransitions -> Bool
  (let [(loop0 (loop/makeAutonomousLoop "task-test-basin" "Test basin"))
        (lSelfOrg (loop/stepAutonomousLoop loop0 true "scout done"))
        (lPlan (loop/stepAutonomousLoop lSelfOrg true "self org done"))
        (lConsensus (loop/stepAutonomousLoop lPlan true "plan done"))
        (lImpl (loop/stepAutonomousLoop lConsensus true "consensus done"))
        (implPhaseStr (loop/loopPhaseToString lImpl.currentPhase))
        (lImplFail1 (loop/stepAutonomousLoop lImpl false "syntax error in file"))
        (basinStr1 (loop/loopPhaseToString lImplFail1.currentPhase))
        (lImplFail2 (loop/stepAutonomousLoop lImplFail1 false "syntax error in file"))
        (basinStr2 (loop/loopPhaseToString lImplFail2.currentPhase))
        (lImplFail3 (loop/stepAutonomousLoop lImplFail2 false "syntax error in file"))
        (basinStr3 (loop/loopPhaseToString lImplFail3.currentPhase))
        (lAudit (loop/stepAutonomousLoop lImpl true "impl done"))
        (lAuditFail (loop/stepAutonomousLoop lAudit false "missing audit assert"))
        (basinAuditStr (loop/loopPhaseToString lAuditFail.currentPhase))]
    (assert (= implPhaseStr "IMPL") "Reached IMPL phase")
    (assert (= basinStr1 "PLAN") "First failure in IMPL transitions back to PLAN basin")
    (refute (= basinStr1 "FAILED") "Refutation: First failure in IMPL must not fail permanently")
    (assert (= basinStr2 "SCOUT") "Second identical failure transitions to SCOUT basin")
    (assert (= basinStr3 "FAILED") "Third identical failure trips dynamic witness circuit breaker")
    (assert (loop/isLoopTerminated? lImplFail3) "Tripped loop is terminated")
    (assert (= basinAuditStr "IMPL") "Failure in AUDIT transitions back to IMPL basin")
    (refute (= basinAuditStr "FAILED") "Refutation: Audit failure must not fail permanently")
    true)

fn testObservationMaskingAndTelemetry -> Bool
  (let [(shortText "Short output log.")
        (longText "Line 001: Execution started\nLine 002: Parsing symbols\nLine 003: Type checking AST\nLine 004: Intermediate representation lowering\nLine 005: Optimization pass fold constants\nLine 006: Target code generation\nLine 007: Assembler emission\nLine 008: Linker resolution\nLine 009: Verification gate check\nLine 010: Execution finished successfully.")
        (maskedShort (loop/maskObservation shortText))
        (maskedLong (loop/maskObservation longText))
        (loop0 (loop/makeAutonomousLoop "task-test-telemetry" "Test telemetry"))
        (loopTel (loop/recordTelemetryTokens loop0 1450 3))]
    (assert (= maskedShort shortText) "Short text is not masked")
    (assert (stringContains? maskedLong "OBSERVATION MASKED") "Long text undergoes observation masking")
    (assert (< (stringLength maskedLong) (stringLength longText)) "Masked text length is smaller than raw text")
    (refute (= maskedLong longText) "Refutation: Masked long text must differ from unmasked")
    (assert (= loopTel.tokenBudgetUsed 1450) "Token budget updated to 1450")
    (assert (= loopTel.observationMaskedCount 3) "Masked observation count updated to 3")
    (refute (= loopTel.tokenBudgetUsed 0) "Refutation: Token budget must not be 0")
    true)

fn testAdaptiveRemediationDAGGeneration -> Bool
  (let [(phases (mlp/generateRemediationPhases "consensus dissent: resilience partition and concurrency race" 1))
        (pCount (listLength phases))]
    (assert (>= pCount 3) "Dissenting votes on resilience and concurrency generate at least 3 remediation phases")
    (refute (< pCount 3) "Refutation: Remediation phase count must be at least 3")
    true)

fn testDynamicTaskEntropyAndTokenBudgetCalibration -> Bool
  (let [(entropy (loop/computeTaskEntropyDynamic "distributed consensus raft joint reconfiguration and wal journaling"))
        (calibrated (loop/calibrateDynamicTokenBudget 1000 entropy))]
    (assert (> entropy 0) "task entropy is strictly positive for non-trivial task")
    (assert (> calibrated 1000) "calibrated token budget scales above base budget")
    true)

fn testSemanticObservationMasking -> Bool
  (let [(longWithPanic "Line 001: Execution started\nLine 002: Parsing symbols\nLine 003: Type checking AST\nLine 004: Intermediate representation lowering\nLine 005: Optimization pass fold constants\nLine 006: CRITICAL_PANIC: segment violation in memory\nLine 007: Assembler emission\nLine 008: Linker resolution\nLine 009: Verification gate check\nLine 010: Execution finished.")
        (masked (loop/maskObservation longWithPanic))]
    (assert (stringContains? masked "CRITICAL_PANIC") "Semantic observation masking must preserve CRITICAL_PANIC in middle")
    true)

fn runTests -> Bool
  (do
    (assert (testAutonomousLoopLifecycle) "testAutonomousLoopLifecycle passed")
    (assert (testAutonomousLoopFailure) "testAutonomousLoopFailure passed")
    (assert (testCircuitBreakerTripping) "testCircuitBreakerTripping passed")
    (assert (testBasinTransitions) "testBasinTransitions passed")
    (assert (testObservationMaskingAndTelemetry) "testObservationMaskingAndTelemetry passed")
    (assert (testSemanticObservationMasking) "testSemanticObservationMasking passed")
    (assert (testAdaptiveRemediationDAGGeneration) "testAdaptiveRemediationDAGGeneration passed")
    (assert (testDynamicTaskEntropyAndTokenBudgetCalibration) "testDynamicTaskEntropyAndTokenBudgetCalibration passed")
    true)

fn RunTests -> Bool
  (runTests)
