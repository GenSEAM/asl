(module asl-linalg/eigen
  :x [Eigen eigenSym]
  :i [(asl-linalg/dense :a d)])

; (:m :ref NUM-LINALG-STATS :do "eigenvalues and eigenvectors of a symmetric n x n matrix by cyclic Jacobi (Numerical Recipes rotation, full-matrix update, at most 60 sweeps); iteration stops when the squared off-diagonal mass is below 1e-28 of the squared Frobenius norm, so eigenvalues are accurate to about 1e-14 times the matrix norm at any scale (the matrix is first divided by the power of two 2^e that brings max|a| into [1,2) and the values multiplied back); values ascend and column k of the row-major vectors matrix (vectors[i*n+k]) is the unit eigenvector of values[k]; non-symmetric (relative 1e-9), non-finite, empty and non-converging input are explicit errors; cost is O(n^3) per sweep, intended for small n")
schema Eigen
  (:f values F64Array)
  (:f vectors F64Array)
  (:f sweeps Int64)

fn ! offMass! ab: Bytes n: Int64 i: Int64 j: Int64 acc: Float64 -> Float64
  (cond
    ((>= i n) acc)
    ((>= j n) (offMass! ab n (+ i 1) 0 acc))
    ((= i j) (offMass! ab n i (+ j 1) acc))
    (else (offMass! ab n i (+ j 1) (+ acc (* (d/getAt! ab n i j) (d/getAt! ab n i j))))))

fn ! rotCols! m: Bytes n: Int64 p: Int64 q: Int64 c: Float64 s: Float64 k: Int64 -> Int64
  (if (>= k n) 0
    (let [(x (d/getAt! m n k p))
          (y (d/getAt! m n k q))]
      (do (d/setAt! m n k p (- (* c x) (* s y)))
          (d/setAt! m n k q (+ (* s x) (* c y)))
          (rotCols! m n p q c s (+ k 1)))))

fn ! rotRows! m: Bytes n: Int64 p: Int64 q: Int64 c: Float64 s: Float64 k: Int64 -> Int64
  (if (>= k n) 0
    (let [(x (d/getAt! m n p k))
          (y (d/getAt! m n q k))]
      (do (d/setAt! m n p k (- (* c x) (* s y)))
          (d/setAt! m n q k (+ (* s x) (* c y)))
          (rotRows! m n p q c s (+ k 1)))))

fn ! rotate! ab: Bytes vb: Bytes n: Int64 p: Int64 q: Int64 -> Int64
  (let [(apq (d/getAt! ab n p q))]
    (if (= apq 0.0) 0
      (let [(theta (/ (- (d/getAt! ab n q q) (d/getAt! ab n p p)) (* 2.0 apq)))
            (t (/ (if (< theta 0.0) -1.0 1.0) (+ (abs theta) (sqrt (+ (* theta theta) 1.0)))))
            (c (/ 1.0 (sqrt (+ (* t t) 1.0))))
            (s (* t c))]
        (do (rotCols! ab n p q c s 0)
            (rotRows! ab n p q c s 0)
            (d/setAt! ab n p q 0.0)
            (d/setAt! ab n q p 0.0)
            (rotCols! vb n p q c s 0)))))

fn ! sweep! ab: Bytes vb: Bytes n: Int64 p: Int64 q: Int64 -> Int64
  (cond
    ((>= p (- n 1)) 0)
    ((>= q n) (sweep! ab vb n (+ p 1) (+ p 2)))
    (else (do (rotate! ab vb n p q) (sweep! ab vb n p (+ q 1)))))

fn ! jacobi! ab: Bytes vb: Bytes n: Int64 sweeps: Int64 limit: Float64 -> Int64
  (cond
    ((<= (offMass! ab n 0 0 0.0) limit) sweeps)
    ((>= sweeps 60) -1)
    (else (do (sweep! ab vb n 0 1) (jacobi! ab vb n (+ sweeps 1) limit))))

fn ! argMin! ab: Bytes used: Bytes n: Int64 j: Int64 best: Int64 -> Int64
  (cond
    ((>= j n) best)
    ((= (bytesGet used j) 1) (argMin! ab used n (+ j 1) best))
    ((< best 0) (argMin! ab used n (+ j 1) j))
    ((< (d/getAt! ab n j j) (d/getAt! ab n best best)) (argMin! ab used n (+ j 1) j))
    (else (argMin! ab used n (+ j 1) best)))

fn ! copyCol! vb: Bytes ob: Bytes n: Int64 from: Int64 to: Int64 i: Int64 -> Int64
  (if (>= i n) 0
    (do (d/setAt! ob n i to (d/getAt! vb n i from))
        (copyCol! vb ob n from to (+ i 1))))

fn ! order! ab: Bytes vb: Bytes used: Bytes vals: Bytes ob: Bytes n: Int64 k: Int64 -> Int64
  (if (>= k n) 0
    (let [(j (argMin! ab used n 0 -1))]
      (do (bytesSet used j 1)
          (bytesSetFloat64 vals k (d/getAt! ab n j j))
          (copyCol! vb ob n j k 0)
          (order! ab vb used vals ob n (+ k 1)))))

fn ! eigenSym n: Int64 a: F64Array -> (Result Eigen String)
  (cond
    ((< n 1) (err "linalgShape: n must be at least 1"))
    ((not (= (f64ArrayLen a) (* n n))) (err "linalgShape: matrix length is not n*n"))
    ((not (d/allFinite a)) (err "linalgNonFinite: matrix has a NaN or infinite entry"))
    (else
      (let [(e (d/pow2Exponent (d/maxAbs a) 0))
            (ab (d/toBuf (d/scaleArray a (- 0 e))))
            (vb (d/toBuf (d/identity n)))
            (frob (offMass! ab n 0 0 (diagMass! ab n 0 0.0)))]
        (if (d/asymmetric! ab n 0 0)
          (err "linalgNotSymmetric: matrix is not symmetric within 1e-9")
          (let [(sweeps (jacobi! ab vb n 0 (* 1.0e-28 frob)))]
            (if (< sweeps 0)
              (err "linalgNoConvergence: Jacobi did not converge in 60 sweeps")
              (let [(used (bytesAlloc n))
                    (vals (bytesAlloc (* 8 n)))
                    (ob (bytesAlloc (* 8 (* n n))))]
                (do (order! ab vb used vals ob n 0)
                    (ok (Eigen :values (d/scaleArray (d/fromBuf vals n) e) :vectors (d/fromBuf ob (* n n)) :sweeps sweeps))))))))))

fn ! diagMass! ab: Bytes n: Int64 i: Int64 acc: Float64 -> Float64
  (if (>= i n) acc
    (diagMass! ab n (+ i 1) (+ acc (* (d/getAt! ab n i i) (d/getAt! ab n i i)))))
