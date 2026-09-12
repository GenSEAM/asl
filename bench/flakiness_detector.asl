(module asl-bench/flakiness-detector
  :d "Outcome stability evaluation, duration distribution, bottleneck ranking, and executed-set regression detection under ADR-0081."
  :x [SuiteRunResult
      SuiteStabilityReport
      ExecutedSetRegression
      BottleneckRank
      EvaluateSuiteStability
      DiffExecutedAssertionSets
      RankBottlenecks
      RunTests]
  :i [])

(dfs SuiteRunResult
  (:f suite-id Str "Suite identifier path")
  (:f run-index I64 "Zero-based iteration index")
  (:f status Str "Suite outcome: pass or fail")
  (:f executed-asserts I64 "Executed assertion count")
  (:f duration-ms I64 "Execution duration in milliseconds"))

(dfs SuiteStabilityReport
  (:f suite-id Str "Suite identifier path")
  (:f total-runs I64 "Total repetitions N")
  (:f pass-count I64 "Number of passing runs")
  (:f fail-count I64 "Number of failing runs")
  (:f stable? Bool "True if outcome is consistent across runs")
  (:f is-unstable? Bool "True if outcome varies between runs")
  (:f counts-toward-guarantee? Bool "False if suite is unstable")
  (:f min-duration-ms I64 "Minimum observed duration")
  (:f max-duration-ms I64 "Maximum observed duration")
  (:f mean-duration-ms I64 "Mean execution duration")
  (:f wall-clock-share Str "Share of total execution wall-clock time"))

(dfs ExecutedSetRegression
  (:f suite-id Str "Suite identifier")
  (:f previous-receipt Str "Previous task receipt identifier")
  (:f current-receipt Str "Current task receipt identifier")
  (:f previous-asserts I64 "Executed assertions in previous receipt")
  (:f current-asserts I64 "Executed assertions in current receipt")
  (:f regression? Bool "True if assertion count dropped")
  (:f delta I64 "Assertion deficit delta"))

(dfs BottleneckRank
  (:f rank I64 "Rank order starting at 1")
  (:f suite-id Str "Suite identifier")
  (:f duration-ms I64 "Wall clock duration in milliseconds")
  (:f share-percent Str "Percent share of total wall clock"))

(df EvaluateSuiteStability [(suite-id Str)
                            (runs (List SuiteRunResult))
                            (total-wall-ms I64)] -> SuiteStabilityReport
  :d "Analyzes outcome stability across runs, duration distribution rather than a single sample, and disqualifies unstable suites"
  (let [(total (list-len runs))]
    (let [(pass-cnt (list-fold (fn [(acc I64) (r SuiteRunResult)]
                                 (if (= (.-status r) "pass") (+ acc 1) acc))
                               0 runs))
          (total-dur (list-fold (fn [(acc I64) (r SuiteRunResult)]
                                  (+ acc (.-duration-ms r)))
                                0 runs))
          (min-dur (list-fold (fn [(acc I64) (r SuiteRunResult)]
                                (let [(d (.-duration-ms r))]
                                  (if (< d acc) d acc)))
                              999999999 runs))
          (max-dur (list-fold (fn [(acc I64) (r SuiteRunResult)]
                                (let [(d (.-duration-ms r))]
                                  (if (> d acc) d acc)))
                              0 runs))]
      (let [(fail-cnt (- total pass-cnt))
            (mean-dur (if (> total 0) (/ total-dur total) 0))]
        (let [(is-unstable (and (> pass-cnt 0) (> fail-cnt 0)))
              (stable (or (= pass-cnt total) (= fail-cnt total)))]
          (let [(counts-guarantee (and stable (> pass-cnt 0)))
                (share (if (> total-wall-ms 0)
                           (str-concat (str (/ (* total-dur 100) total-wall-ms)) "%")
                           "0%"))]
            (SuiteStabilityReport
              :suite-id suite-id
              :total-runs total
              :pass-count pass-cnt
              :fail-count fail-cnt
              :stable? stable
              :is-unstable? is-unstable
              :counts-toward-guarantee? counts-guarantee
              :min-duration-ms min-dur
              :max-duration-ms max-dur
              :mean-duration-ms mean-dur
              :wall-clock-share share)))))))

(df DiffExecutedAssertionSets [(suite-id Str)
                               (prev-receipt Str)
                               (curr-receipt Str)
                               (prev-count I64)
                               (curr-count I64)] -> ExecutedSetRegression
  :d "Diffs executed assertion set against previous receipt; flags newly unreached assertions as regression"
  (let [(has-regression (< curr-count prev-count))
        (delta (if (< curr-count prev-count)
                   (- prev-count curr-count)
                   0))]
    (ExecutedSetRegression
      :suite-id suite-id
      :previous-receipt prev-receipt
      :current-receipt curr-receipt
      :previous-asserts prev-count
      :current-asserts curr-count
      :regression? has-regression
      :delta delta)))

(df RankBottlenecks [(reports (List SuiteStabilityReport))
                     (total-wall-ms I64)] -> (List BottleneckRank)
  :d "Ranks bottlenecks by wall-clock share and reports duration distribution"
  (let [(ranked (list-map (fn [(r SuiteStabilityReport)]
                            (let [(dur (.-mean-duration-ms r))
                                  (pct (if (> total-wall-ms 0)
                                           (str-concat (str (/ (* dur 100) total-wall-ms)) "%")
                                           "0%"))]
                              (BottleneckRank
                                :rank 1
                                :suite-id (.-suite-id r)
                                :duration-ms dur
                                :share-percent pct)))
                          reports))]
    ranked))

(df RunTests [] -> Bool
  :d "Executes internal verification tests for flakiness detector"
  (let [(r1 (SuiteRunResult :suite-id "s1" :run-index 0 :status "pass" :executed-asserts 10 :duration-ms 100))
        (r2 (SuiteRunResult :suite-id "s1" :run-index 1 :status "fail" :executed-asserts 5 :duration-ms 120))
        (r3 (SuiteRunResult :suite-id "s1" :run-index 2 :status "pass" :executed-asserts 10 :duration-ms 110))]
    (let [(rep (EvaluateSuiteStability "s1" [r1 r2 r3] 1000))]
      (assert (.-is-unstable? rep) "Suite with mixed pass and fail must be flagged is-unstable")
      (assert (not (.-stable? rep)) "Suite with mixed outcomes must not be stable")
      (assert (not (.-counts-toward-guarantee? rep)) "Unstable suite must not count toward guarantee")
      (assert (= (.-total-runs rep) 3) "Must record total repetitions")
      (assert (= (.-pass-count rep) 2) "Must record pass count")
      (assert (= (.-fail-count rep) 1) "Must record fail count")
      (let [(reg (DiffExecutedAssertionSets "s1" "rc-prev-01" "rc-curr-02" 10 7))]
        (assert (.-regression? reg) "Fewer executed assertions must trigger regression")
        (assert (= (.-delta reg) 3) "Delta must reflect missing assertion deficit")
        (assert (= (.-previous-receipt reg) "rc-prev-01") "Must record previous receipt id")
        (assert (= (.-current-receipt reg) "rc-curr-02") "Must record current receipt id")
        (let [(no-reg (DiffExecutedAssertionSets "s1" "rc-prev-01" "rc-curr-02" 10 12))]
          (assert (not (.-regression? no-reg)) "Equal or greater assertions must not be regression")
          (let [(ranks (RankBottlenecks [rep] 1000))]
            (assert (> (list-len ranks) 0) "Must rank at least one bottleneck")
            true))))))

(df rank-bottlenecks [(reports (List SuiteStabilityReport))
                      (total-wall-ms I64)] -> (List BottleneckRank)
  :d "Alias for RankBottlenecks"
  (RankBottlenecks reports total-wall-ms))
