(module aslBench/attentionProsthesis
  :d "Evaluation of attention policies, paired arms, repeated reliable task outcomes, and cost/retrieval efficiency."
  :x [TrialResult
      PolicyEvaluation
      makeTrialResult
      makePolicyEvaluation
      evaluateTrialConsistency
      isConstraintPreserved?
      isObservationRecoverable?
      calculatePassRate
      calculateMeanCost
      runTests]
  :i [])

(dfs TrialResult
  (:f taskId Str "Task identifier")
  (:f policyArm Str "Policy arm: baseline, ledger-only, observation-masking, relevant-retrieval, summary")
  (:f runIndex I64 "Repeated run index")
  (:f outcomeCorrect Bool "True if semantic gate passed cleanly")
  (:f costUsd Float "Dollar cost for trial")
  (:f latencyMs I64 "Latency in milliseconds")
  (:f retries I64 "Number of tool retries")
  (:f aggregateRetrievalTokens I64 "Total tokens retrieved")
  (:f aggregateOutputTokens I64 "Total tokens generated")
  (:f cacheReads I64 "Provider cache reads")
  (:f cacheWrites I64 "Provider cache writes")
  (:f cacheMisses I64 "Provider cache misses")
  (:f hasProviderData Bool "True if provider telemetry is present")
  (:f constraintsSatisfied Bool "True if constraints remained satisfied")
  (:f observationRecovered Bool "True if observation recovered from source")
  (:f confidenceScore Float "Confidence score")
  (:f abstentionFlag Bool "True if model correctly abstained"))

(dfs PolicyEvaluation
  (:f policyArm Str "Evaluated attention policy arm")
  (:f totalRuns I64 "Total repeated trials evaluated")
  (:f successfulRuns I64 "Successful runs with correct outcomes")
  (:f passRate Float "Ratio of successful runs to total runs")
  (:f meanCostUsd Float "Average cost per trial")
  (:f meanLatencyMs I64 "Average latency across trials")
  (:f constraintSatisfactionRate Float "Ratio of runs preserving constraints")
  (:f observationRecoveryRate Float "Ratio of runs recovering observations"))

(df makeTrialResult [(taskId Str)
                       (policyArm Str)
                       (runIndex I64)
                       (outcomeCorrect Bool)
                       (costUsd Float)
                       (latencyMs I64)
                       (retries I64)
                       (retrievalTokens I64)
                       (outputTokens I64)
                       (cacheReads I64)
                       (cacheWrites I64)
                       (cacheMisses I64)
                       (hasProviderData Bool)
                       (constraintsSatisfied Bool)
                       (observationRecovered Bool)
                       (confidenceScore Float)
                       (abstentionFlag Bool)] -> TrialResult
  :d "Constructs a single trial result record."
  (TrialResult
    :taskId taskId
    :policyArm policyArm
    :runIndex runIndex
    :outcomeCorrect outcomeCorrect
    :costUsd costUsd
    :latencyMs latencyMs
    :retries retries
    :aggregateRetrievalTokens retrievalTokens
    :aggregateOutputTokens outputTokens
    :cacheReads cacheReads
    :cacheWrites cacheWrites
    :cacheMisses cacheMisses
    :hasProviderData hasProviderData
    :constraintsSatisfied constraintsSatisfied
    :observationRecovered observationRecovered
    :confidenceScore confidenceScore
    :abstentionFlag abstentionFlag))

(df isConstraintPreserved? [(trial TrialResult)] -> Bool
  :d "Verifies whether constraints remained satisfied during compaction or execution."
  (.-constraintsSatisfied trial))

(df isObservationRecoverable? [(trial TrialResult)] -> Bool
  :d "Verifies whether masked observations were recovered via source references."
  (.-observationRecovered trial))

(df calculatePassRate [(successful I64) (total I64)] -> Float
  :d "Calculates the fractional pass rate with zero check."
  (if (> total 0)
    (/ (* 1.0 successful) (* 1.0 total))
    0.0))

(df calculateMeanCost [(totalCost Float) (runs I64)] -> Float
  :d "Calculates the average dollar cost per run."
  (if (> runs 0)
    (/ totalCost (* 1.0 runs))
    0.0))

(df makePolicyEvaluation [(policyArm Str)
                            (totalRuns I64)
                            (successfulRuns I64)
                            (totalCost Float)
                            (totalLatencyMs I64)
                            (constraintsSatisfiedCount I64)
                            (observationsRecoveredCount I64)] -> PolicyEvaluation
  :d "Aggregates trial results into a policy evaluation summary."
  (let [(pRate (calculatePassRate successfulRuns totalRuns))
        (mCost (calculateMeanCost totalCost totalRuns))
        (mLat (if (> totalRuns 0) (/ totalLatencyMs totalRuns) 0))
        (cRate (calculatePassRate constraintsSatisfiedCount totalRuns))
        (oRate (calculatePassRate observationsRecoveredCount totalRuns))]
    (PolicyEvaluation
      :policyArm policyArm
      :totalRuns totalRuns
      :successfulRuns successfulRuns
      :passRate pRate
      :meanCostUsd mCost
      :meanLatencyMs mLat
      :constraintSatisfactionRate cRate
      :observationRecoveryRate oRate)))

(df evaluateTrialConsistency [(t1 TrialResult) (t2 TrialResult)] -> Bool
  :d "Evaluates whether two runs of the same task and policy produced consistent outcomes."
  (and (= (.-taskId t1) (.-taskId t2))
       (and (= (.-policyArm t1) (.-policyArm t2))
            (= (.-outcomeCorrect t1) (.-outcomeCorrect t2)))))

(df runTests [] -> Bool
  :d "Validates attention prosthesis measurement primitives and invariants."
  (let [(t1 (makeTrialResult "Task-Eval-01" "observation-masking" 1 true 0.0042 320 0 1450 380 1200 0 250 true true true 0.95 false))
        (t2 (makeTrialResult "Task-Eval-01" "observation-masking" 2 true 0.0039 310 0 1450 375 1200 0 250 true true true 0.94 false))
        (eval (makePolicyEvaluation "observation-masking" 2 2 0.0081 630 2 2))]
    (assert (isConstraintPreserved? t1) "Constraints must be preserved in trial 1")
    (assert (isObservationRecoverable? t1) "Observations must be recoverable in trial 1")
    (assert (evaluateTrialConsistency t1 t2) "Repeated runs must exhibit outcome consistency")
    (assert (= (.-passRate eval) 1.0) "Pass rate must be 1.0 for 2/2 successful trials")
    (assert (> (.-meanCostUsd eval) 0.0) "Mean cost must be greater than zero")
    true))
