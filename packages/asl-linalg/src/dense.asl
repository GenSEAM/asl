(module asl-linalg/dense
  :x [pow2Exponent mul2 scaleArray maxAbs asymmetric! toBuf fromBuf getAt! setAt! allFinite identity transpose matVec]
  :i [])

; (:m :ref NUM-LINALG-STATS :do "F64Array is immutable, so the factorisations work in a Bytes scratch buffer of Float64 slots, row-major, and copy out once at the end; every kernel checks shapes and finiteness first and returns (err msg) instead of trapping")
fn ! copyIn! b: Bytes a: F64Array i: Int64 n: Int64 -> Bytes
  (if (>= i n) b
    (do (bytesSetFloat64 b i (f64ArrayGet a i)) (copyIn! b a (+ i 1) n)))

fn ! toBuf a: F64Array -> Bytes
  (let [(n (f64ArrayLen a))]
    (copyIn! (bytesAlloc (* 8 n)) a 0 n))

fn ! fromBuf b: Bytes n: Int64 -> F64Array
  (f64ArrayGenerate n (fn [(i Int64)] -> Float64 (bytesGetFloat64 b i)))

fn ! getAt! b: Bytes cols: Int64 i: Int64 j: Int64 -> Float64
  (bytesGetFloat64 b (+ (* i cols) j))

fn ! setAt! b: Bytes cols: Int64 i: Int64 j: Int64 v: Float64 -> Unit
  (bytesSetFloat64 b (+ (* i cols) j) v)

fn allFinite a: F64Array -> Bool
  (f64ArrayFold (fn [(ok Bool) (x Float64)] -> Bool (and ok (and (= x x) (< (abs x) 1.0e308)))) true a)

fn identity n: Int64 -> F64Array
  (f64ArrayGenerate (* n n) (fn [(k Int64)] -> Float64 (if (= (/ k n) (% k n)) 1.0 0.0)))

fn transpose m: Int64 n: Int64 a: F64Array -> (Result F64Array String)
  (cond
    ((or (< m 0) (< n 0)) (err "linalgShape: negative dimension"))
    ((not (= (f64ArrayLen a) (* m n))) (err "linalgShape: transpose array length is not m*n"))
    (else (ok (f64ArrayGenerate (* m n) (fn [(k Int64)] -> Float64 (f64ArrayGet a (+ (* (% k m) n) (/ k m))))))))

fn matVec m: Int64 n: Int64 a: F64Array x: F64Array -> (Result F64Array String)
  (cond
    ((or (< m 0) (< n 0)) (err "linalgShape: negative dimension"))
    ((not (= (f64ArrayLen a) (* m n))) (err "linalgShape: matrix length is not m*n"))
    ((not (= (f64ArrayLen x) n)) (err "linalgShape: vector length is not n"))
    (else (ok (gemm m 1 n a x))))

fn ! asymmetric! a: Bytes n: Int64 i: Int64 j: Int64 -> Bool
  (cond
    ((>= i n) false)
    ((>= j i) (asymmetric! a n (+ i 1) 0))
    (else
      (let [(x (getAt! a n i j))
            (y (getAt! a n j i))]
        (if (> (abs (- x y)) (* 1.0e-9 (+ 1.0 (+ (abs x) (abs y)))))
          true
          (asymmetric! a n i (+ j 1))))))

; (:m :ref NUM-LINALG-STATS :do "extreme scale: the kernels square entries, so inputs near 1e154 or 1e-160 overflow or underflow; callers divide by the power of two 2^e that brings max|a| into [1,2), run on that, and multiply the results back with mul2, which moves in steps of 2^500 so no intermediate leaves the double range; powers of two make both moves exact")
fn maxAbs a: F64Array -> Float64
  (f64ArrayFold (fn [(m Float64) (x Float64)] -> Float64 (max m (abs x))) 0.0 a)

fn pow2Exponent m: Float64 e: Int64 -> Int64
  (cond
    ((= m 0.0) 0)
    ((>= m 2.0) (pow2Exponent (/ m 2.0) (+ e 1)))
    ((< m 1.0) (pow2Exponent (* m 2.0) (- e 1)))
    (else e))

fn mul2 x: Float64 e: Int64 -> Float64
  (cond
    ((= e 0) x)
    ((> e 500) (mul2 (* x 3.273390607896142e150) (- e 500)))
    ((< e -500) (mul2 (/ x 3.273390607896142e150) (+ e 500)))
    ((> e 0) (mul2 (* x 2.0) (- e 1)))
    (else (mul2 (/ x 2.0) (+ e 1))))

fn scaleArray a: F64Array e: Int64 -> F64Array
  (if (= e 0) a
    (f64ArrayGenerate (f64ArrayLen a) (fn [(i Int64)] -> Float64 (mul2 (f64ArrayGet a i) e))))
