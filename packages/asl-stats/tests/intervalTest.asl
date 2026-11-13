(module asl-stats/tests/intervalTest
  :x [runTests]
  :i [(asl-stats/special :a sp) (asl-stats/interval :a iv) (asl-stats/rng :a rg) (asl-stats/describe :a ds)])

fn near? a: Float64 b: Float64 eps: Float64 -> Bool
  (< (abs (- a b)) eps)

fn pr r: (Result (Pair Float64 Float64) String) -> (Pair Float64 Float64)
  (match r
    ((ok p) p)
    ((err e) (do (assert false e) (pair -1.0 -1.0))))

fn errP r: (Result (Pair Float64 Float64) String) -> String
  (match r
    ((ok _) "")
    ((err e) e))

fn nearPair? p: (Pair Float64 Float64) lo: Float64 hi: Float64 eps: Float64 -> Bool
  (and (near? (pairFirst p) lo eps) (near? (pairSecond p) hi eps))

fn testSpecial! -> Bool
  (do
    (assert (near? (sp/normalQuantile 0.975) 1.9599639845400532 1.0e-9) "normal quantile .975 is 1.959964")
    (assert (near? (sp/normalCdf 0.0) 0.5 1.0e-12) "normal cdf at 0 is .5")
    (assert (near? (sp/normalCdf 1.959963984540054) 0.975 1.0e-9) "normal cdf at 1.96 is .975")
    (assert (near? (sp/studentQuantile 0.975 9.0) 2.262157162798248 1.0e-7) "t quantile .975 with 9 df is 2.2621572")
    (assert (near? (sp/studentQuantile 0.975 4.0) 2.7764451051978014 1.0e-7) "t quantile .975 with 4 df is 2.7764451")
    (assert (near? (sp/lgamma 5.0) (log 24.0) 1.0e-12) "lgamma 5 is ln 24")
    (assert (near? (sp/lgamma 0.5) (* 0.5 (log 3.141592653589793)) 1.0e-12) "lgamma .5 is ln(pi)/2 by reflection")
    (assert (near? (sp/betaInc 0.5 2.0 2.0) 0.5 1.0e-12) "I_.5(2,2) is .5 by symmetry")
    (assert (near? (sp/betaInc 0.25 1.0 3.0) 0.578125 1.0e-12) "I_.25(1,3) = 1-(.75)^3")
    (assert (near? (sp/gammaIncP 1.0 1.0) (- 1.0 (exp -1.0)) 1.0e-12) "P(1,1) = 1 - 1/e")
    true)

fn testWilson! -> Bool
  (do
    (assert (nearPair? (pr (iv/wilson 8 10 0.95)) 0.49016247153664183 0.9433178485456247 1.0e-9) "Wilson 95% for 8/10 is 0.4902 to 0.9433")
    (assert (nearPair? (pr (iv/wilson 81 263 0.95)) 0.2552885 0.3662096 1.0e-6) "Newcombe 1998 81/263: 0.2553 to 0.3662")
    (assert (nearPair? (pr (iv/wilson 15 148 0.95)) 0.0623864 0.1604872 1.0e-6) "Newcombe 1998 15/148: 0.0624 to 0.1605")
    (assert (nearPair? (pr (iv/wilson 0 20 0.95)) 0.0 0.1611252 1.0e-6) "Newcombe 1998 0/20: 0 to 0.1611")
    (assert (nearPair? (pr (iv/wilson 1 29 0.95)) 0.0061132 0.1717552 1.0e-6) "Newcombe 1998 1/29: 0.0061 to 0.1718")
    (assert (nearPair? (pr (iv/wilson 10 10 0.95)) 0.7224672 1.0 1.0e-6) "Wilson 10/10 is 0.7225 to 1, not 1 to 1 as the normal approximation gives")
    (assert (stringStartsWith? (errP (iv/wilson 11 10 0.95)) "statsRange") "x above n is statsRange")
    (assert (stringStartsWith? (errP (iv/wilson -1 10 0.95)) "statsRange") "a negative x is statsRange")
    (assert (stringStartsWith? (errP (iv/wilson 0 0 0.95)) "statsRange") "n of 0 is statsRange")
    (assert (stringStartsWith? (errP (iv/wilson 5 10 1.0)) "statsRange") "conf 1 is statsRange")
    (assert (stringStartsWith? (errP (iv/wilson 5 10 0.0)) "statsRange") "conf 0 is statsRange")
    true)

fn testClopper! -> Bool
  (do
    (assert (nearPair? (pr (iv/clopperPearson 8 10 0.95)) 0.4439045376923586 0.9747892736731667 1.0e-9) "Clopper-Pearson 8/10 is 0.4439 to 0.9748 (binomial-sum oracle)")
    (assert (nearPair? (pr (iv/clopperPearson 0 10 0.95)) 0.0 0.3084971078187607 1.0e-9) "Clopper-Pearson 0/10 has lower bound 0")
    (assert (nearPair? (pr (iv/clopperPearson 10 10 0.95)) 0.6915028921812392 1.0 1.0e-9) "Clopper-Pearson 10/10 has upper bound 1")
    (assert (nearPair? (pr (iv/clopperPearson 3 20 0.95)) 0.032070937185463666 0.37892682654531396 1.0e-9) "Clopper-Pearson 3/20")
    (assert (< (pairFirst (pr (iv/clopperPearson 8 10 0.95))) (pairFirst (pr (iv/wilson 8 10 0.95)))) "the exact interval is wider than Wilson on the lower side")
    (assert (stringStartsWith? (errP (iv/clopperPearson 3 2 0.95)) "statsRange") "x above n is statsRange")
    true)

fn sample -> (List Float64)
  (list 2.1 2.5 1.9 3.2 2.8 2.4 2.9 3.0 2.2 2.6)

fn testMeanCi! -> Bool
  (do
    (assert (nearPair? (pr (iv/meanCi (sample) 0.95)) 2.259890938967332 2.8601090610326683 1.0e-6) "t interval of the 10 values is 2.2599 to 2.8601")
    (assert (stringStartsWith? (errP (iv/meanCi (list 1.0) 0.95)) "statsTooFew") "one value is statsTooFew")
    (assert (stringStartsWith? (errP (iv/meanCi (list) 0.95)) "statsEmpty") "no values is statsEmpty")
    (assert (stringStartsWith? (errP (iv/meanCi (sample) 1.5)) "statsRange") "conf 1.5 is statsRange")
    (assert (= (errP (iv/meanCi (list 1.0 (floatNan) 3.0) 0.95)) "statsRange: a value is NaN or infinite") "a NaN value is statsRange, not an interval of nan")
    (assert (= (errP (iv/meanCi (list 1.0 (floatInf) 3.0) 0.95)) "statsRange: a value is NaN or infinite") "an infinite value is statsRange")
    true)

fn meanOf xs: (List Float64) -> Float64
  (match (ds/mean xs)
    ((ok m) m)
    ((err _) -1.0))

fn ! testBoot! -> Bool
  (let [(xs (list 2.0 4.0 4.0 4.0 5.0 5.0 7.0 9.0))
        (r (rg/rngSeed 7))]
    (match (iv/bootstrapPercentile xs meanOf 1000 0.95 r)
      ((err e) (do (assert false e) false))
      ((ok b)
        (do
          (assert (near? b.lo 3.75 1.0e-12) "seed 7, 1000 resamples: lower bound 3.75 (python oracle with the same generator)")
          (assert (near? b.hi 6.378124999999997 1.0e-12) "seed 7, 1000 resamples: upper bound 6.378125")
          (assert (= b.estimate 5.0) "the estimate is the statistic on the original sample")
          (assert (= b.rng.s0 9033078346848060202) "the returned generator state is the oracle state after 8000 draws")
          (match (iv/bootstrapPercentile xs meanOf 1000 0.95 (rg/rngSeed 7))
            ((ok b2) (assert (and (= b2.lo b.lo) (and (= b2.hi b.hi) (= b2.rng.s3 b.rng.s3))) "the same seed reproduces the interval and the state bit for bit"))
            ((err e) (assert false e)))
          (match (iv/bootstrapPercentile xs meanOf 1000 0.95 (rg/rngSeed 8))
            ((ok b3) (assert (not (and (= b3.lo b.lo) (= b3.hi b.hi))) "a different seed gives a different interval"))
            ((err e) (assert false e)))
          (assert (stringStartsWith? (match (iv/bootstrapPercentile (list) meanOf 100 0.95 r) ((err e) e) ((ok _) "")) "statsEmpty") "empty input is statsEmpty")
          (assert (stringStartsWith? (match (iv/bootstrapPercentile (list 1.0) meanOf 100 0.95 r) ((err e) e) ((ok _) "")) "statsTooFew") "one value is statsTooFew")
          (assert (stringStartsWith? (match (iv/bootstrapPercentile xs meanOf 5 0.95 r) ((err e) e) ((ok _) "")) "statsRange") "fewer than 10 resamples is statsRange")
          (assert (stringStartsWith? (match (iv/bootstrapPercentile xs meanOf 100 2.0 r) ((err e) e) ((ok _) "")) "statsRange") "conf 2 is statsRange")
          true))))

fn sizeOf r: (Result Int64 String) -> Int64
  (match r
    ((ok n) n)
    ((err e) (do (assert false e) -1)))

fn testSize! -> Bool
  (do
    (assert (= (sizeOf (iv/twoProportionSampleSize 0.5 0.6 0.05 0.8)) 388) "50% vs 60% at alpha .05 power .8 needs 388 per group")
    (assert (= (sizeOf (iv/twoProportionSampleSize 0.2 0.3 0.05 0.8)) 294) "20% vs 30% needs 294 per group")
    (assert (= (sizeOf (iv/twoProportionSampleSize 0.3 0.2 0.05 0.8)) 294) "the order of the proportions does not matter")
    (assert (= (sizeOf (iv/twoProportionSampleSize 0.1 0.15 0.05 0.8)) 686) "10% vs 15% needs 686 per group")
    (assert (stringStartsWith? (match (iv/twoProportionSampleSize 0.5 0.5 0.05 0.8) ((err e) e) ((ok _) "")) "statsRange") "equal proportions are statsRange")
    (assert (stringStartsWith? (match (iv/twoProportionSampleSize 0.5 0.500000000001 0.05 0.8) ((err e) e) ((ok _) "")) "statsRange") "a size beyond Int64 is statsRange, never ok 0")
    (assert (stringStartsWith? (match (iv/twoProportionSampleSize (floatNan) 0.5 0.05 0.8) ((err e) e) ((ok _) "")) "statsRange") "a NaN proportion is statsRange")
    (assert (stringStartsWith? (match (iv/twoProportionSampleSize 0.5 0.6 (floatNan) 0.8) ((err e) e) ((ok _) "")) "statsRange") "a NaN alpha is statsRange")
    (assert (= (match (iv/twoProportionSampleSize 0.5 0.6 0.05 (floatNan)) ((err e) e) ((ok _) "")) "statsRange: an argument is NaN") "a NaN power is caught by the NaN guard itself, not a later range check")
    (assert (= (match (iv/twoProportionSampleSize (floatNan) 0.5 0.05 0.8) ((err e) e) ((ok _) "")) "statsRange: an argument is NaN") "a NaN proportion names the NaN guard")
    (assert (stringStartsWith? (match (iv/twoProportionSampleSize 0.0 0.5 0.05 0.8) ((err e) e) ((ok _) "")) "statsRange") "a proportion of 0 is statsRange")
    true)

fn ! runTests -> Bool
  (do
    (testSpecial!)
    (testWilson!)
    (testClopper!)
    (testMeanCi!)
    (testBoot!)
    (testSize!)
    true)
