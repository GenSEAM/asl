(module asl-linalg/tests/denseTest
  :x [runTests]
  :i [(asl-linalg/dense :a d)])

fn arr xs: (List Float64) -> F64Array
  (f64ArrayConcat (map (fn [(x Float64)] -> F64Array (f64ArrayGenerate 1 (fn [(i Int64)] -> Float64 x))) xs))

fn errHas? r: (Result F64Array String) key: String -> Bool
  (match r ((err e) (stringContains? e key)) ((ok v) false))

fn okArr r: (Result F64Array String) -> F64Array
  (match r ((err e) (arr (list))) ((ok v) v))

fn ! runTests -> Bool
  (let [(a (arr (list 1.0 2.0 3.0 4.0 5.0 6.0)))
        (b (d/toBuf a))
        (nan (/ 0.0 0.0))
        (sym (d/toBuf (arr (list 1.0 2.0 2.0 5.0))))
        (asym (d/toBuf (arr (list 1.0 2.0 2.5 5.0))))]
    (do
      (assert (= (d/getAt! b 3 1 2) 6.0) "getAt! row 1 col 2 of a 2x3 buffer")
      (assert (= (do (d/setAt! b 3 0 1 9.0) (d/getAt! b 3 0 1)) 9.0) "setAt! then getAt!")
      (assert (= (f64ArrayGet (d/fromBuf b 6) 1) 9.0) "fromBuf sees the write")
      (assert (= (f64ArrayGet a 1) 2.0) "toBuf copies, the source array is unchanged")
      (assert (and (d/allFinite a) (not (d/allFinite (arr (list 1.0 nan)))) (not (d/allFinite (arr (list 1.0 (/ 1.0e308 1.0e-10))))) (d/allFinite (arr (list)))) "allFinite: finite, NaN, overflow to infinity, empty")
      (assert (= (f64ArrayGet (d/identity 3) 4) 1.0) "identity diagonal")
      (assert (= (f64ArrayGet (d/identity 3) 5) 0.0) "identity off diagonal")
      (assert (= (f64ArrayLen (d/identity 3)) 9) "identity length")
      (assert (= (f64ArrayGet (okArr (d/transpose 2 3 a)) 1) 4.0) "transpose of 2x3: element 1 is a[1][0] = 4")
      (assert (= (f64ArrayGet (okArr (d/transpose 2 3 a)) 5) 6.0) "transpose last element")
      (assert (errHas? (d/transpose 3 3 a) "linalgShape") "transpose length mismatch")
      (assert (errHas? (d/transpose -1 6 a) "linalgShape") "transpose negative dimension")
      (assert (= (f64ArrayGet (okArr (d/matVec 2 3 a (arr (list 1.0 0.0 -1.0)))) 0) -2.0) "matVec row 0: 1 - 3")
      (assert (= (f64ArrayGet (okArr (d/matVec 2 3 a (arr (list 1.0 0.0 -1.0)))) 1) -2.0) "matVec row 1: 4 - 6")
      (assert (errHas? (d/matVec 2 3 a (arr (list 1.0 2.0))) "linalgShape") "matVec vector length mismatch")
      (assert (errHas? (d/matVec 2 2 a (arr (list 1.0 2.0))) "linalgShape") "matVec matrix length mismatch")
      (assert (not (d/asymmetric! sym 2 0 0)) "symmetric 2x2")
      (assert (d/asymmetric! asym 2 0 0) "asymmetric 2x2")
      (assert (and (= (d/pow2Exponent 1.0 0) 0) (= (d/pow2Exponent 7.9 0) 2) (= (d/pow2Exponent 0.3 0) -2) (= (d/pow2Exponent 0.0 0) 0) (= (d/pow2Exponent 1.0e154 0) 511) (= (d/pow2Exponent 1.0e-170 0) -565)) "pow2Exponent brings the magnitude into [1,2)")
      (assert (and (= (d/mul2 3.0 2) 12.0) (= (d/mul2 3.0 -1) 1.5) (= (d/mul2 1.0 -1000) (/ 1.0 (d/mul2 1.0 1000))) (= (d/mul2 (d/mul2 1.0e-300 1100) -1100) 1.0e-300)) "mul2 is exact and survives exponents past the double range of 2^e itself")
      (assert (= (f64ArrayGet (d/scaleArray (arr (list 1.0 2.0)) 3) 1) 16.0) "scaleArray multiplies by 2^e")
      (assert (= (d/maxAbs (arr (list 1.0 -7.5 3.0))) 7.5) "maxAbs takes the absolute value")
      (assert (= (d/maxAbs (arr (list))) 0.0) "maxAbs of empty is 0")
      true))
