(module asl-utils/tests/statsTest
  :x [runTests]
  :i [(asl-utils/stats :a st)])

fn close? a: Float64 b: Float64 -> Bool
  (let [(d (- a b))] (and (< d 0.000000001) (> d -0.000000001)))

fn testMean -> Bool
  (do (assert (= (st/mean (list 1.0 2.0 3.0 4.0)) (ok 2.5)) "mean of 1..4 is 2.5")
      (assert (= (st/mean (list 7.0)) (ok 7.0)) "mean of one value is that value")
      (assert (err? (st/mean (list))) "mean of an empty list is an err")
      true)

fn testMedian -> Bool
  (do (assert (= (st/median (list 3.0 1.0 2.0)) (ok 2.0)) "median of 3,1,2 is 2")
      (assert (= (st/median (list 4.0 1.0 3.0 2.0)) (ok 2.5)) "median of an even count averages the middle two")
      (assert (err? (st/median (list))) "median of an empty list is an err")
      true)

fn testVariance -> Bool
  (do (assert (= (st/variance (list 1.0 2.0 3.0 4.0)) (ok 1.25)) "population variance of 1..4 is 1.25")
      (assert (= (st/variance (list 5.0 5.0 5.0)) (ok 0.0)) "variance of equal values is 0")
      (assert (err? (st/variance (list))) "variance of an empty list is an err")
      (assert (match (st/stddev (list 1.0 2.0 3.0 4.0))
                ((ok s) (close? s 1.118033988749895))
                ((err _) false))
              "stddev of 1..4 is sqrt 1.25")
      (assert (err? (st/stddev (list))) "stddev of an empty list is an err")
      true)

fn testPercentile -> Bool
  (do (assert (= (st/percentile (list 1.0 2.0 3.0 4.0) 0.0) (ok 1.0)) "p0 is the minimum")
      (assert (= (st/percentile (list 1.0 2.0 3.0 4.0) 100.0) (ok 4.0)) "p100 is the maximum")
      (assert (= (st/percentile (list 1.0 2.0 3.0 4.0) 50.0) (ok 2.5)) "p50 is the median")
      (assert (= (st/percentile (list 1.0 2.0 3.0 4.0) 25.0) (ok 1.75)) "p25 interpolates between 1 and 2")
      (assert (err? (st/percentile (list) 50.0)) "percentile of an empty list is an err")
      (assert (err? (st/percentile (list 1.0 2.0) 101.0)) "p above 100 is an err")
      (assert (err? (st/percentile (list 1.0 2.0) -1.0)) "p below 0 is an err")
      true)

fn testHistogram -> Bool
  (do (assert (= (st/histogram (list 1.0 2.0 3.0 4.0) 2) (ok (list 2 2))) "two bins split 1..4 into 2 and 2")
      (assert (= (st/histogram (list 0.0 1.0 2.0 3.0 4.0) 5) (ok (list 1 1 1 1 1))) "five bins put each value in its own bin")
      (assert (= (st/histogram (list 5.0 5.0 5.0) 3) (ok (list 3 0 0))) "equal values all land in the first bin")
      (assert (err? (st/histogram (list) 4)) "histogram of an empty list is an err")
      (assert (err? (st/histogram (list 1.0) 0)) "zero bins is an err")
      true)

fn runTests -> Bool
  (and (testMean) (and (testMedian) (and (testVariance) (and (testPercentile) (testHistogram)))))
