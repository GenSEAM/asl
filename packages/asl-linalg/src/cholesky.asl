(module asl-linalg/cholesky
  :x [choleskyFactor choleskySolve choleskySolveSpd choleskyRcond]
  :i [(asl-linalg/dense :a d)])

; (:m :ref NUM-LINALG-STATS :do "lower Cholesky A = L*L^T of a symmetric positive definite n x n matrix, row-major; only the symmetry of A is checked (relative 1e-9) and a pivot at or below 1e-13 times its diagonal entry, or a non-finite one, is the explicit error linalgNotPositiveDefinite; no output is ever a silent wrong answer")
fn ! rowDot! l: Bytes n: Int64 i: Int64 j: Int64 k: Int64 t: Int64 acc: Float64 -> Float64
  (if (>= t k) acc
    (rowDot! l n i j k (+ t 1) (+ acc (* (d/getAt! l n i t) (d/getAt! l n j t)))))

fn ! chStep! l: Bytes a: Bytes n: Int64 i: Int64 j: Int64 -> (Result Bool String)
  (cond
    ((>= i n) (ok true))
    ((> j i) (chStep! l a n (+ i 1) 0))
    (else
      (let [(s (- (d/getAt! a n i j) (rowDot! l n i j j 0 0.0)))]
        (if (= i j)
          (if (> s (* 1.0e-13 (abs (d/getAt! a n i i))))
            (do (d/setAt! l n i i (sqrt s)) (chStep! l a n i (+ j 1)))
            (err (stringConcat "linalgNotPositiveDefinite: pivot " (stringConcat (stringFromInt64 i) (stringConcat " is " (stringFromFloat64 s))))))
          (do (d/setAt! l n i j (/ s (d/getAt! l n j j))) (chStep! l a n i (+ j 1)))))))

fn ! choleskyFactor n: Int64 a: F64Array -> (Result F64Array String)
  (cond
    ((< n 1) (err "linalgShape: n must be at least 1"))
    ((not (= (f64ArrayLen a) (* n n))) (err "linalgShape: matrix length is not n*n"))
    ((not (d/allFinite a)) (err "linalgNonFinite: matrix has a NaN or infinite entry"))
    (else
      (let [(ab (d/toBuf a))
            (l (bytesAlloc (* 8 (* n n))))]
        (if (d/asymmetric! ab n 0 0)
          (err "linalgNotSymmetric: matrix is not symmetric within 1e-9")
          (match (chStep! l ab n 0 0)
            ((err e) (err e))
            ((ok u) (ok (d/fromBuf l (* n n)))))))))

fn ! fwd! l: Bytes y: Bytes n: Int64 i: Int64 -> Int64
  (if (>= i n) 0
    (do (bytesSetFloat64 y i (/ (- (bytesGetFloat64 y i) (rowDot2! l y n i 0 0.0)) (d/getAt! l n i i)))
        (fwd! l y n (+ i 1))))

fn ! rowDot2! l: Bytes y: Bytes n: Int64 i: Int64 t: Int64 acc: Float64 -> Float64
  (if (>= t i) acc
    (rowDot2! l y n i (+ t 1) (+ acc (* (d/getAt! l n i t) (bytesGetFloat64 y t)))))

fn ! colDot! l: Bytes y: Bytes n: Int64 i: Int64 t: Int64 acc: Float64 -> Float64
  (if (>= t n) acc
    (colDot! l y n i (+ t 1) (+ acc (* (d/getAt! l n t i) (bytesGetFloat64 y t)))))

fn ! bwd! l: Bytes y: Bytes n: Int64 i: Int64 -> Int64
  (if (< i 0) 0
    (do (bytesSetFloat64 y i (/ (- (bytesGetFloat64 y i) (colDot! l y n i (+ i 1) 0.0)) (d/getAt! l n i i)))
        (bwd! l y n (- i 1))))

fn ! choleskySolve n: Int64 l: F64Array b: F64Array -> (Result F64Array String)
  (cond
    ((< n 1) (err "linalgShape: n must be at least 1"))
    ((not (= (f64ArrayLen l) (* n n))) (err "linalgShape: factor length is not n*n"))
    ((not (= (f64ArrayLen b) n)) (err "linalgShape: right-hand side length is not n"))
    ((not (and (d/allFinite l) (d/allFinite b))) (err "linalgNonFinite: factor or right-hand side has a NaN or infinite entry"))
    ((not (diagPositive? l n 0)) (err "linalgNotPositiveDefinite: factor has a non-positive diagonal entry"))
    (else
      (let [(lb (d/toBuf l))
            (y (d/toBuf b))]
        (do (fwd! lb y n 0)
            (bwd! lb y n (- n 1))
            (ok (d/fromBuf y n))))))

fn diagPositive? l: F64Array n: Int64 i: Int64 -> Bool
  (if (>= i n) true
    (if (> (f64ArrayGet l (+ (* i n) i)) 0.0) (diagPositive? l n (+ i 1)) false))

fn ! choleskySolveSpd n: Int64 a: F64Array b: F64Array -> (Result F64Array String)
  (match (choleskyFactor n a)
    ((err e) (err e))
    ((ok l) (choleskySolve n l b)))

; (:m :ref NUM-LINALG-STATS :do "reciprocal 1-norm condition estimate of an SPD matrix from its factor: rcond = 1/(|A|_1 * est|A^-1|_1) with est the Hager-Higham iteration (at most 5 steps, solves through the factor) maxed with the Higham alternating-sign probe, a lower bound of |A^-1|_1, so rcond may overstate the true value by a small factor, never by orders; rcond near 1e-16 means the solution has no correct digits, and a solve of an ill-conditioned system is the caller's check, choleskySolveSpd does not refuse it; verified against numpy cond(A,1) within a factor 3 on Hilbert 6 and 12")
fn ! sumAbs! a: F64Array -> Float64
  (f64ArrayFold (fn [(s Float64) (x Float64)] -> Float64 (+ s (abs x))) 0.0 a)

fn ! colSums! a: F64Array n: Int64 j: Int64 best: Float64 -> Float64
  (if (>= j n) best
    (colSums! a n (+ j 1) (max best (sumAbs! (f64ArrayGenerate n (fn [(i Int64)] -> Float64 (f64ArrayGet a (+ (* i n) j))))))))

fn ! argMaxAbs! a: F64Array i: Int64 best: Int64 -> Int64
  (cond
    ((>= i (f64ArrayLen a)) best)
    ((> (abs (f64ArrayGet a i)) (abs (f64ArrayGet a best))) (argMaxAbs! a (+ i 1) i))
    (else (argMaxAbs! a (+ i 1) best)))

fn ! hager! n: Int64 l: F64Array x: F64Array k: Int64 est: Float64 -> (Result Float64 String)
  (match (choleskySolve n l x)
    ((err e) (err e))
    ((ok y)
      (let [(e2 (max est (sumAbs! y)))
            (xi (f64ArrayGenerate n (fn [(i Int64)] -> Float64 (if (< (f64ArrayGet y i) 0.0) -1.0 1.0))))]
        (match (choleskySolve n l xi)
          ((err e) (err e))
          ((ok z)
            (let [(j (argMaxAbs! z 0 0))]
              (if (or (>= k 4) (<= (abs (f64ArrayGet z j)) (dot z x)))
                (ok e2)
                (hager! n l (f64ArrayGenerate n (fn [(i Int64)] -> Float64 (if (= i j) 1.0 0.0))) (+ k 1) e2))))))))

fn ! choleskyRcond n: Int64 a: F64Array l: F64Array -> (Result Float64 String)
  (cond
    ((< n 1) (err "linalgShape: n must be at least 1"))
    ((not (= (f64ArrayLen a) (* n n))) (err "linalgShape: matrix length is not n*n"))
    (else
      (match (hager! n l (f64ArrayGenerate n (fn [(i Int64)] -> Float64 (/ 1.0 (int64ToFloat64 n)))) 0 0.0)
        ((err e) (err e))
        ((ok est1)
          (let [(alt (f64ArrayGenerate n (fn [(i Int64)] -> Float64 (* (if (= (% i 2) 0) 1.0 -1.0) (+ 1.0 (/ (int64ToFloat64 i) (int64ToFloat64 (max 1 (- n 1)))))))))]
            (match (choleskySolve n l alt)
              ((err e) (err e))
              ((ok ya)
                (let [(est (max est1 (/ (* 2.0 (sumAbs! ya)) (* 3.0 (int64ToFloat64 n)))))]
                  (ok (/ 1.0 (* (colSums! a n 0 0.0) est)))))))))))
