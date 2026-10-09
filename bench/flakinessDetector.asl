(module aslBench/flakinessDetector :x [SuiteRunResult SuiteStabilityReport ExecutedSetRegression BottleneckRank EvaluateSuiteStability DiffExecutedAssertionSets RankBottlenecks RunTests] :i [])

(schema SuiteRunResult (:f suiteId Str) (:f runIndex I64) (:f status Str) (:f executedAsserts I64) (:f durationMs I64))

(schema SuiteStabilityReport (:f suiteId Str) (:f totalRuns I64) (:f passCount I64) (:f failCount I64) (:f stable? Bool) (:f isUnstable? Bool) (:f countsTowardGuarantee? Bool) (:f minDurationMs I64) (:f maxDurationMs I64) (:f meanDurationMs I64) (:f wallClockShare Str))

(schema ExecutedSetRegression (:f suiteId Str) (:f previousReceipt Str) (:f currentReceipt Str) (:f previousAsserts I64) (:f currentAsserts I64) (:f regression? Bool) (:f delta I64))

(schema BottleneckRank (:f rank I64) (:f suiteId Str) (:f durationMs I64) (:f sharePercent Str))

fn EvaluateSuiteStability suiteId: Str runs: (List SuiteRunResult) totalWallMs: I64 -> SuiteStabilityReport
  (let [(total (listLength runs))] (let [(passCnt (fold (fn [(acc I64) (r SuiteRunResult)] (if (= r.status "pass") (+ acc 1) acc)) 0 runs)) (totalDur (fold (fn [(acc I64) (r SuiteRunResult)] (+ acc r.durationMs)) 0 runs)) (minDur (fold (fn [(acc I64) (r SuiteRunResult)] (let [(d r.durationMs)] (if (< d acc) d acc))) 999999999 runs)) (maxDur (fold (fn [(acc I64) (r SuiteRunResult)] (let [(d r.durationMs)] (if (> d acc) d acc))) 0 runs))] (let [(failCnt (- total passCnt)) (meanDur (if (> total 0) (/ totalDur total) 0))] (let [(isUnstable (and (> passCnt 0) (> failCnt 0))) (stable (or (= passCnt total) (= failCnt total)))] (let [(countsGuarantee (and stable (> passCnt 0))) (share (if (> totalWallMs 0) (stringConcat (str (/ (* totalDur 100) totalWallMs)) "%") "0%"))] (SuiteStabilityReport :suiteId suiteId :totalRuns total :passCount passCnt :failCount failCnt :stable? stable :isUnstable? isUnstable :countsTowardGuarantee? countsGuarantee :minDurationMs minDur :maxDurationMs maxDur :meanDurationMs meanDur :wallClockShare share))))))

fn DiffExecutedAssertionSets suiteId: Str prevReceipt: Str currReceipt: Str prevCount: I64 currCount: I64 -> ExecutedSetRegression
  (let [(hasRegression (< currCount prevCount)) (delta (if (< currCount prevCount) (- prevCount currCount) 0))] (ExecutedSetRegression :suiteId suiteId :previousReceipt prevReceipt :currentReceipt currReceipt :previousAsserts prevCount :currentAsserts currCount :regression? hasRegression :delta delta))

fn RankBottlenecks reports: (List SuiteStabilityReport) totalWallMs: I64 -> (List BottleneckRank)
  (let [(ranked (map (fn [(r SuiteStabilityReport)] (let [(dur r.meanDurationMs) (pct (if (> totalWallMs 0) (stringConcat (str (/ (* dur 100) totalWallMs)) "%") "0%"))] (BottleneckRank :rank 1 :suiteId r.suiteId :durationMs dur :sharePercent pct))) reports))] ranked)

fn RunTests -> Bool
  (let [(r1 (SuiteRunResult :suiteId "s1" :runIndex 0 :status "pass" :executedAsserts 10 :durationMs 100)) (r2 (SuiteRunResult :suiteId "s1" :runIndex 1 :status "fail" :executedAsserts 5 :durationMs 120)) (r3 (SuiteRunResult :suiteId "s1" :runIndex 2 :status "pass" :executedAsserts 10 :durationMs 110))] (let [(rep (EvaluateSuiteStability "s1" [r1 r2 r3] 1000))] (assert rep.isUnstable? "Suite with mixed pass and fail must be flagged is-unstable") (assert (not rep.stable?) "Suite with mixed outcomes must not be stable") (assert (not rep.countsTowardGuarantee?) "Unstable suite must not count toward guarantee") (assert (= rep.totalRuns 3) "Must record total repetitions") (assert (= rep.passCount 2) "Must record pass count") (assert (= rep.failCount 1) "Must record fail count") (let [(reg (DiffExecutedAssertionSets "s1" "rc-prev-01" "rc-curr-02" 10 7))] (assert reg.regression? "Fewer executed assertions must trigger regression") (assert (= reg.delta 3) "Delta must reflect missing assertion deficit") (assert (= reg.previousReceipt "rc-prev-01") "Must record previous receipt id") (assert (= reg.currentReceipt "rc-curr-02") "Must record current receipt id") (let [(noReg (DiffExecutedAssertionSets "s1" "rc-prev-01" "rc-curr-02" 10 12))] (assert (not noReg.regression?) "Equal or greater assertions must not be regression") (let [(ranks (RankBottlenecks [rep] 1000))] (assert (> (listLength ranks) 0) "Must rank at least one bottleneck") true)))))

fn rankBottlenecks reports: (List SuiteStabilityReport) totalWallMs: I64 -> (List BottleneckRank)
  (RankBottlenecks reports totalWallMs)
