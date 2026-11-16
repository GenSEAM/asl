(module asl-linalg/qr
  :x [Lstsq lstsq lstsqTol defaultRankTol]
  :i [(asl-linalg/dense :a d)])

; (:m :ref NUM-LINALG-STATS :do "least squares min |A x - b|_2 by Householder QR with column pivoting (Businger-Golub); A is m x n row-major, any m,n >= 1; rank is the count of pivots with |R_kk| > tol*|R_00|, the default tol being max(m,n)*2.2e-16 relative to the largest pivot (near-dependence at about 1e-14 relative is borderline); A and b are each scaled by a power of two first so extreme magnitudes neither overflow nor underflow; a rank-deficient A is not an error, it is reported through rank < n and gets the basic solution (pivoted columns past the rank get coefficient 0); non-finite input, shape mismatch and a negative tol are explicit errors")
schema Lstsq
  (:f coef F64Array)
  (:f rank Int64)
  (:f residualNorm Float64)
  (:f tol Float64)

fn defaultRankTol m: Int64 n: Int64 -> Float64
  (* (int64ToFloat64 (max m n)) 2.220446049250313e-16)

fn ! colNorm2! ab: Bytes n: Int64 m: Int64 j: Int64 i: Int64 acc: Float64 -> Float64
  (if (>= i m) acc
    (colNorm2! ab n m j (+ i 1) (+ acc (* (d/getAt! ab n i j) (d/getAt! ab n i j)))))

fn ! pickPivot! ab: Bytes m: Int64 n: Int64 k: Int64 j: Int64 best: Int64 bestVal: Float64 -> Int64
  (if (>= j n) best
    (let [(v (colNorm2! ab n m j k 0.0))]
      (if (> v bestVal)
        (pickPivot! ab m n k (+ j 1) j v)
        (pickPivot! ab m n k (+ j 1) best bestVal))))

fn ! swapCols! ab: Bytes n: Int64 m: Int64 c1: Int64 c2: Int64 i: Int64 -> Int64
  (if (>= i m) 0
    (let [(t (d/getAt! ab n i c1))]
      (do (d/setAt! ab n i c1 (d/getAt! ab n i c2))
          (d/setAt! ab n i c2 t)
          (swapCols! ab n m c1 c2 (+ i 1)))))

fn ! applyRefl! ab: Bytes vb: Bytes n: Int64 m: Int64 k: Int64 j: Int64 vtv: Float64 -> Int64
  (let [(s (vdot! ab vb n m k j k 0.0))
        (beta (/ (* 2.0 s) vtv))]
    (axpyCol! ab vb n m k j k (- 0.0 beta)))

fn ! vdot! ab: Bytes vb: Bytes n: Int64 m: Int64 k: Int64 j: Int64 i: Int64 acc: Float64 -> Float64
  (if (>= i m) acc
    (vdot! ab vb n m k j (+ i 1) (+ acc (* (bytesGetFloat64 vb i) (d/getAt! ab n i j)))))

fn ! axpyCol! ab: Bytes vb: Bytes n: Int64 m: Int64 k: Int64 j: Int64 i: Int64 c: Float64 -> Int64
  (if (>= i m) 0
    (do (d/setAt! ab n i j (+ (d/getAt! ab n i j) (* c (bytesGetFloat64 vb i))))
        (axpyCol! ab vb n m k j (+ i 1) c)))

fn ! applyAll! ab: Bytes vb: Bytes n: Int64 m: Int64 k: Int64 j: Int64 vtv: Float64 -> Int64
  (if (>= j n) 0
    (do (applyRefl! ab vb n m k j vtv)
        (applyAll! ab vb n m k (+ j 1) vtv)))

fn ! applyB! qb: Bytes vb: Bytes m: Int64 k: Int64 vtv: Float64 -> Int64
  (let [(s (vdotB! qb vb m k 0.0))
        (beta (/ (* 2.0 s) vtv))]
    (axpyB! qb vb m k (- 0.0 beta)))

fn ! vdotB! qb: Bytes vb: Bytes m: Int64 i: Int64 acc: Float64 -> Float64
  (if (>= i m) acc
    (vdotB! qb vb m (+ i 1) (+ acc (* (bytesGetFloat64 vb i) (bytesGetFloat64 qb i)))))

fn ! axpyB! qb: Bytes vb: Bytes m: Int64 i: Int64 c: Float64 -> Int64
  (if (>= i m) 0
    (do (bytesSetFloat64 qb i (+ (bytesGetFloat64 qb i) (* c (bytesGetFloat64 vb i))))
        (axpyB! qb vb m (+ i 1) c)))

fn ! fillV! ab: Bytes vb: Bytes n: Int64 m: Int64 k: Int64 alpha: Float64 i: Int64 acc: Float64 -> Float64
  (if (>= i m) acc
    (let [(x (if (= i k) (- (d/getAt! ab n i k) alpha) (d/getAt! ab n i k)))]
      (do (bytesSetFloat64 vb i x)
          (fillV! ab vb n m k alpha (+ i 1) (+ acc (* x x))))))

fn ! qrLoop! ab: Bytes qb: Bytes vb: Bytes pb: Bytes m: Int64 n: Int64 k: Int64 kmax: Int64 tol: Float64 r0: Float64 -> Int64
  (if (>= k kmax) k
    (let [(p (pickPivot! ab m n k k k -1.0))
          (nrm (sqrt (colNorm2! ab n m p k 0.0)))
          (limit (if (= k 0) 0.0 (* tol r0)))]
      (if (or (= nrm 0.0) (<= nrm limit))
        k
        (do (if (= p k) 0
              (do (swapCols! ab n m k p 0)
                  (let [(t (bytesGetFloat64 pb k))]
                    (do (bytesSetFloat64 pb k (bytesGetFloat64 pb p))
                        (bytesSetFloat64 pb p t)
                        0))))
            (let [(akk (d/getAt! ab n k k))
                  (alpha (if (> akk 0.0) (- 0.0 nrm) nrm))
                  (vtv (fillV! ab vb n m k alpha k 0.0))]
              (do (applyAll! ab vb n m k (+ k 1) vtv)
                  (applyB! qb vb m k vtv)
                  (d/setAt! ab n k k alpha)
                  (qrLoop! ab qb vb pb m n (+ k 1) kmax tol (if (= k 0) nrm r0))))))))

fn ! backSub! ab: Bytes n: Int64 rank: Int64 qb: Bytes xb: Bytes i: Int64 -> Int64
  (if (< i 0) 0
    (let [(s (backDot! ab n xb i (+ i 1) rank 0.0))]
      (do (bytesSetFloat64 xb i (/ (- (bytesGetFloat64 qb i) s) (d/getAt! ab n i i)))
          (backSub! ab n rank qb xb (- i 1)))))

fn ! backDot! ab: Bytes n: Int64 xb: Bytes i: Int64 j: Int64 rank: Int64 acc: Float64 -> Float64
  (if (>= j rank) acc
    (backDot! ab n xb i (+ j 1) rank (+ acc (* (d/getAt! ab n i j) (bytesGetFloat64 xb j)))))

fn ! scatter! xb: Bytes pb: Bytes out: Bytes rank: Int64 j: Int64 -> Int64
  (if (>= j rank) 0
    (do (bytesSetFloat64 out (optionOr (float64ToInt64 (bytesGetFloat64 pb j)) 0) (bytesGetFloat64 xb j))
        (scatter! xb pb out rank (+ j 1))))

fn ! initPerm! pb: Bytes j: Int64 n: Int64 -> Int64
  (if (>= j n) 0
    (do (bytesSetFloat64 pb j (int64ToFloat64 j))
        (initPerm! pb (+ j 1) n)))

fn ! tailNorm2! qb: Bytes i: Int64 m: Int64 acc: Float64 -> Float64
  (if (>= i m) acc
    (tailNorm2! qb (+ i 1) m (+ acc (* (bytesGetFloat64 qb i) (bytesGetFloat64 qb i)))))

fn ! lstsqTol m: Int64 n: Int64 a: F64Array b: F64Array tol: Float64 -> (Result Lstsq String)
  (cond
    ((or (< m 1) (< n 1)) (err "linalgShape: m and n must be at least 1"))
    ((not (= (f64ArrayLen a) (* m n))) (err "linalgShape: matrix length is not m*n"))
    ((not (= (f64ArrayLen b) m)) (err "linalgShape: right-hand side length is not m"))
    ((not (and (d/allFinite a) (d/allFinite b))) (err "linalgNonFinite: input has a NaN or infinite entry"))
    ((not (and (>= tol 0.0) (< tol 1.0))) (err "linalgTolerance: tol must be in [0,1)"))
    (else
      (let [(ea (d/pow2Exponent (d/maxAbs a) 0))
            (eb (d/pow2Exponent (d/maxAbs b) 0))
            (ab (d/toBuf (d/scaleArray a (- 0 ea))))
            (qb (d/toBuf (d/scaleArray b (- 0 eb))))
            (vb (bytesAlloc (* 8 m)))
            (pb (bytesAlloc (* 8 n)))
            (xb (bytesAlloc (* 8 n)))
            (out (bytesAlloc (* 8 n)))]
        (do (initPerm! pb 0 n)
            (let [(rank (qrLoop! ab qb vb pb m n 0 (min m n) tol 0.0))]
              (do (backSub! ab n rank qb xb (- rank 1))
                  (scatter! xb pb out rank 0)
                  (ok (Lstsq :coef (d/scaleArray (d/fromBuf out n) (- eb ea)) :rank rank :residualNorm (d/mul2 (sqrt (tailNorm2! qb rank m 0.0)) eb) :tol tol))))))))

fn ! lstsq m: Int64 n: Int64 a: F64Array b: F64Array -> (Result Lstsq String)
  (lstsqTol m n a b (defaultRankTol m n))
