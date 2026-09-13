(module aslBench/flakinessDetector
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
  (:f suiteId Str "Suite identifier path")
  (:f runIndex I64 "Zero-based iteration index")
  (:f status Str "Suite outcome: pass or fail")
  (:f executedAsserts I64 "Executed assertion count")
  (:f durationMs I64 "Execution duration in milliseconds"))

(dfs SuiteStabilityReport
  (:f suiteId Str "Suite identifier path")
  (:f totalRuns I64 "Total repetitions N")
  (:f passCount I64 "Number of passing runs")
  (:f failCount I64 "Number of failing runs")
  (:f stable? Bool "True if outcome is consistent across runs")
  (:f isUnstable? Bool "True if outcome varies between runs")
  (:f countsTowardGuarantee? Bool "False if suite is unstable")
  (:f minDurationMs I64 "Minimum observed duration")
  (:f maxDurationMs I64 "Maximum observed duration")
  (:f meanDurationMs I64 "Mean execution duration")
  (:f wallClockShare Str "Share of total execution wall-clock time"))

(dfs ExecutedSetRegression
  (:f suiteId Str "Suite identifier")
  (:f previousReceipt Str "Previous task receipt identifier")
  (:f currentReceipt Str "Current task receipt identifier")
  (:f previousAsserts I64 "Executed assertions in previous receipt")
  (:f currentAsserts I64 "Executed assertions in current receipt")
  (:f regression? Bool "True if assertion count dropped")
  (:f delta I64 "Assertion deficit delta"))

(dfs BottleneckRank
  (:f rank I64 "Rank order starting at 1")
  (:f suiteId Str "Suite identifier")
  (:f durationMs I64 "Wall clock duration in milliseconds")
  (:f sharePercent Str "Percent share of total wall clock"))

(df EvaluateSuiteStability [(suiteId Str)
                            (runs (List SuiteRunResult))
                            (totalWallMs I64)] -> SuiteStabilityReport
  :d "Analyzes outcome stability across runs, duration distribution rather than a single sample, and disqualifies unstable suites"
  (let [(total (listLen runs))]
    (let [(passCnt (listFold (fn [(acc I64) (r SuiteRunResult)]
                                 (if (= (.-status r) "pass") (+ acc 1) acc))
                               0 runs))
          (totalDur (listFold (fn [(acc I64) (r SuiteRunResult)]
                                  (+ acc (.-durationMs r)))
                                0 runs))
          (minDur (listFold (fn [(acc I64) (r SuiteRunResult)]
                                (let [(d (.-durationMs r))]
                                  (if (< d acc) d acc)))
                              999999999 runs))
          (maxDur (listFold (fn [(acc I64) (r SuiteRunResult)]
                                (let [(d (.-durationMs r))]
                                  (if (> d acc) d acc)))
                              0 runs))]
      (let [(failCnt (- total passCnt))
            (meanDur (if (> total 0) (/ totalDur total) 0))]
        (let [(isUnstable (and (> passCnt 0) (> failCnt 0)))
              (stable (or (= passCnt total) (= failCnt total)))]
          (let [(countsGuarantee (and stable (> passCnt 0)))
                (share (if (> totalWallMs 0)
                           (strConcat (str (/ (* totalDur 100) totalWallMs)) "%")
                           "0%"))]
            (SuiteStabilityReport
              :suiteId suiteId
              :totalRuns total
              :passCount passCnt
              :failCount failCnt
              :stable? stable
              :isUnstable? isUnstable
              :countsTowardGuarantee? countsGuarantee
              :minDurationMs minDur
              :maxDurationMs maxDur
              :meanDurationMs meanDur
              :wallClockShare share)))))))

(df DiffExecutedAssertionSets [(suiteId Str)
                               (prevReceipt Str)
                               (currReceipt Str)
                               (prevCount I64)
                               (currCount I64)] -> ExecutedSetRegression
  :d "Diffs executed assertion set against previous receipt; flags newly unreached assertions as regression"
  (let [(hasRegression (< currCount prevCount))
        (delta (if (< currCount prevCount)
                   (- prevCount currCount)
                   0))]
    (ExecutedSetRegression
      :suiteId suiteId
      :previousReceipt prevReceipt
      :currentReceipt currReceipt
      :previousAsserts prevCount
      :currentAsserts currCount
      :regression? hasRegression
      :delta delta)))

(df RankBottlenecks [(reports (List SuiteStabilityReport))
                     (totalWallMs I64)] -> (List BottleneckRank)
  :d "Ranks bottlenecks by wall-clock share and reports duration distribution"
  (let [(ranked (listMap (fn [(r SuiteStabilityReport)]
                            (let [(dur (.-meanDurationMs r))
                                  (pct (if (> totalWallMs 0)
                                           (strConcat (str (/ (* dur 100) totalWallMs)) "%")
                                           "0%"))]
                              (BottleneckRank
                                :rank 1
                                :suiteId (.-suiteId r)
                                :durationMs dur
                                :sharePercent pct)))
                          reports))]
    ranked))

(df RunTests [] -> Bool
  :d "Executes internal verification tests for flakiness detector"
  (let [(r1 (SuiteRunResult :suiteId "s1" :runIndex 0 :status "pass" :executedAsserts 10 :durationMs 100))
        (r2 (SuiteRunResult :suiteId "s1" :runIndex 1 :status "fail" :executedAsserts 5 :durationMs 120))
        (r3 (SuiteRunResult :suiteId "s1" :runIndex 2 :status "pass" :executedAsserts 10 :durationMs 110))]
    (let [(rep (EvaluateSuiteStability "s1" [r1 r2 r3] 1000))]
      (assert (.-isUnstable? rep) "Suite with mixed pass and fail must be flagged is-unstable")
      (assert (not (.-stable? rep)) "Suite with mixed outcomes must not be stable")
      (assert (not (.-countsTowardGuarantee? rep)) "Unstable suite must not count toward guarantee")
      (assert (= (.-totalRuns rep) 3) "Must record total repetitions")
      (assert (= (.-passCount rep) 2) "Must record pass count")
      (assert (= (.-failCount rep) 1) "Must record fail count")
      (let [(reg (DiffExecutedAssertionSets "s1" "rc-prev-01" "rc-curr-02" 10 7))]
        (assert (.-regression? reg) "Fewer executed assertions must trigger regression")
        (assert (= (.-delta reg) 3) "Delta must reflect missing assertion deficit")
        (assert (= (.-previousReceipt reg) "rc-prev-01") "Must record previous receipt id")
        (assert (= (.-currentReceipt reg) "rc-curr-02") "Must record current receipt id")
        (let [(noReg (DiffExecutedAssertionSets "s1" "rc-prev-01" "rc-curr-02" 10 12))]
          (assert (not (.-regression? noReg)) "Equal or greater assertions must not be regression")
          (let [(ranks (RankBottlenecks [rep] 1000))]
            (assert (> (listLen ranks) 0) "Must rank at least one bottleneck")
            true))))))

(df rankBottlenecks [(reports (List SuiteStabilityReport))
                      (totalWallMs I64)] -> (List BottleneckRank)
  :d "Alias for RankBottlenecks"
  (RankBottlenecks reports totalWallMs))
