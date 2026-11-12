(module asl-stats/tests/describeTest
  :x [runTests]
  :i [(asl-stats/describe :a ds) (asl-stats/agree :a ag)])

fn near? a: Float64 b: Float64 eps: Float64 -> Bool
  (< (abs (- a b)) eps)

fn val r: (Result Float64 String) -> Float64
  (match r
    ((ok v) v)
    ((err e) (do (assert false e) -999.0)))

fn errOf r: (Result Float64 String) -> String
  (match r
    ((ok _) "")
    ((err e) e))

fn data -> (List Float64)
  (list 2.0 4.0 4.0 4.0 5.0 5.0 7.0 9.0)

fn testDescribe! -> Bool
  (do
    (assert (= (val (ds/mean (data))) 5.0) "mean of the textbook vector is 5")
    (assert (= (val (ds/popVariance (data))) 4.0) "population variance is 4")
    (assert (near? (val (ds/variance (data))) 4.571428571428571 1.0e-12) "sample variance is 32/7")
    (assert (near? (val (ds/stddev (data))) 2.138089935299395 1.0e-12) "sample standard deviation is 2.1380899")
    (assert (= (val (ds/median (data))) 4.5) "median of an even count is the mean of the middle two")
    (assert (= (val (ds/median (list 9.0 1.0 5.0))) 5.0) "median of an unsorted odd list")
    (assert (= (val (ds/percentile (data) 25.0)) 4.0) "p25 by linear interpolation (type 7) is 4")
    (assert (near? (val (ds/percentile (data) 90.0)) 7.6 1.0e-12) "p90 interpolates between 7 and 9")
    (assert (= (val (ds/percentile (data) 0.0)) 2.0) "p0 is the minimum")
    (assert (= (val (ds/percentile (data) 100.0)) 9.0) "p100 is the maximum")
    (assert (= (val (ds/mad (data))) 0.5) "median absolute deviation is 0.5")
    (assert (near? (val (ds/robustZ 9.0 (data))) 6.070407751764735 1.0e-9) "robust z of 9 is 4.5 / (1.4826 * 0.5)")
    (assert (= (val (ds/percentileOf (data) 5.0)) 62.5) "percentile rank of 5 counts half the ties: (4 below + 1) / 8")
    (assert (= (val (ds/percentileOf (data) 100.0)) 100.0) "everything below gives 100")
    (assert (= (ds/sumKahan (list 1.0e16 1.0 -1.0e16)) 1.0) "compensated sum keeps the 1.0 a naive sum loses")
    true)

fn testEffect! -> Bool
  (let [(a (list 1.0 2.0 3.0 4.0 5.0))
        (b (list 3.0 4.0 5.0 6.0 7.0))]
    (do
      (assert (near? (val (ds/cohenD a b)) -1.2649110640673518 1.0e-12) "Cohen d of two shifted vectors is -2/sqrt(2.5)")
      (assert (near? (val (ds/hedgesG a b)) -1.1425003159318015 1.0e-12) "Hedges g applies 1 - 3/(4n-9)")
      (assert (stringStartsWith? (errOf (ds/cohenD (list 1.0 1.0) (list 2.0 2.0))) "statsConstant") "a zero pooled spread is statsConstant")
      true))

fn testErrors! -> Bool
  (let [(none (list))
        (one (list 3.0))]
    (do
      (assert (stringStartsWith? (errOf (ds/mean none)) "statsEmpty") "mean of empty is statsEmpty")
      (assert (stringStartsWith? (errOf (ds/median none)) "statsEmpty") "median of empty is statsEmpty")
      (assert (stringStartsWith? (errOf (ds/percentile none 50.0)) "statsEmpty") "percentile of empty is statsEmpty")
      (assert (stringStartsWith? (errOf (ds/variance none)) "statsEmpty") "variance of empty is statsEmpty")
      (assert (stringStartsWith? (errOf (ds/variance one)) "statsTooFew") "sample variance of one value is statsTooFew")
      (assert (stringStartsWith? (errOf (ds/stddev one)) "statsTooFew") "stddev of one value is statsTooFew")
      (assert (= (val (ds/mean one)) 3.0) "mean of one value is that value")
      (assert (= (val (ds/popVariance one)) 0.0) "population variance of one value is 0")
      (assert (= (val (ds/median one)) 3.0) "median of one value is that value")
      (assert (stringStartsWith? (errOf (ds/percentile (data) 101.0)) "statsRange") "percentile above 100 is statsRange")
      (assert (stringStartsWith? (errOf (ds/percentile (data) -1.0)) "statsRange") "a negative percentile is statsRange")
      (assert (stringStartsWith? (errOf (ds/robustZ 1.0 (list 2.0 2.0 2.0))) "statsConstant") "robust z with zero MAD is statsConstant")
      (assert (stringStartsWith? (errOf (ds/cohenD one (list 1.0 2.0))) "statsTooFew") "Cohen d with a one-value group is statsTooFew")
      true))

fn rk xs: (List Float64) -> (List Float64)
  (match (ag/ranks xs)
    ((ok r) r)
    ((err e) (do (assert false e) (list))))

fn testNonFinite! -> Bool
  (let [(nan (floatNan))
        (inf (floatInf))]
    (do
      (assert (stringStartsWith? (errOf (ag/spearman (list 1.0 nan 3.0) (list 1.0 2.0 3.0))) "statsRange") "a NaN in x is statsRange and the run terminates")
      (assert (stringStartsWith? (errOf (ag/spearman (list 1.0 2.0 3.0) (list nan nan nan))) "statsRange") "all-NaN y is statsRange")
      (assert (stringStartsWith? (errOf (ag/spearman (list 1.0 inf 3.0) (list 1.0 2.0 3.0))) "statsRange") "an infinity is statsRange")
      (assert (stringStartsWith? (errOf (ag/pearson (list 1.0 nan 3.0) (list 1.0 2.0 3.0))) "statsRange") "pearson refuses NaN too")
      (assert (stringStartsWith? (match (ag/ranks (list nan 1.0)) ((err e) e) ((ok _) "")) "statsRange") "ranks refuses NaN")
      (assert (= (ds/sumKahan (list 1.0 inf 2.0)) inf) "a compensated sum with an infinity is that infinity, not NaN")
      (assert (isNan? (ds/sumKahan (list inf (- 0.0 inf)))) "inf minus inf stays NaN")
      (assert (stringStartsWith? (errOf (ds/percentile (data) nan)) "statsRange") "a NaN percentile is statsRange")
      (assert (and (ds/finiteValue? 1.0) (and (not (ds/finiteValue? nan)) (not (ds/finiteValue? (- 0.0 inf))))) "finiteValue? is false for NaN and either infinity")
      (assert (= (errOf (ds/mean (list 1.0 nan 3.0))) "statsRange: a value is NaN or infinite") "a NaN in mean is statsRange, not ok nan")
      (assert (= (errOf (ds/mean (list 1.0 inf))) "statsRange: a value is NaN or infinite") "an infinity in mean is statsRange")
      (assert (stringStartsWith? (errOf (ds/variance (list 1.0 nan 3.0))) "statsRange") "variance inherits the mean guard")
      (assert (= (ds/mean (list 1.0e308 1.0e308)) (ok 1.0e308)) "the mean of two 1e308 is 1e308, not inf: the sum overflows, the scaled sum does not")
      (assert (= (ds/mean (list 1.0e308 1.0e308 -1.0e308)) (ok (/ 1.0e308 3.0))) "an overflowing sum with a negative term still gives the scaled mean")
      (assert (= (ds/mean (list 1.0 2.0 4.0)) (ok (/ 7.0 3.0))) "an ordinary mean is the plain sum over n")
      (assert (= (ds/variance (list 1.0e308 1.0e308)) (ok 0.0)) "the variance of two 1e308 is 0: the mean is 1e308, so no deviation overflows")
      (assert (= (ds/popVariance (list 1.0e308 1.0e308)) (ok 0.0)) "the population variance of two 1e308 is 0")
      (assert (= (errOf (ds/variance (list 1.0e308 -1.0e308))) "statsRange: the variance overflows Float64") "1e308 and -1e308 have a variance past Float64 max: statsRange, not ok inf")
      (assert (= (errOf (ds/popVariance (list 1.0e308 -1.0e308))) "statsRange: the variance overflows Float64") "popVariance refuses the same overflow")
      (assert (let [(xs (map (fn [(i Int64)] -> Float64 (if (= (mod i 2) 0) 2.0e153 -2.0e153)) (range 0 100)))] (near? (/ (val (ds/variance xs)) (* 4.0e306 (/ 100.0 99.0))) 1.0 1.0e-12)) "100 values of +-2e153: the squares sum past max (4e308), the variance 4.04e306 is not, and comes back from the scaled sum")
      (assert (let [(src (resultOr (fileReadString "asl/packages/asl-stats/src/agree.asl") ""))] (and (stringContains? src "ds/finiteValue?") (not (stringContains? src "fn finite?")))) "agree.asl uses describe finiteValue? and keeps no finite check of its own")
      true))

fn testRank! -> Bool
  (do
    (assert (= (rk (list 5.0 6.0 7.0 8.0 7.0)) (list 1.0 2.0 3.5 5.0 3.5)) "ties share the average rank")
    (assert (= (rk (list 10.0 20.0 20.0 30.0 40.0 40.0 40.0)) (list 1.0 2.5 2.5 4.0 6.0 6.0 6.0)) "a three-way tie takes rank 6")
    (assert (near? (val (ag/spearman (list 1.0 2.0 3.0 4.0 5.0) (list 5.0 6.0 7.0 8.0 7.0))) 0.8207826816681233 1.0e-12) "Spearman with a tie in y is 0.82078268 (average ranks)")
    (assert (near? (val (ag/spearman (list 10.0 20.0 20.0 30.0 40.0 40.0 40.0) (list 1.0 3.0 2.0 5.0 4.0 4.0 6.0))) 0.8118990304530631 1.0e-12) "Spearman with ties in both series")
    (assert (= (val (ag/spearman (list 1.0 2.0 3.0 4.0) (list 1.0 8.0 27.0 64.0))) 1.0) "a monotone nonlinear pair is exactly 1")
    (assert (= (val (ag/spearman (list 1.0 2.0 3.0) (list 9.0 4.0 1.0))) -1.0) "a reversed pair is exactly -1")
    (assert (stringStartsWith? (errOf (ag/spearman (list 1.0 1.0 1.0) (list 1.0 2.0 3.0))) "statsConstant") "a constant series is statsConstant")
    (assert (stringStartsWith? (errOf (ag/spearman (list) (list))) "statsEmpty") "empty spearman is statsEmpty")
    (assert (stringStartsWith? (errOf (ag/spearman (list 1.0) (list 2.0))) "statsTooFew") "one pair is statsTooFew")
    (assert (stringStartsWith? (errOf (ag/spearman (list 1.0 2.0) (list 2.0))) "statsRange") "unequal lengths are statsRange")
    true)

fn testKappa! -> Bool
  (let [(t3 (list (list 11 3 1) (list 2 9 4) (list 1 2 12)))]
    (do
      (assert (near? (val (ag/cohenKappa (list (list 20 5) (list 10 15)))) 0.4 1.0e-12) "kappa of the 2x2 table 20 5 10 15 is 0.4 (po .7, pe .5)")
      (assert (near? (val (ag/cohenKappa (list (list 45 15) (list 25 15)))) 0.13043478260869554 1.0e-12) "kappa of 45 15 25 15 is 0.1304 (po .6, pe .54)")
      (assert (near? (val (ag/cohenKappa t3)) 0.5666666666666667 1.0e-12) "unweighted 3x3 kappa")
      (assert (near? (val (ag/weightedKappa t3 "linear")) 0.6280991735537191 1.0e-12) "linear weighted 3x3 kappa")
      (assert (near? (val (ag/weightedKappa t3 "quadratic")) 0.6885245901639345 1.0e-12) "quadratic weighted 3x3 kappa")
      (assert (= (val (ag/cohenKappa (list (list 10 0) (list 0 10)))) 1.0) "perfect agreement is 1")
      (assert (stringStartsWith? (errOf (ag/cohenKappa (list (list 5 0) (list 0 0)))) "statsConstant") "chance agreement 1 is statsConstant")
      (assert (stringStartsWith? (errOf (ag/cohenKappa (list (list 1 2 3) (list 4 5 6)))) "statsRange") "a non-square table is statsRange")
      (assert (stringStartsWith? (errOf (ag/cohenKappa (list (list 1 -2) (list 3 4)))) "statsRange") "a negative count is statsRange")
      (assert (stringStartsWith? (errOf (ag/cohenKappa (list (list 0 0) (list 0 0)))) "statsEmpty") "an all-zero table is statsEmpty")
      (assert (stringStartsWith? (errOf (ag/weightedKappa t3 "cubic")) "statsRange") "an unknown weighting is statsRange")
      true))

fn ! runTests -> Bool
  (do
    (testDescribe!)
    (testEffect!)
    (testErrors!)
    (testRank!)
    (testNonFinite!)
    (testKappa!)
    true)
