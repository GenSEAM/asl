(module aslHarness/autonomousLoop
  :x [AutonomousLoopPhase
      phaseScout
      phaseSelfOrg
      phasePlan
      phaseConsensus
      phaseImpl
      phaseAudit
      phaseVerify
      phaseSettle
      phaseFailed
      AutonomousLoopState
      makeAutonomousLoop
      stepAutonomousLoop
      loopPhaseToString
      isLoopTerminated?
      isLoopSuccessful?
      recordFailureSignature
      maskObservation
      recordTelemetryTokens
      computeTaskEntropyDynamic
      calibrateDynamicTokenBudget]
  :i [(multiLensPipeline :a mlp)])

(enum AutonomousLoopPhase
  (:c phaseScout [] "Environment reconnaissance and fact discovery")
  (:c phaseSelfOrg [] "Autonomous skill-pack discovery and role taxonomy assignment")
  (:c phasePlan [] "Action DAG decomposition and gate formulation")
  (:c phaseConsensus [] "2-Stage cross-model consensus council deliberation")
  (:c phaseImpl [] "Phased scoped implementation in isolated RAM buffers")
  (:c phaseAudit [] "Cross-scope 10-lens verification and refutation check")
  (:c phaseVerify [] "Clean-context Popperian gate verification")
  (:c phaseSettle [] "Terminal settlement, receipts emission and commit")
  (:c phaseFailed [] "Terminal failure or circuit-breaker halt"))

(schema AutonomousLoopState
  (:f taskId Str)
  (:f instruction Str)
  (:f currentPhase AutonomousLoopPhase)
  (:f iterationCount I64)
  (:f maxIterations I64)
  (:f pipeline mlp/MultiLensPipeline)
  (:f lastMessage Str)
  (:f lastFailureSig Str)
  (:f consecutiveFailures I64)
  (:f tokenBudgetUsed I64)
  (:f observationMaskedCount I64))

fn loopPhaseToString phase: AutonomousLoopPhase -> Str
  (mt phase
    ((phaseScout) "SCOUT")
    ((phaseSelfOrg) "SELF_ORG")
    ((phasePlan) "PLAN")
    ((phaseConsensus) "CONSENSUS")
    ((phaseImpl) "IMPL")
    ((phaseAudit) "AUDIT")
    ((phaseVerify) "VERIFY")
    ((phaseSettle) "SETTLE")
    ((phaseFailed) "FAILED"))

fn makeAutonomousLoop taskId: Str instruction: Str -> AutonomousLoopState
  (AutonomousLoopState
    :taskId taskId
    :instruction instruction
    :currentPhase (phaseScout)
    :iterationCount 0
    :maxIterations 20
    :pipeline (mlp/make7StagePipeline taskId instruction)
    :lastMessage "Initialized autonomous loop"
    :lastFailureSig ""
    :consecutiveFailures 0
    :tokenBudgetUsed 0
    :observationMaskedCount 0)

fn isLoopTerminated? loop: AutonomousLoopState -> Bool
  (mt loop.currentPhase
    ((phaseSettle) true)
    ((phaseFailed) true)
    (_ false))

fn isLoopSuccessful? loop: AutonomousLoopState -> Bool
  (mt loop.currentPhase
    ((phaseSettle) true)
    (_ false))

fn findErrorSignalIndex output: Str -> (Option I64)
  (let [(p1 (stringIndexOf output "CRITICAL_PANIC"))]
    (mt p1
      ((some idx1) (some idx1))
      ((none) (let [(p2 (stringIndexOf output "Assertion failed"))]
                (mt p2
                  ((some idx2) (some idx2))
                  ((none) (let [(p3 (stringIndexOf output "PANIC"))]
                            (mt p3
                              ((some idx3) (some idx3))
                              ((none) (let [(p4 (stringIndexOf output "FAIL"))]
                                        (mt p4
                                          ((some idx4) (some idx4))
                                          ((none) (stringIndexOf output "ERROR")))))))))))))

fn maskObservation output: Str -> Str
  (let [(len (stringLength output))]
    (if (<= len 300)
      output
      (let [(head (optionOr (stringSlice output 0 100) ""))
            (tail (optionOr (stringSlice output (- len 100) len) ""))
            (errOpt (findErrorSignalIndex output))]
        (mt errOpt
          ((some errIdx)
           (if (and (> errIdx 100) (< errIdx (- len 100)))
             (let [(winStart (if (< errIdx 40) 0 (- errIdx 40)))
                   (winEnd (if (> (+ errIdx 60) len) len (+ errIdx 60)))
                   (errSnippet (optionOr (stringSlice output winStart winEnd) ""))]
               (str head "\n... [OBSERVATION MASKED] ...\n[PRESERVED FAILURE CONTEXT]:\n" errSnippet "\n... [OBSERVATION MASKED] ...\n" tail))
             (let [(maskedBytes (- len 200))]
               (str head "\n... [OBSERVATION MASKED: " (stringFromInt64 maskedBytes) " bytes compressed] ...\n" tail))))
          ((none)
           (let [(maskedBytes (- len 200))]
             (str head "\n... [OBSERVATION MASKED: " (stringFromInt64 maskedBytes) " bytes compressed] ...\n" tail)))))))

fn recordTelemetryTokens loop: AutonomousLoopState tokens: I64 maskedObservations: I64 -> AutonomousLoopState
  (with loop :tokenBudgetUsed (+ loop.tokenBudgetUsed tokens) :observationMaskedCount (+ loop.observationMaskedCount maskedObservations))

fn recordFailureSignature loop: AutonomousLoopState sig: Str -> AutonomousLoopState
  (let [(matchesPrev (= sig loop.lastFailureSig))
        (newCount (if matchesPrev (+ loop.consecutiveFailures 1) 1))
        (tripped (>= newCount 3))
        (nextPhase (if tripped (phaseFailed) loop.currentPhase))
        (msg (if tripped
               (str "Dynamic witness circuit breaker tripped: 3 identical failures for " sig)
               (str "Recorded failure signature: " sig " (count=" (stringFromInt64 newCount) ")")))]
    (with loop :currentPhase nextPhase :lastMessage msg :lastFailureSig sig :consecutiveFailures newCount))

fn stepAutonomousLoop loop: AutonomousLoopState success: Bool detail: Str -> AutonomousLoopState
  (if (isLoopTerminated? loop)
    loop
    (if (>= loop.iterationCount loop.maxIterations)
      (with loop :currentPhase (phaseFailed) :lastMessage "Iteration budget ceiling exceeded")
      (if (not success)
        (let [(sig detail)
              (matchesPrev (= sig loop.lastFailureSig))
              (newCount (if matchesPrev (+ loop.consecutiveFailures 1) 1))]
          (if (>= newCount 3)
            (with loop :currentPhase (phaseFailed) :iterationCount (+ loop.iterationCount 1) :lastMessage (str "Dynamic witness circuit breaker tripped: 3 identical failures for " sig) :lastFailureSig sig :consecutiveFailures newCount)
            (let [(basinPhase (mt loop.currentPhase
                                ((phaseImpl) (phasePlan))
                                ((phaseAudit) (phaseImpl))
                                ((phaseVerify) (phaseImpl))
                                ((phaseConsensus) (phasePlan))
                                ((phasePlan) (phaseScout))
                                (_ (phaseFailed))))]
              (with loop :currentPhase basinPhase :iterationCount (+ loop.iterationCount 1) :lastMessage (str "Step failure (" (stringFromInt64 newCount) "/3), transition to basin: " (loopPhaseToString basinPhase) " (" detail ")") :lastFailureSig sig :consecutiveFailures newCount))))
        (let [(nextPhase (mt loop.currentPhase
                           ((phaseScout) (phaseSelfOrg))
                           ((phaseSelfOrg) (phasePlan))
                           ((phasePlan) (phaseConsensus))
                           ((phaseConsensus) (phaseImpl))
                           ((phaseImpl) (phaseAudit))
                           ((phaseAudit) (phaseVerify))
                           ((phaseVerify) (phaseSettle))
                           (_ (phaseFailed))))]
          (with loop :currentPhase nextPhase :iterationCount (+ loop.iterationCount 1) :lastMessage detail :lastFailureSig "" :consecutiveFailures 0)))))

fn computeTaskEntropyDynamic taskDesc: Str -> I64
  (let [(len (stringLength taskDesc))]
    (if (<= len 0)
      0
      (+ (/ len 10) 1)))

fn calibrateDynamicTokenBudget baseBudget: I64 entropy: I64 -> I64
  (+ baseBudget (* entropy 50))
