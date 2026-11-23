(module asl-linalg/tests/qrTest
  :x [runTests]
  :i [(asl-linalg/qr :a q) (asl-linalg/dense :a d)])

fn arr xs: (List Float64) -> F64Array
  (f64ArrayConcat (map (fn [(x Float64)] -> F64Array (f64ArrayGenerate 1 (fn [(i Int64)] -> Float64 x))) xs))

fn near? a: Float64 b: Float64 eps: Float64 -> Bool
  (< (abs (- a b)) eps)

fn ! maxAbs! a: F64Array i: Int64 acc: Float64 -> Float64
  (if (>= i (f64ArrayLen a)) acc
    (maxAbs! a (+ i 1) (max acc (abs (f64ArrayGet a i)))))

fn isErr? r: (Result q/Lstsq String) key: String -> Bool
  (match r
    ((err e) (stringContains? e key))
    ((ok v) false))

fn zeroFit -> q/Lstsq
  (q/Lstsq :coef (f64ArrayGenerate 0 (fn [(i Int64)] -> Float64 0.0)) :rank -1 :residualNorm 0.0 :tol 0.0)

fn fit r: (Result q/Lstsq String) -> q/Lstsq
  (match r
    ((err e) (zeroFit))
    ((ok v) v))

fn ! orthErr m: Int64 n: Int64 a: F64Array b: F64Array f: q/Lstsq -> Float64
  (let [(ax (gemm m 1 n a f.coef))
        (r (axpy -1.0 ax b))
        (at (match (d/transpose m n a) ((err e) a) ((ok t) t)))]
    (maxAbs! (gemm n 1 m at r) 0 0.0))

fn xs s: Float64 -> F64Array
  (f64ArrayGenerate 60 (fn [(k Int64)] -> Float64 (* s (sin (+ (* 0.37 (int64ToFloat64 k)) (* 0.011 (int64ToFloat64 (mod (* k k) 1000))))))))

fn ys s: Float64 -> F64Array
  (f64ArrayGenerate 20 (fn [(k Int64)] -> Float64 (* s (cos (* 0.73 (int64ToFloat64 k))))))

fn ! relErr! a: F64Array b: F64Array i: Int64 acc: Float64 -> Float64
  (if (>= i (f64ArrayLen a)) acc
    (relErr! a b (+ i 1) (max acc (/ (abs (- (f64ArrayGet a i) (f64ArrayGet b i))) (+ 1.0e-300 (abs (f64ArrayGet b i)))))))

fn ! scaleFit! sa: Float64 sb: Float64 -> Bool
  (let [(base (fit (q/lstsq 20 3 (xs 1.0) (ys 1.0))))
        (f (fit (q/lstsq 20 3 (xs sa) (ys sb))))
        (want (f64ArrayGenerate 3 (fn [(i Int64)] -> Float64 (* (/ sb sa) (f64ArrayGet base.coef i)))))]
    (and (= f.rank 3) (< (relErr! f.coef want 0 0.0) 1.0e-11) (< (abs (- (/ f.residualNorm sb) base.residualNorm)) 1.0e-11)))

fn ! runTests -> Bool
  (let [(a2 (arr (list 1.0 1.0 1.0 2.0 1.0 3.0 1.0 4.0)))
        (b2 (arr (list 1.0 2.0 2.0 4.0)))
        (f2 (fit (q/lstsq 4 2 a2 b2)))
        (ex (fit (q/lstsq 4 2 a2 (arr (list 3.0 5.0 7.0 9.0)))))
        (a3 (arr (list 1.0 1.0 2.0 1.0 2.0 4.0 1.0 3.0 6.0 1.0 4.0 8.0)))
        (f3 (fit (q/lstsq 4 3 a3 b2)))
        (big (f64ArrayGenerate 200 (fn [(k Int64)] -> Float64 (sin (+ (* 0.37 (int64ToFloat64 k)) (* 0.011 (int64ToFloat64 (* k k))))))))
        (bb (f64ArrayGenerate 50 (fn [(k Int64)] -> Float64 (cos (* 0.73 (int64ToFloat64 k))))))
        (fb (fit (q/lstsq 50 4 big bb)))
        (z (fit (q/lstsq 2 2 (arr (list 0.0 0.0 0.0 0.0)) (arr (list 1.0 1.0)))))
        (u (fit (q/lstsq 1 2 (arr (list 1.0 1.0)) (arr (list 2.0)))))]
    (do
      (assert (= f2.rank 2) "full rank 2")
      (assert (near? (f64ArrayGet f2.coef 0) 0.0 1.0e-12) "intercept 0 (hand-computed)")
      (assert (near? (f64ArrayGet f2.coef 1) 0.9 1.0e-12) "slope 0.9 (hand-computed)")
      (assert (near? f2.residualNorm 0.8366600265340756 1.0e-12) "residual norm sqrt(0.7)")
      (assert (< (orthErr 4 2 a2 b2 f2) 1.0e-12) "residual is orthogonal to the columns of A")
      (assert (and (= ex.rank 2) (near? (f64ArrayGet ex.coef 0) 1.0 1.0e-12) (near? (f64ArrayGet ex.coef 1) 2.0 1.0e-12) (< ex.residualNorm 1.0e-12)) "exact fit y = 1 + 2x")
      (assert (= f3.rank 2) "duplicated column (x and 2x) is rank 2 of 3")
      (assert (near? f3.residualNorm 0.8366600265340756 1.0e-12) "rank-deficient residual equals the full-rank projection residual")
      (assert (< (orthErr 4 3 a3 b2 f3) 1.0e-12) "rank-deficient basic solution is still a least squares solution")
      (assert (= fb.rank 4) "50x4 smooth design is rank 4")
      (assert (< (orthErr 50 4 big bb fb) 1.0e-10) "50x4 residual orthogonality")
      (assert (= z.rank 0) "zero matrix has rank 0")
      (assert (= (maxAbs! z.coef 0 0.0) 0.0) "zero matrix coefficients are 0")
      (assert (and (= u.rank 1) (near? (+ (f64ArrayGet u.coef 0) (f64ArrayGet u.coef 1)) 2.0 1.0e-12)) "underdetermined 1x2 gives a solution of A x = b")
      (assert (near? (q/defaultRankTol 4 2) 8.881784197001252e-16 1.0e-30) "default tolerance is max(m,n)*eps")
      (assert (isErr? (q/lstsq 4 2 a2 (arr (list 1.0 2.0 3.0))) "linalgShape") "rhs length mismatch")
      (assert (isErr? (q/lstsq 3 2 a2 b2) "linalgShape") "matrix length mismatch")
      (assert (isErr? (q/lstsq 0 2 (arr (list)) (arr (list))) "linalgShape") "empty")
      (assert (isErr? (q/lstsq 2 1 (arr (list 1.0 (/ 0.0 0.0))) (arr (list 1.0 1.0))) "linalgNonFinite") "NaN in A")
      (assert (isErr? (q/lstsq 2 1 (arr (list 1.0 1.0)) (arr (list 1.0 (/ 0.0 0.0)))) "linalgNonFinite") "NaN in b")
      (assert (isErr? (q/lstsqTol 4 2 a2 b2 -1.0) "linalgTolerance") "negative tol")
      (assert (= (fit (q/lstsqTol 4 2 a2 b2 0.9)).rank 1) "a loose tolerance reports a smaller rank")
      (assert (scaleFit! 1.0e-170 1.0e-170) "A and b at 1e-170: full rank, same coefficients (was rank 0)")
      (assert (scaleFit! 1.0e160 1.0e160) "A and b at 1e160: finite coefficients equal to the unscaled ones (was NaN)")
      (assert (scaleFit! 1.0e154 1.0e-100) "A at 1e154 and b at 1e-100: coefficients scale by b/A")
      (assert (scaleFit! 1.0e-160 1.0e-160) "A and b at 1e-160")
      true))
