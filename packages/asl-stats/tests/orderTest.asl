(module asl-stats/tests/orderTest
  :x [runTests]
  :i [(asl-stats/order :a o)])

fn arr xs: (List Float64) -> F64Array
  (f64ArrayConcat (map (fn [(x Float64)] -> F64Array (f64ArrayGenerate 1 (fn [(i Int64)] -> Float64 x))) xs))

fn near? a: Float64 b: Float64 eps: Float64 -> Bool
  (< (abs (- a b)) eps)

fn rv r: (Result Float64 String) -> Float64
  (match r ((err e) -999.0) ((ok v) v))

fn errHas? r: (Result Float64 String) key: String -> Bool
  (match r ((err e) (stringContains? e key)) ((ok v) false))

fn pseudo n: Int64 md: Int64 -> F64Array
  (f64ArrayGenerate n (fn [(k Int64)] -> Float64 (int64ToFloat64 (mod (+ (* k 7919) (* (mod (* k k) 104729) 31)) md))))

fn ! ascending! a: F64Array i: Int64 -> Bool
  (if (>= (+ i 1) (f64ArrayLen a)) true
    (if (<= (f64ArrayGet a i) (f64ArrayGet a (+ i 1))) (ascending! a (+ i 1)) false))

fn ! selectAll! a: F64Array s: F64Array k: Int64 -> Bool
  (if (>= k (f64ArrayLen a)) true
    (if (= (rv (o/selectF64 a k)) (f64ArrayGet s k)) (selectAll! a s (+ k 1)) false))

fn ! runTests -> Bool
  (let [(ten (arr (list 10.0 1.0 9.0 2.0 8.0 3.0 7.0 4.0 6.0 5.0)))
        (nan (/ 0.0 0.0))
        (withNan (arr (list 3.0 nan 1.0 nan 2.0)))
        (sn (o/sortF64 withNan))
        (p (pseudo 1000 97))
        (sp (o/sortF64 p))
        (q (pseudo 300 5))
        (sq (o/sortF64 q))
        (same (f64ArrayGenerate 5000 (fn [(k Int64)] -> Float64 7.0)))]
    (do
      (assert (ascending! (o/sortF64 ten) 0) "sorted ten ascending")
      (assert (and (= (f64ArrayGet (o/sortF64 ten) 0) 1.0) (= (f64ArrayGet (o/sortF64 ten) 9) 10.0)) "sorted ten ends")
      (assert (= (f64ArrayGet ten 0) 10.0) "input array is not modified")
      (assert (and (= (f64ArrayLen sp) 1000) (ascending! sp 0) (= (f64ArraySum sp) (f64ArraySum p))) "1000 pseudo-random values: ascending, same length, same sum")
      (assert (and (= (f64ArrayLen (o/sortF64 (arr (list)))) 0) (= (f64ArrayLen (o/sortF64 (arr (list 4.0)))) 1)) "empty and single")
      (assert (and (= (f64ArrayGet sn 0) 1.0) (= (f64ArrayGet sn 1) 2.0) (= (f64ArrayGet sn 2) 3.0) (not (= (f64ArrayGet sn 3) (f64ArrayGet sn 3))) (not (= (f64ArrayGet sn 4) (f64ArrayGet sn 4)))) "NaN sorts last, finite values stay ascending")
      (assert (o/hasNanF64 withNan) "hasNan true")
      (assert (not (o/hasNanF64 ten)) "hasNan false")
      (assert (near? (rv (o/quantileF64 ten 0.25)) 3.25 1.0e-12) "type 7 q0.25 of 1..10 is 3.25")
      (assert (near? (rv (o/quantileF64 ten 0.5)) 5.5 1.0e-12) "median of 1..10 is 5.5")
      (assert (near? (rv (o/quantileF64 ten 0.9)) 9.1 1.0e-12) "type 7 q0.9 of 1..10 is 9.1")
      (assert (and (= (rv (o/quantileF64 ten 0.0)) 1.0) (= (rv (o/quantileF64 ten 1.0)) 10.0)) "q0 is the minimum, q1 the maximum")
      (assert (= (rv (o/quantileF64 (arr (list 4.0)) 0.7)) 4.0) "single value")
      (assert (near? (rv (o/quantileSortedF64 (arr (list 1.0 2.0 4.0)) 0.75)) 3.0 1.0e-12) "sorted q0.75 of 1,2,4 is 3")
      (assert (errHas? (o/quantileF64 withNan 0.5) "statsNaN") "NaN input is refused by quantile")
      (assert (errHas? (o/quantileF64 (arr (list)) 0.5) "statsEmpty") "empty input")
      (assert (errHas? (o/quantileF64 ten 1.5) "statsRange") "p above 1")
      (assert (errHas? (o/quantileF64 ten nan) "statsRange") "p NaN")
      (assert (errHas? (o/quantileF64 ten -0.1) "statsRange") "p below 0")
      (assert (selectAll! q sq 0) "select equals the sorted element for every k (300 values with duplicates)")
      (assert (selectAll! p sp 0) "select equals the sorted element for every k (1000 values)")
      (assert (= (rv (o/selectF64 same 2500)) 7.0) "select on 5000 equal values")
      (assert (errHas? (o/selectF64 ten 10) "statsRange") "k out of range")
      (assert (errHas? (o/selectF64 withNan 0) "statsNaN") "select refuses NaN")
      (assert (errHas? (o/selectF64 (arr (list)) 0) "statsEmpty") "select on empty")
      (assert (match (o/quantilesF64 ten (list 0.0 0.5 1.0)) ((err e) false) ((ok vs) (and (= (listLength vs) 3) (near? (optionOr (listGet vs 1) 0.0) 5.5 1.0e-12)))) "quantiles of a list")
      (assert (= (rv (o/quantileF64 (arr (list (- 0.0 (/ 1.0 0.0)) 1.0 (/ 1.0 0.0))) 0.0)) (- 0.0 (/ 1.0 0.0))) "infinite data at p = 0 returns -inf, not NaN")
      (assert (= (rv (o/quantileF64 (arr (list (- 0.0 (/ 1.0 0.0)) 1.0 (/ 1.0 0.0))) 1.0)) (/ 1.0 0.0)) "infinite data at p = 1 returns +inf")
      (assert (= (rv (o/quantileF64 (arr (list (- 0.0 (/ 1.0 0.0)) 1.0 (/ 1.0 0.0))) 0.5)) 1.0) "infinite data at p = 0.5 returns the middle value")
      true))
