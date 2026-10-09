(module aslHarness/stepsPipeline
  :x [StepPhase GapAuditResult StepsPipeline AddieConfig
      PipelineStage ReflectionConfig ReflectionVerdict
      defaultReflectionConfig evaluateFidelityGate
      evaluatePromptFidelity selectPipelineProfile
      computeTaskEntropy makeEpistemic7Phases make7StagePipeline
      createStepsPipeline addPipelinePhase
      auditPlanGaps auditImplGaps
      advancePipelineStage pipelineStatusSummary
      makeStandardPhases classifyTaskEntropy
      makePipelineByMode defaultAddieConfig
      makeReflectionConfig executeEpistemicPipeline
      evaluateStageTeleology
      AdaptiveDAGConfig EpistemicStepRecord
      makeAdaptiveDagConfig isReplanExhausted?
      triggerAdaptiveReplan recordEpistemicPrimitive
      advancePipelineStageAdaptive]
  :i [(operationalModel :a op)
      (teleology :a tel)])

(schema StepPhase
  (:f id Str)
  (:f name Str)
  (:f stage Str)
  (:f gateCommand Str)
  (:f status Str)
  (:f findings (List Str)))

(schema GapAuditResult
  (:f verdict Str)
  (:f omissions (List Str))
  (:f bloatWarnings (List Str))
  (:f invariantsPreserved Bool)
  (:f recommendations (List Str)))

(schema StepsPipeline
  (:f taskId Str)
  (:f taskInstruction Str)
  (:f activeStage Str)
  (:f phases (List StepPhase))
  (:f currentPhaseIdx I64)
  (:f gapAudits (List GapAuditResult))
  (:f isCompleted Bool)
  (:f finalStatus Str))

(schema AdaptiveDAGConfig
  (:f maxReplanIterations I64)
  (:f currentReplanCount I64)
  (:f autoDiagnose Bool)
  (:f allowRecovery Bool))

(schema EpistemicStepRecord
  (:f stepType Str)
  (:f target Str)
  (:f executed Bool)
  (:f details Str))

(enum PipelineStage
  (:c s1Ingest      [] "Ingestion and boundary normalization of task instruction and invariants")
  (:c s2Reformulate [] "Operational self-reformulation: explicit restatement of goal and constraints")
  (:c s3IntentGate [] "Intent-Fidelity Gate: validates reformulation against prompt before planning")
  (:c s4Plan        [] "Action DAG decomposition with falsifiable verification gates")
  (:c s5PlanGate   [] "Pre-mortem plan gate: detects ungrounded assumptions and omissions")
  (:c s6Implement   [] "Phased implementation under staged buffer isolation")
  (:c s7Verify      [] "Post-execution verification against genuine execution receipts"))

(schema ReflectionConfig
  (:f enabledStages (List PipelineStage))
  (:f minFidelityScore F64)
  (:f allowFastPath Bool)
  (:f strictFalsify Bool))

(schema ReflectionVerdict
  (:f stage PipelineStage)
  (:f passed Bool)
  (:f hallucinations (List Str))
  (:f omittedConstraints (List Str))
  (:f confidenceScore F64))

"Constructs a ReflectionConfig with specified stages and fidelity threshold."
fn makeReflectionConfig stages: (List PipelineStage) minScore: F64 fastPath: Bool strict: Bool -> ReflectionConfig
  (ReflectionConfig
    :enabledStages stages
    :minFidelityScore minScore
    :allowFastPath fastPath
    :strictFalsify strict)

"Constructs standard canonical ReflectionConfig enabling all 7 stages."
fn defaultReflectionConfig -> ReflectionConfig
  (ReflectionConfig
    :enabledStages [(s1Ingest) (s2Reformulate) (s3IntentGate) (s4Plan) (s5PlanGate) (s6Implement) (s7Verify)]
    :minFidelityScore 0.95
    :allowFastPath false
    :strictFalsify true)

"Evaluates whether reflection verdict passes the configured fidelity threshold."
fn evaluateFidelityGate verdict: ReflectionVerdict cfg: ReflectionConfig -> Bool
  (and verdict.passed
       (>= verdict.confidenceScore cfg.minFidelityScore))

"Audits agent reformulation against original prompt to prevent scope hallucination and omitted constraints."
fn evaluatePromptFidelity originalPrompt: Str agentReformulation: Str threshold: F64 -> ReflectionVerdict
  (let [(normPrompt (stringLower originalPrompt))
        (normRef (stringLower agentReformulation))
        (hasContent (and (not (stringEmpty? normPrompt)) (not (stringEmpty? normRef))))]
    (if (not hasContent)
      (ReflectionVerdict
        :stage (s3IntentGate)
        :passed false
        :hallucinations (list)
        :omittedConstraints (list "Empty prompt or reformulation provided")
        :confidenceScore 0.0)
      (let [(words (stringSplit normPrompt " "))
            (matchedCount (listLength (filter (fn [(w Str)] -> Bool (and (> (stringLength w) 3) (stringContains? normRef w))) words)))
            (candidateCount (listLength (filter (fn [(w Str)] -> Bool (> (stringLength w) 3)) words)))
            (score (if (> candidateCount 0)
                     (/ (int64ToFloat64 matchedCount) (int64ToFloat64 candidateCount))
                     1.0))
            (isPassed (>= score threshold))
            (omissions (if isPassed (list) (list "Reformulation omitted critical constraint terms from original prompt")))]
        (ReflectionVerdict
          :stage (s3IntentGate)
          :passed isPassed
          :hallucinations (list)
          :omittedConstraints omissions
          :confidenceScore score))))

"Strips common syntax delimiters from path or identifier tokens."
fn cleanPathToken tok: Str -> Str
  (let [(t1 (stringReplace tok "," ""))
        (t2 (stringReplace t1 ";" ""))
        (t3 (stringReplace t2 "\"" ""))
        (t4 (stringReplace t3 "'" ""))
        (t5 (stringReplace t4 "`" ""))
        (t6 (stringReplace t5 "(" ""))
        (t7 (stringReplace t6 ")" ""))]
    t7)

"Executes epistemic reflection verification against the operational model, detecting invariant omissions and hallucinations."
fn executeEpistemicPipeline instruction: Str model: op/OperationalModel cfg: ReflectionConfig -> ReflectionVerdict
  (let [(normInst (stringLower instruction))
        (normExit (stringLower model.expectedExitBehavior))
        (words (stringSplit instruction " "))
        (cleanedWords (map (fn [(w Str)] -> Str (cleanPathToken w)) words))
        (candidatePaths (filter (fn [(w Str)] -> Bool
                                   (and (> (stringLength w) 3)
                                        (or (stringContains? w "/")
                                            (or (stringEndsWith? w ".asl")
                                                (or (stringEndsWith? w ".asn")
                                                    (stringEndsWith? w ".ts"))))))
                                 cleanedWords))
        (omittedFiles (filter (fn [(cp Str)] -> Bool
                                 (= (listLength (filter (fn [(tf Str)] -> Bool
                                                           (or (= tf cp)
                                                               (stringContains? tf cp)))
                                                         model.targetFiles)) 0))
                               candidatePaths))
        (omittedFileMsgs (map (fn [(f Str)] -> Str (str "Missing target file in operational model: " f)) omittedFiles))
        (flags1 (if (and (stringContains? normInst "argv")
                          (not (stringContains? normExit "argv")))
                     (list "Missing command-line argument handling requirement (argv)")
                     (list)))
        (flags2 (if (and (stringContains? normInst "exit")
                          (not (stringContains? normExit "exit")))
                     (listAppend flags1 (list "Missing verification exit behavior expectation"))
                     flags1))
        (flags3 (if (and (stringContains? normInst "strict-falsify")
                          (not (stringContains? normExit "strict-falsify")))
                     (listAppend flags2 (list "Missing strict-falsify verification expectation"))
                     flags2))
        (hasNeg (or (stringContains? normInst "forbidden")
                     (or (stringContains? normInst "do not")
                         (or (stringContains? normInst "never")
                             (or (stringContains? normInst "without")
                                 (or (stringContains? normInst "no foreign")
                                     (stringContains? normInst "zero foreign")))))))
        (omittedFlags (if (and hasNeg (listEmpty? model.forbiddenSideEffects))
                           (listAppend flags3 (list "Omitted negative constraint preservation from instruction into forbidden side-effects"))
                           flags3))
        (allOmissions (listAppend omittedFileMsgs omittedFlags))
        (hallucinatedFiles (filter (fn [(tf Str)] -> Bool
                                      (not (or (stringContains? instruction tf)
                                               (> (listLength (filter (fn [(cp Str)] -> Bool
                                                                         (or (stringContains? tf cp)
                                                                             (stringContains? cp tf)))
                                                                       candidatePaths))
                                                  0))))
                                    model.targetFiles))
        (hallucinatedFileMsgs (map (fn [(f Str)] -> Str (str "Hallucinated unanchored target file: " f)) hallucinatedFiles))
        (hallucinatedSymbols (filter (fn [(sym Str)] -> Bool
                                        (not (stringContains? normInst (stringLower sym))))
                                      model.requiredSymbols))
        (hallucinatedSymbolMsgs (map (fn [(s Str)] -> Str (str "Hallucinated ungrounded required symbol or external dependency: " s)) hallucinatedSymbols))
        (allHallucinations (listAppend hallucinatedFileMsgs hallucinatedSymbolMsgs))
        (oCount (listLength allOmissions))
        (hCount (listLength allHallucinations))
        (penalty (+ (* (int64ToFloat64 oCount) 0.3) (* (int64ToFloat64 hCount) 0.4)))
        (rawScore (- 1.0 penalty))
        (confidenceScore (if (< rawScore 0.0) 0.0 rawScore))
        (isPassed (and (= oCount 0) (and (= hCount 0) (>= confidenceScore cfg.minFidelityScore))))]
    (ReflectionVerdict
      :stage (s3IntentGate)
      :passed isPassed
      :hallucinations allHallucinations
      :omittedConstraints allOmissions
      :confidenceScore confidenceScore))

(schema AddieConfig
  (:f model Str "Inference model identifier")
  (:f pipeline Str "Default pipeline: full | adaptive | standard | fast")
  (:f aslFirst Bool "Use dense ASN tool calls and telemetry")
  (:f scoutPolyglot Bool "Inspect polyglot runtimes in scout phase"))

"Returns canonical default Addie configuration."
fn defaultAddieConfig -> AddieConfig
  (AddieConfig
    :model "openai/gemma-4-31b-it"
    :pipeline "full"
    :aslFirst true
    :scoutPolyglot true)

"Classifies task complexity to select optimal pipeline mode: fast | standard | full."
fn classifyTaskEntropy instruction: Str -> Str
  (let ((lower (stringLower instruction)))
    (cond
      ((or (stringContains? lower "tb-")
           (stringContains? lower "terminal-bench")
           (stringContains? lower "vulnerability")
           (stringContains? lower "xss")
           (stringContains? lower "exploit")
           (stringContains? lower "crypto")
           (stringContains? lower "vigenere")
           (stringContains? lower "dedup")
           (stringContains? lower "security")
           (stringContains? lower "sanitize"))
       "full")
      ((or (stringContains? lower "typo")
           (stringContains? lower "rename")
           (stringContains? lower "one-line")
           (stringContains? lower "trivial")
           (stringContains? lower "docstring"))
       "fast")
      (else
       "standard")))

"Computes continuous task entropy score H_task based on file count, domain depth, ambiguity, and security criticality."
fn computeTaskEntropy nFiles: I64 domainScore: F64 ambiguity: F64 securityCrit: F64 -> F64
  (let [(w1 0.5)
        (w2 1.5)
        (w3 1.0)
        (w4 1.5)
        (fVal (int64ToFloat64 nFiles))]
    (+ (+ (* w1 fVal) (* w2 domainScore))
       (+ (* w3 ambiguity) (* w4 securityCrit))))

"Selects execution profile based on task entropy: fast (< 1.5), standard (1.5 - 4.0), full (>= 4.0)."
fn selectPipelineProfile entropy: F64 -> Str
  (cond
    ((< entropy 1.5) "fast")
    ((< entropy 4.0) "standard")
    (else "full"))

"Generates full 7-stage epistemic reflection pipeline execution phases."
fn makeEpistemic7Phases taskId: Str -> (List StepPhase)
  (list
    (StepPhase
      :id "stage-1-ingest"
      :name "Ingest Task & Parse Invariants"
      :stage "s1-ingest"
      :gateCommand "test -n \"$TASK_INSTRUCTION\""
      :status "pending"
      :findings (list))
    (StepPhase
      :id "stage-2-reformulate"
      :name "Operational Self-Reformulation"
      :stage "s2-reformulate"
      :gateCommand "test -f REFORMULATION.md"
      :status "pending"
      :findings (list))
    (StepPhase
      :id "stage-3-intent-gate"
      :name "Intent-Fidelity Gate Verification"
      :stage "s3-intent-gate"
      :gateCommand "asl test --strict-falsify harness/tests/epistemic_pipeline_test.asl"
      :status "pending"
      :findings (list))
    (StepPhase
      :id "stage-4-plan"
      :name "Action DAG Decomposition & Gate Formulation"
      :stage "s4-plan"
      :gateCommand "test -f PLAN.md"
      :status "pending"
      :findings (list))
    (StepPhase
      :id "stage-5-plan-gate"
      :name "Pre-Mortem Plan Verification"
      :stage "s5-plan-gate"
      :gateCommand "test -f REVIEW.md"
      :status "pending"
      :findings (list))
    (StepPhase
      :id "stage-6-implement"
      :name "Phased Implementation"
      :stage "s6-implement"
      :gateCommand "asl rpc '(:batch (:diff))'"
      :status "pending"
      :findings (list))
    (StepPhase
      :id "stage-7-verify"
      :name "Post-Execution Receipt Verification"
      :stage "s7-verify"
      :gateCommand "asl gate"
      :status "pending"
      :findings (list)))

"Instantiates full 7-stage epistemic reflection pipeline."
fn make7StagePipeline taskId: Str instruction: Str -> StepsPipeline
  (StepsPipeline
    :taskId taskId
    :taskInstruction instruction
    :activeStage "s1-ingest"
    :phases (makeEpistemic7Phases taskId)
    :currentPhaseIdx 0
    :gapAudits (list)
    :isCompleted false
    :finalStatus "pending")

"Generates standard 5-phase canonical Steps+GAP execution phases for an autonomous task."
fn makeStandardPhases taskId: Str -> (List StepPhase)
  [
    (StepPhase
      :id "phase-1-scout"
      :name "Environment Reconnaissance & Fact Discovery"
      :stage "scout"
      :gateCommand "ls -la && env"
      :status "pending"
      :findings [])
    (StepPhase
      :id "phase-2-plan"
      :name "Phased Decomposition & Gate Formulation"
      :stage "plan"
      :gateCommand "cat PLAN.md"
      :status "pending"
      :findings [])
    (StepPhase
      :id "phase-3-gap-plan"
      :name "Plan-to-Instruction Pre-Implementation GAP Audit"
      :stage "gap-plan"
      :gateCommand "cat REVIEW.md"
      :status "pending"
      :findings [])
    (StepPhase
      :id "phase-4-impl"
      :name "Phased Implementation with Step Gates"
      :stage "impl"
      :gateCommand "test -f output.ready"
      :status "pending"
      :findings [])
    (StepPhase
      :id "phase-5-gap-impl"
      :name "Post-Implementation GAP Audit & Negative Test Verification"
      :stage "gap-impl"
      :gateCommand "pytest tests/ || ./test.sh"
      :status "pending"
      :findings [])
  ]

"Instantiates StepsPipeline configured for specified mode: fast | standard | full | adaptive."
fn makePipelineByMode taskId: Str instruction: Str mode: Str -> StepsPipeline
  (let ((effectiveMode (if (= mode "adaptive")
                          (classifyTaskEntropy instruction)
                          mode)))
    (cond
      ((= effectiveMode "fast")
       (StepsPipeline
         :taskId taskId
         :taskInstruction instruction
         :activeStage "impl"
         :phases [
           (StepPhase
             :id "phase-1-impl"
             :name "Direct Targeted Implementation"
             :stage "impl"
             :gateCommand "git status -s"
             :status "pending"
             :findings [])
           (StepPhase
             :id "phase-2-verify"
             :name "Fast Verification & Settle"
             :stage "verify"
             :gateCommand "git diff"
             :status "pending"
             :findings [])
         ]
         :currentPhaseIdx 0
         :gapAudits []
         :isCompleted false
         :finalStatus "pending"))
      ((= effectiveMode "standard")
       (StepsPipeline
         :taskId taskId
         :taskInstruction instruction
         :activeStage "plan"
         :phases [
           (StepPhase
             :id "phase-1-plan"
             :name "Implementation Plan"
             :stage "plan"
             :gateCommand "cat PLAN.md"
             :status "pending"
             :findings [])
           (StepPhase
             :id "phase-2-impl"
             :name "Implementation"
             :stage "impl"
             :gateCommand "test -f output.ready"
             :status "pending"
             :findings [])
           (StepPhase
             :id "phase-3-verify"
             :name "Verification Gate"
             :stage "verify"
             :gateCommand "pytest || ./test.sh"
             :status "pending"
             :findings [])
         ]
         :currentPhaseIdx 0
         :gapAudits []
         :isCompleted false
         :finalStatus "pending"))
      (else
       (StepsPipeline
         :taskId taskId
         :taskInstruction instruction
         :activeStage "scout"
         :phases (makeStandardPhases taskId)
         :currentPhaseIdx 0
         :gapAudits []
         :isCompleted false
         :finalStatus "pending"))))

"Instantiates a new autonomous Steps pipeline."
fn createStepsPipeline taskId: Str instruction: Str -> StepsPipeline
  (makePipelineByMode taskId instruction "full")

"Appends a custom phase to the pipeline."
fn addPipelinePhase pipeline: StepsPipeline phase: StepPhase -> StepsPipeline
  (with pipeline :phases (listAppend pipeline.phases [phase]))

"Evaluates whether an action in the current pipeline stage adheres to the appropriate teleological mandate."
fn evaluateStageTeleology stageName: Str proposedAction: Str -> Bool
  (let ((lowerStage (stringLower stageName)))
    (cond
      ((or (stringContains? lowerStage "scout") (= lowerStage "s1-ingest"))
       (tel/validateActionAgainstMandate (tel/makeScoutMandate) proposedAction))
      ((or (stringContains? lowerStage "plan") (= lowerStage "s4-plan"))
       (tel/validateActionAgainstMandate (tel/makePlannerMandate) proposedAction))
      ((or (stringContains? lowerStage "impl") (= lowerStage "s6-implement"))
       (tel/validateActionAgainstMandate (tel/makeImplementerMandate) proposedAction))
      ((or (stringContains? lowerStage "gap") (stringContains? lowerStage "verify") (= lowerStage "s7-verify"))
       (tel/validateActionAgainstMandate (tel/makeAuditorMandate) proposedAction))
      (else true)))

"Audits a proposed plan against the original instruction to detect omissions and bloat."
fn auditPlanGaps instruction: Str plannedSteps: (List Str) -> GapAuditResult
  (let ((joined (stringJoin plannedSteps " "))
        (o1 (if (and (stringContains? instruction "argv")
                     (not (stringContains? joined "arg")))
              ["Missing command-line argument handling (argv)"]
              []))
        (o2 (if (and (stringContains? instruction "exit")
                     (not (stringContains? joined "exit")))
              (listAppend o1 ["Missing exit code handling requirement"])
              o1))
        (o3 (if (and (stringContains? instruction "in-place")
                     (not (stringContains? joined "in-place")))
              (listAppend o2 ["Missing in-place file modification check"])
              o2))
        (omissions (if (not (tel/validateActionAgainstMandate (tel/makePlannerMandate) joined))
                     (listAppend o3 ["Teleological mandate violation: plan contains ungrounded steps without verification gates"])
                     o3))
        (bloat (if (> (listLength plannedSteps) 8)
                 ["Excessive phase count: plan exceeds 8 steps, risk of over-engineering"]
                 []))
        (hasOmissions (> (listLength omissions) 0))
        (hasBloat (> (listLength bloat) 0)))
    (cond
      (hasOmissions
       (GapAuditResult
         :verdict "approve-with-amendments"
         :omissions omissions
         :bloatWarnings bloat
         :invariantsPreserved false
         :recommendations ["Incorporate missing requirements into plan before implementing."]))
      (hasBloat
       (GapAuditResult
         :verdict "approve-with-amendments"
         :omissions []
         :bloatWarnings bloat
         :invariantsPreserved true
         :recommendations ["Simplify plan: collapse redundant intermediate steps."]))
      (else
       (GapAuditResult
         :verdict "approve"
         :omissions []
         :bloatWarnings []
         :invariantsPreserved true
         :recommendations ["Plan is complete, minimal, and verified against instruction."]))))

"Audits a completed implementation against the instruction and test results."
fn auditImplGaps instruction: Str diff: Str testsPassed: Bool -> GapAuditResult
  (cond
    ((not testsPassed)
     (GapAuditResult
       :verdict "reject"
       :omissions ["Automated verification gate failed; regression detected"]
       :bloatWarnings []
       :invariantsPreserved false
       :recommendations ["Inspect failing test trace, apply targeted fix, re-run gate."]))
    ((stringEmpty? diff)
     (GapAuditResult
       :verdict "reject"
       :omissions ["No code diff produced; task not implemented"]
       :bloatWarnings []
       :invariantsPreserved false
       :recommendations ["Produce required code implementation."]))
    ((not (tel/validateActionAgainstMandate (tel/makeImplementerMandate) diff))
     (GapAuditResult
       :verdict "reject"
       :omissions ["Teleological mandate violation: implementation attempted gate tampering or unauthorized modification"]
       :bloatWarnings []
       :invariantsPreserved false
       :recommendations ["Preserve all verification gates without weakening or skipping."]))
    ((and (stringContains? instruction "in-place")
          (not (stringContains? diff "write")))
     (GapAuditResult
       :verdict "approve-with-amendments"
       :omissions ["Ensure file is modified in-place"]
       :bloatWarnings []
       :invariantsPreserved true
       :recommendations ["Verify in-place write to disk."]))
    (else
     (GapAuditResult
       :verdict "approve"
       :omissions []
       :bloatWarnings []
       :invariantsPreserved true
       :recommendations ["All functional and quality invariants verified."])))

"Transitions pipeline to the next stage upon gate pass, or records failure."
fn advancePipelineStage pipeline: StepsPipeline gatePassed: Bool output: Str -> StepsPipeline
  (if (not gatePassed)
    (with pipeline :isCompleted false :finalStatus "failed")
    (let ((nextIdx (+ pipeline.currentPhaseIdx 1))
          (total (listLength pipeline.phases)))
      (if (>= nextIdx total)
        (with pipeline :activeStage "settle" :currentPhaseIdx nextIdx :isCompleted true :finalStatus "verified")
        (let ((nextPhase (mt (listGet pipeline.phases nextIdx) ((some ph) ph))))
          (with pipeline :activeStage nextPhase.stage :currentPhaseIdx nextIdx :isCompleted false :finalStatus "pending")))))

"Produces a compact human-readable status summary of the pipeline."
fn pipelineStatusSummary pipeline: StepsPipeline -> Str
  (str "StepsPipeline [" pipeline.taskId "]: stage=" pipeline.activeStage 
       " | progress=" (stringFromInt64 pipeline.currentPhaseIdx) "/" (stringFromInt64 (listLength pipeline.phases))
       " | completed=" (if pipeline.isCompleted "true" "false")
       " | status=" pipeline.finalStatus)

"Constructs canonical AdaptiveDAGConfig with homeostatic recovery ceiling."
fn makeAdaptiveDagConfig maxReplan: I64 autoDiag: Bool -> AdaptiveDAGConfig
  (AdaptiveDAGConfig
    :maxReplanIterations maxReplan
    :currentReplanCount 0
    :autoDiagnose autoDiag
    :allowRecovery true)

"Checks whether dynamic replan attempts have reached maximum ceiling."
fn isReplanExhausted? cfg: AdaptiveDAGConfig -> Bool
  (>= cfg.currentReplanCount cfg.maxReplanIterations)

"Dynamically triggers homeostatic replanning upon gate failure if under recovery limit."
fn triggerAdaptiveReplan pipeline: StepsPipeline cfg: AdaptiveDAGConfig failureReason: Str -> StepsPipeline
  (if (isReplanExhausted? cfg)
    (with pipeline :isCompleted false :finalStatus "failed")
    (let [(replanIdx (+ cfg.currentReplanCount 1))
          (triagePhase (StepPhase
                          :id (str "triage-" (stringFromInt64 replanIdx))
                          :name "Adaptive Root-Cause Triage & Recovery DAG"
                          :stage "plan"
                          :gateCommand "asl check .asl/mem/tasks/in_flight.asn"
                          :status "running"
                          :findings (list (str "Auto-diagnose: " failureReason))))]
      (with pipeline :activeStage "plan" :phases (listAppend pipeline.phases (list triagePhase)) :isCompleted false :finalStatus "replanning")))

"Constructs an EpistemicStepRecord capturing verified operational discipline."
fn recordEpistemicPrimitive stepType: Str target: Str details: Str -> EpistemicStepRecord
  (EpistemicStepRecord
    :stepType stepType
    :target target
    :executed true
    :details details)

"Transitions pipeline stage with adaptive replan fallback upon gate failure."
fn advancePipelineStageAdaptive pipeline: StepsPipeline gatePassed: Bool output: Str cfg: AdaptiveDAGConfig -> StepsPipeline
  (if gatePassed
    (advancePipelineStage pipeline true output)
    (triggerAdaptiveReplan pipeline cfg output))
