(module asl-bench/attention-prosthesis
  :d "Evaluation of attention policies, paired arms, repeated reliable task outcomes, and cost/retrieval efficiency."
  :x [TrialResult
      PolicyEvaluation
      make-trial-result
      make-policy-evaluation
      evaluate-trial-consistency
      is-constraint-preserved?
      is-observation-recoverable?
      calculate-pass-rate
      calculate-mean-cost
      run-tests]
  :i [])

(dfs TrialResult
  (:f task-id Str "Task identifier")
  (:f policy-arm Str "Policy arm: baseline, ledger-only, observation-masking, relevant-retrieval, summary")
  (:f run-index I64 "Repeated run index")
  (:f outcome-correct Bool "True if semantic gate passed cleanly")
  (:f cost-usd Float "Dollar cost for trial")
  (:f latency-ms I64 "Latency in milliseconds")
  (:f retries I64 "Number of tool retries")
  (:f aggregate-retrieval-tokens I64 "Total tokens retrieved")
  (:f aggregate-output-tokens I64 "Total tokens generated")
  (:f cache-reads I64 "Provider cache reads")
  (:f cache-writes I64 "Provider cache writes")
  (:f cache-misses I64 "Provider cache misses")
  (:f has-provider-data Bool "True if provider telemetry is present")
  (:f constraints-satisfied Bool "True if constraints remained satisfied")
  (:f observation-recovered Bool "True if observation recovered from source")
  (:f confidence-score Float "Confidence score")
  (:f abstention-flag Bool "True if model correctly abstained"))

(dfs PolicyEvaluation
  (:f policy-arm Str "Evaluated attention policy arm")
  (:f total-runs I64 "Total repeated trials evaluated")
  (:f successful-runs I64 "Successful runs with correct outcomes")
  (:f pass-rate Float "Ratio of successful runs to total runs")
  (:f mean-cost-usd Float "Average cost per trial")
  (:f mean-latency-ms I64 "Average latency across trials")
  (:f constraint-satisfaction-rate Float "Ratio of runs preserving constraints")
  (:f observation-recovery-rate Float "Ratio of runs recovering observations"))

(df make-trial-result [(task-id Str)
                       (policy-arm Str)
                       (run-index I64)
                       (outcome-correct Bool)
                       (cost-usd Float)
                       (latency-ms I64)
                       (retries I64)
                       (retrieval-tokens I64)
                       (output-tokens I64)
                       (cache-reads I64)
                       (cache-writes I64)
                       (cache-misses I64)
                       (has-provider-data Bool)
                       (constraints-satisfied Bool)
                       (observation-recovered Bool)
                       (confidence-score Float)
                       (abstention-flag Bool)] -> TrialResult
  :d "Constructs a single trial result record."
  (TrialResult
    :task-id task-id
    :policy-arm policy-arm
    :run-index run-index
    :outcome-correct outcome-correct
    :cost-usd cost-usd
    :latency-ms latency-ms
    :retries retries
    :aggregate-retrieval-tokens retrieval-tokens
    :aggregate-output-tokens output-tokens
    :cache-reads cache-reads
    :cache-writes cache-writes
    :cache-misses cache-misses
    :has-provider-data has-provider-data
    :constraints-satisfied constraints-satisfied
    :observation-recovered observation-recovered
    :confidence-score confidence-score
    :abstention-flag abstention-flag))

(df is-constraint-preserved? [(trial TrialResult)] -> Bool
  :d "Verifies whether constraints remained satisfied during compaction or execution."
  (.-constraints-satisfied trial))

(df is-observation-recoverable? [(trial TrialResult)] -> Bool
  :d "Verifies whether masked observations were recovered via source references."
  (.-observation-recovered trial))

(df calculate-pass-rate [(successful I64) (total I64)] -> Float
  :d "Calculates the fractional pass rate with zero check."
  (if (> total 0)
    (/ (* 1.0 successful) (* 1.0 total))
    0.0))

(df calculate-mean-cost [(total-cost Float) (runs I64)] -> Float
  :d "Calculates the average dollar cost per run."
  (if (> runs 0)
    (/ total-cost (* 1.0 runs))
    0.0))

(df make-policy-evaluation [(policy-arm Str)
                            (total-runs I64)
                            (successful-runs I64)
                            (total-cost Float)
                            (total-latency-ms I64)
                            (constraints-satisfied-count I64)
                            (observations-recovered-count I64)] -> PolicyEvaluation
  :d "Aggregates trial results into a policy evaluation summary."
  (let [(p-rate (calculate-pass-rate successful-runs total-runs))
        (m-cost (calculate-mean-cost total-cost total-runs))
        (m-lat (if (> total-runs 0) (/ total-latency-ms total-runs) 0))
        (c-rate (calculate-pass-rate constraints-satisfied-count total-runs))
        (o-rate (calculate-pass-rate observations-recovered-count total-runs))]
    (PolicyEvaluation
      :policy-arm policy-arm
      :total-runs total-runs
      :successful-runs successful-runs
      :pass-rate p-rate
      :mean-cost-usd m-cost
      :mean-latency-ms m-lat
      :constraint-satisfaction-rate c-rate
      :observation-recovery-rate o-rate)))

(df evaluate-trial-consistency [(t1 TrialResult) (t2 TrialResult)] -> Bool
  :d "Evaluates whether two runs of the same task and policy produced consistent outcomes."
  (and (= (.-task-id t1) (.-task-id t2))
       (and (= (.-policy-arm t1) (.-policy-arm t2))
            (= (.-outcome-correct t1) (.-outcome-correct t2)))))

(df run-tests [] -> Bool
  :d "Validates attention prosthesis measurement primitives and invariants."
  (let [(t1 (make-trial-result "Task-Eval-01" "observation-masking" 1 true 0.0042 320 0 1450 380 1200 0 250 true true true 0.95 false))
        (t2 (make-trial-result "Task-Eval-01" "observation-masking" 2 true 0.0039 310 0 1450 375 1200 0 250 true true true 0.94 false))
        (eval (make-policy-evaluation "observation-masking" 2 2 0.0081 630 2 2))]
    (assert (is-constraint-preserved? t1) "Constraints must be preserved in trial 1")
    (assert (is-observation-recoverable? t1) "Observations must be recoverable in trial 1")
    (assert (evaluate-trial-consistency t1 t2) "Repeated runs must exhibit outcome consistency")
    (assert (= (.-pass-rate eval) 1.0) "Pass rate must be 1.0 for 2/2 successful trials")
    (assert (> (.-mean-cost-usd eval) 0.0) "Mean cost must be greater than zero")
    true))
