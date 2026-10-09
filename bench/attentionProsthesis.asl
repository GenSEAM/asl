(module aslBench/attentionProsthesis :x [TrialResult PolicyEvaluation makeTrialResult makePolicyEvaluation evaluateTrialConsistency isConstraintPreserved? isObservationRecoverable? calculatePassRate calculateMeanCost runTests] :i [])

(schema TrialResult (:f taskId Str) (:f policyArm Str) (:f runIndex I64) (:f outcomeCorrect Bool) (:f costUsd Float) (:f latencyMs I64) (:f retries I64) (:f aggregateRetrievalTokens I64) (:f aggregateOutputTokens I64) (:f cacheReads I64) (:f cacheWrites I64) (:f cacheMisses I64) (:f hasProviderData Bool) (:f constraintsSatisfied Bool) (:f observationRecovered Bool) (:f confidenceScore Float) (:f abstentionFlag Bool))

(schema PolicyEvaluation (:f policyArm Str) (:f totalRuns I64) (:f successfulRuns I64) (:f passRate Float) (:f meanCostUsd Float) (:f meanLatencyMs I64) (:f constraintSatisfactionRate Float) (:f observationRecoveryRate Float))

fn makeTrialResult taskId: Str policyArm: Str runIndex: I64 outcomeCorrect: Bool costUsd: Float latencyMs: I64 retries: I64 retrievalTokens: I64 outputTokens: I64 cacheReads: I64 cacheWrites: I64 cacheMisses: I64 hasProviderData: Bool constraintsSatisfied: Bool observationRecovered: Bool confidenceScore: Float abstentionFlag: Bool -> TrialResult
  (TrialResult :taskId taskId :policyArm policyArm :runIndex runIndex :outcomeCorrect outcomeCorrect :costUsd costUsd :latencyMs latencyMs :retries retries :aggregateRetrievalTokens retrievalTokens :aggregateOutputTokens outputTokens :cacheReads cacheReads :cacheWrites cacheWrites :cacheMisses cacheMisses :hasProviderData hasProviderData :constraintsSatisfied constraintsSatisfied :observationRecovered observationRecovered :confidenceScore confidenceScore :abstentionFlag abstentionFlag)

fn isConstraintPreserved? trial: TrialResult -> Bool
  trial.constraintsSatisfied

fn isObservationRecoverable? trial: TrialResult -> Bool
  trial.observationRecovered

fn calculatePassRate successful: I64 total: I64 -> Float
  (if (> total 0) (/ (int64ToFloat64 successful) (int64ToFloat64 total)) 0.0)

fn calculateMeanCost totalCost: Float runs: I64 -> Float
  (if (> runs 0) (/ totalCost (int64ToFloat64 runs)) 0.0)

fn makePolicyEvaluation policyArm: Str totalRuns: I64 successfulRuns: I64 totalCost: Float totalLatencyMs: I64 constraintsSatisfiedCount: I64 observationsRecoveredCount: I64 -> PolicyEvaluation
  (let [(pRate (calculatePassRate successfulRuns totalRuns)) (mCost (calculateMeanCost totalCost totalRuns)) (mLat (if (> totalRuns 0) (/ totalLatencyMs totalRuns) 0)) (cRate (calculatePassRate constraintsSatisfiedCount totalRuns)) (oRate (calculatePassRate observationsRecoveredCount totalRuns))] (PolicyEvaluation :policyArm policyArm :totalRuns totalRuns :successfulRuns successfulRuns :passRate pRate :meanCostUsd mCost :meanLatencyMs mLat :constraintSatisfactionRate cRate :observationRecoveryRate oRate))

fn evaluateTrialConsistency t1: TrialResult t2: TrialResult -> Bool
  (and (= t1.taskId t2.taskId) (and (= t1.policyArm t2.policyArm) (= t1.outcomeCorrect t2.outcomeCorrect)))

fn runTests -> Bool
  (let [(t1 (makeTrialResult "Task-Eval-01" "observation-masking" 1 true 0.0042 320 0 1450 380 1200 0 250 true true true 0.95 false)) (t2 (makeTrialResult "Task-Eval-01" "observation-masking" 2 true 0.0039 310 0 1450 375 1200 0 250 true true true 0.94 false)) (eval (makePolicyEvaluation "observation-masking" 2 2 0.0081 630 2 2))] (assert (isConstraintPreserved? t1) "Constraints must be preserved in trial 1") (assert (isObservationRecoverable? t1) "Observations must be recoverable in trial 1") (assert (evaluateTrialConsistency t1 t2) "Repeated runs must exhibit outcome consistency") (assert (= eval.passRate 1.0) "Pass rate must be 1.0 for 2/2 successful trials") (assert (> eval.meanCostUsd 0.0) "Mean cost must be greater than zero") true)
