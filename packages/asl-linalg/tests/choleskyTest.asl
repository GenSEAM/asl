(module asl-linalg/tests/choleskyTest
  :x [runTests]
  :i [(asl-linalg/cholesky :a ch) (asl-linalg/dense :a d)])

fn arr xs: (List Float64) -> F64Array
  (f64ArrayConcat (map (fn [(x Float64)] -> F64Array (f64ArrayGenerate 1 (fn [(i Int64)] -> Float64 x))) xs))

fn near? a: Float64 b: Float64 eps: Float64 -> Bool
  (< (abs (- a b)) eps)

fn ! maxDiff! a: F64Array b: F64Array i: Int64 acc: Float64 -> Float64
  (if (>= i (f64ArrayLen a)) acc
    (maxDiff! a b (+ i 1) (max acc (abs (- (f64ArrayGet a i) (f64ArrayGet b i))))))

fn isErr? r: (Result F64Array String) key: String -> Bool
  (match r
    ((err e) (stringContains? e key))
    ((ok v) false))

fn unwrap r: (Result F64Array String) -> F64Array
  (match r
    ((err e) (f64ArrayGenerate 0 (fn [(i Int64)] -> Float64 0.0)))
    ((ok v) v))

fn hilbert n: Int64 -> F64Array
  (f64ArrayGenerate (* n n) (fn [(k Int64)] -> Float64 (/ 1.0 (int64ToFloat64 (+ (+ (/ k n) (% k n)) 1)))))

fn ! rcondOf n: Int64 a: F64Array -> Float64
  (match (ch/choleskyFactor n a)
    ((err e) -1.0)
    ((ok l) (match (ch/choleskyRcond n a l) ((err e) -2.0) ((ok r) r))))

fn ! runTests -> Bool
  (let [(a (arr (list 4.0 12.0 -16.0 12.0 37.0 -43.0 -16.0 -43.0 98.0)))
        (lr (ch/choleskyFactor 3 a))
        (l (unwrap lr))
        (lt (unwrap (d/transpose 3 3 l)))
        (rec (gemm 3 3 3 l lt))
        (b (arr (list 1.0 2.0 3.0)))
        (x (unwrap (ch/choleskySolveSpd 3 a b)))
        (ax (gemm 3 1 3 a x))
        (id2 (arr (list 1.0 0.0 0.0 1.0)))]
    (do
      (assert (near? (f64ArrayGet l 0) 2.0 1.0e-12) "L00 = 2 (Wikipedia example)")
      (assert (near? (f64ArrayGet l 3) 6.0 1.0e-12) "L10 = 6")
      (assert (near? (f64ArrayGet l 4) 1.0 1.0e-12) "L11 = 1")
      (assert (near? (f64ArrayGet l 6) -8.0 1.0e-12) "L20 = -8")
      (assert (near? (f64ArrayGet l 7) 5.0 1.0e-12) "L21 = 5")
      (assert (near? (f64ArrayGet l 8) 3.0 1.0e-12) "L22 = 3")
      (assert (= (f64ArrayGet l 1) 0.0) "upper triangle of L is zero")
      (assert (< (maxDiff! rec a 0 0.0) 1.0e-12) "L*L^T reconstructs A")
      (assert (< (maxDiff! ax b 0 0.0) 1.0e-10) "A*x = b")
      (assert (near? (f64ArrayGet x 0) 28.58333333333333 1.0e-9) "x0 known answer")
      (assert (isErr? (ch/choleskyFactor 2 (arr (list 1.0 2.0 2.0 1.0))) "linalgNotPositiveDefinite") "indefinite matrix is an error")
      (assert (isErr? (ch/choleskyFactor 2 (arr (list 1.0 1.0 1.0 1.0))) "linalgNotPositiveDefinite") "singular matrix is an error")
      (assert (isErr? (ch/choleskyFactor 2 (arr (list -1.0 0.0 0.0 1.0))) "linalgNotPositiveDefinite") "negative first pivot")
      (assert (isErr? (ch/choleskyFactor 2 (arr (list 2.0 1.0 0.0 2.0))) "linalgNotSymmetric") "asymmetric")
      (assert (isErr? (ch/choleskyFactor 3 (arr (list 1.0 0.0 0.0 1.0))) "linalgShape") "length not n*n")
      (assert (isErr? (ch/choleskyFactor 0 (arr (list))) "linalgShape") "empty")
      (assert (isErr? (ch/choleskyFactor 1 (arr (list (/ 0.0 0.0)))) "linalgNonFinite") "NaN entry")
      (assert (isErr? (ch/choleskySolve 2 id2 (arr (list 1.0 2.0 3.0))) "linalgShape") "rhs length mismatch")
      (assert (isErr? (ch/choleskySolve 2 (arr (list 1.0 0.0 0.0 0.0)) (arr (list 1.0 2.0))) "linalgNotPositiveDefinite") "zero diagonal factor refused")
      (assert (isErr? (ch/choleskySolve 2 id2 (arr (list 1.0 (/ 0.0 0.0)))) "linalgNonFinite") "NaN rhs")
      (assert (near? (rcondOf 3 (d/identity 3)) 1.0 1.0e-12) "rcond of the identity is 1")
      (assert (near? (rcondOf 2 (arr (list 1.0 0.0 0.0 1.0e-8))) 1.0e-8 1.0e-12) "rcond of diag(1,1e-8) is 1e-8")
      (assert (and (> (rcondOf 6 (hilbert 6)) 1.0e-8) (< (rcondOf 6 (hilbert 6)) 1.0e-6)) "Hilbert 6: numpy 1/cond1 = 3.4e-8, estimate within a factor 3")
      (assert (< (rcondOf 12 (hilbert 12)) 1.0e-14) "Hilbert 12 (numpy cond1 3.8e16): rcond below 1e-14, the caller can refuse the solve")
      (assert (> (rcondOf 3 a) 1.0e-5) "Wikipedia 3x3 is well conditioned relative to Hilbert")
      (assert (match (ch/choleskyRcond 3 (arr (list 1.0)) (d/identity 3)) ((err e) (stringContains? e "linalgShape")) ((ok r) false)) "rcond shape mismatch")
      true))
