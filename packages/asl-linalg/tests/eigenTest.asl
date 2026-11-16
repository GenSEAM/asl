(module asl-linalg/tests/eigenTest
  :x [runTests]
  :i [(asl-linalg/eigen :a e) (asl-linalg/dense :a d)])

fn arr xs: (List Float64) -> F64Array
  (f64ArrayConcat (map (fn [(x Float64)] -> F64Array (f64ArrayGenerate 1 (fn [(i Int64)] -> Float64 x))) xs))

fn near? a: Float64 b: Float64 eps: Float64 -> Bool
  (< (abs (- a b)) eps)

fn ! maxAbs! a: F64Array i: Int64 acc: Float64 -> Float64
  (if (>= i (f64ArrayLen a)) acc
    (maxAbs! a (+ i 1) (max acc (abs (f64ArrayGet a i)))))

fn isErr? r: (Result e/Eigen String) key: String -> Bool
  (match r
    ((err x) (stringContains? x key))
    ((ok v) false))

fn eig n: Int64 a: F64Array -> e/Eigen
  (match (e/eigenSym n a)
    ((err x) (e/Eigen :values (arr (list)) :vectors (arr (list)) :sweeps -9))
    ((ok v) v))

fn tr n: Int64 a: F64Array -> F64Array
  (match (d/transpose n n a) ((err x) a) ((ok t) t))

fn ! diffMax a: F64Array b: F64Array -> Float64
  (maxAbs! (axpy -1.0 b a) 0 0.0)

fn scaled n: Int64 v: F64Array lam: F64Array -> F64Array
  (f64ArrayGenerate (* n n) (fn [(k Int64)] -> Float64 (* (f64ArrayGet v k) (f64ArrayGet lam (% k n)))))

fn ! avErr n: Int64 a: F64Array r: e/Eigen -> Float64
  (diffMax (gemm n n n a r.vectors) (scaled n r.vectors r.values))

fn ! orthErr n: Int64 r: e/Eigen -> Float64
  (diffMax (gemm n n n (tr n r.vectors) r.vectors) (d/identity n))

fn symm s: Float64 -> F64Array
  (f64ArrayGenerate 36 (fn [(k Int64)] -> Float64 (* s (+ (sin (int64ToFloat64 (+ (+ (/ k 6) (% k 6)) 1))) (if (= (/ k 6) (% k 6)) (int64ToFloat64 (/ k 6)) 0.0)))))

fn ! scaleErr! s: Float64 -> Float64
  (let [(r1 (eig 6 (symm 1.0)))
        (r2 (eig 6 (symm s)))
        (back (f64ArrayGenerate 6 (fn [(i Int64)] -> Float64 (/ (f64ArrayGet r2.values i) s))))]
    (diffMax back r1.values))

fn ! runTests -> Bool
  (let [(a2 (arr (list 2.0 1.0 1.0 2.0)))
        (r2 (eig 2 a2))
        (a3 (arr (list 2.0 -1.0 0.0 -1.0 2.0 -1.0 0.0 -1.0 2.0)))
        (r3 (eig 3 a3))
        (s2 (sqrt 2.0))
        (dg (arr (list 5.0 0.0 0.0 0.0 -3.0 0.0 0.0 0.0 1.0)))
        (rd (eig 3 dg))
        (id (eig 3 (d/identity 3)))
        (n 7)
        (h (f64ArrayGenerate 49 (fn [(k Int64)] -> Float64 (/ 1.0 (+ 1.0 (int64ToFloat64 (+ (/ k 7) (% k 7))))))))
        (rh (eig 7 h))
        (r1 (eig 1 (arr (list 4.5))))]
    (do
      (assert (and (near? (f64ArrayGet r2.values 0) 1.0 1.0e-13) (near? (f64ArrayGet r2.values 1) 3.0 1.0e-13)) "2x2 [[2,1],[1,2]] has eigenvalues 1 and 3")
      (assert (near? (abs (f64ArrayGet r2.vectors 1)) (/ 1.0 s2) 1.0e-12) "eigenvector of 3 is (1,1)/sqrt 2 up to sign")
      (assert (< (avErr 2 a2 r2) 1.0e-13) "A v = lambda v for 2x2")
      (assert (and (near? (f64ArrayGet r3.values 0) (- 2.0 s2) 1.0e-13) (near? (f64ArrayGet r3.values 1) 2.0 1.0e-13) (near? (f64ArrayGet r3.values 2) (+ 2.0 s2) 1.0e-13)) "tridiagonal 3x3 eigenvalues 2-sqrt2, 2, 2+sqrt2")
      (assert (< (avErr 3 a3 r3) 1.0e-13) "A v = lambda v for 3x3")
      (assert (< (orthErr 3 r3) 1.0e-13) "V^T V = I for 3x3")
      (assert (and (= (f64ArrayGet rd.values 0) -3.0) (= (f64ArrayGet rd.values 1) 1.0) (= (f64ArrayGet rd.values 2) 5.0)) "diagonal input comes back sorted")
      (assert (= rd.sweeps 0) "diagonal input needs no sweep")
      (assert (and (= (f64ArrayGet id.values 0) 1.0) (= (f64ArrayGet id.values 2) 1.0) (< (orthErr 3 id) 1.0e-15)) "identity: repeated eigenvalue, orthonormal vectors")
      (assert (near? (f64ArrayGet r1.values 0) 4.5 1.0e-15) "1x1")
      (assert (< (avErr 7 h rh) 1.0e-13) "A v = lambda v for the 7x7 Hankel-Hilbert matrix")
      (assert (< (orthErr 7 rh) 1.0e-13) "V^T V = I for 7x7")
      (assert (>= (f64ArrayGet rh.values 6) (f64ArrayGet h 0)) "largest eigenvalue is at least the largest diagonal entry")
      (assert (near? (f64ArraySum rh.values) (f64ArraySum (f64ArrayGenerate 7 (fn [(k Int64)] -> Float64 (f64ArrayGet h (* k 8))))) 1.0e-12) "sum of eigenvalues equals the trace")
      (assert (isErr? (e/eigenSym 2 (arr (list 1.0 2.0 3.0 1.0))) "linalgNotSymmetric") "asymmetric")
      (assert (isErr? (e/eigenSym 2 (arr (list 1.0 2.0 2.0))) "linalgShape") "length mismatch")
      (assert (isErr? (e/eigenSym 0 (arr (list))) "linalgShape") "empty")
      (assert (isErr? (e/eigenSym 2 (arr (list 1.0 (/ 0.0 0.0) (/ 0.0 0.0) 1.0))) "linalgNonFinite") "NaN")
      (assert (< (scaleErr! 1.0e154) 1.0e-12) "scale 1e154: values equal the unscaled ones times 1e154 (was 47 percent off)")
      (assert (< (scaleErr! 1.0e-170) 1.0e-12) "scale 1e-170 (was a returned diagonal)")
      (assert (< (scaleErr! 1.0e-160) 1.0e-12) "scale 1e-160")
      (assert (< (scaleErr! 1.0e300) 1.0e-12) "scale 1e300")
      (assert (= (f64ArrayGet (eig 2 (arr (list 0.0 0.0 0.0 0.0))).values 0) 0.0) "all-zero matrix keeps eigenvalue 0")
      true))
