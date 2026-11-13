(module asl-stats/interval
  :x [BootResult wilson clopperPearson meanCi bootstrapPercentile twoProportionSampleSize]
  :i [(asl-stats/special :a sp) (asl-stats/describe :a ds) (asl-stats/rng :a rg)])

; (:m :ref workspace-20261031-experimentStats :do "intervals return (Pair lo hi) as (Result .. String): wilson is the score interval (Newcombe 1998 method 3 for one proportion), clopperPearson the exact binomial interval from beta quantiles, meanCi the Student t interval, bootstrapPercentile resamples with replacement from a seeded Rng and returns the percentile interval with the advanced state; conf must be inside (0,1) and counts must satisfy 0<=x<=n, n>=1, else statsRange")
fn confOk? c: Float64 -> Bool
  (and (> c 0.0) (< c 1.0))

fn countsOk? x: Int64 n: Int64 -> Bool
  (and (>= n 1) (and (>= x 0) (<= x n)))

fn wilson x: Int64 n: Int64 conf: Float64 -> (Result (Pair Float64 Float64) String)
  (cond
    ((not (countsOk? x n)) (err "statsRange: need 0 <= x <= n and n >= 1"))
    ((not (confOk? conf)) (err "statsRange: conf must be inside (0,1)"))
    (else
      (let [(nf (int64ToFloat64 n))
            (p (/ (int64ToFloat64 x) nf))
            (z (sp/normalQuantile (- 1.0 (/ (- 1.0 conf) 2.0))))
            (z2 (* z z))
            (denom (+ 1.0 (/ z2 nf)))
            (center (/ (+ p (/ z2 (* 2.0 nf))) denom))
            (half (/ (* z (sqrt (+ (/ (* p (- 1.0 p)) nf) (/ z2 (* (* 4.0 nf) nf))))) denom))]
        (ok (pair (max 0.0 (- center half)) (min 1.0 (+ center half)))))))

fn clopperPearson x: Int64 n: Int64 conf: Float64 -> (Result (Pair Float64 Float64) String)
  (cond
    ((not (countsOk? x n)) (err "statsRange: need 0 <= x <= n and n >= 1"))
    ((not (confOk? conf)) (err "statsRange: conf must be inside (0,1)"))
    (else
      (let [(al (/ (- 1.0 conf) 2.0))
            (xf (int64ToFloat64 x))
            (nf (int64ToFloat64 n))
            (lo (if (= x 0) 0.0 (sp/betaQuantile al xf (+ (- nf xf) 1.0))))
            (hi (if (= x n) 1.0 (sp/betaQuantile (- 1.0 al) (+ xf 1.0) (- nf xf))))]
        (ok (pair lo hi)))))

fn meanCi xs: (List Float64) conf: Float64 -> (Result (Pair Float64 Float64) String)
  (cond
    ((not (confOk? conf)) (err "statsRange: conf must be inside (0,1)"))
    (else
      (match (ds/mean xs)
        ((err e) (err e))
        ((ok m)
          (match (ds/stddev xs)
            ((err e) (err e))
            ((ok s)
              (let [(n (int64ToFloat64 (listLength xs)))
                    (t (sp/studentQuantile (- 1.0 (/ (- 1.0 conf) 2.0)) (- n 1.0)))
                    (h (/ (* t s) (sqrt n)))]
                (ok (pair (- m h) (+ m h))))))))))

schema BootResult
  (:f lo Float64)
  (:f hi Float64)
  (:f estimate Float64)
  (:f rng rg/Rng)

fn ! resampleLoop! src: Bytes n: Int64 out: Bytes i: Int64 r: rg/Rng -> rg/Rng
  (if (>= i n) r
    (let [(p (rg/rngNext r))
          (k (mod (rg/lsr (pairFirst p) 1) n))]
      (do (bytesSetFloat64 out i (bytesGetFloat64 src k))
          (resampleLoop! src n out (+ i 1) (pairSecond p)))))

fn floatsOf b: Bytes i: Int64 n: Int64 -> (List Float64)
  (if (>= i n) (list) (cons (bytesGetFloat64 b i) (floatsOf b (+ i 1) n)))

fn ! statLoop! src: Bytes n: Int64 out: Bytes stat: (fn [(List Float64)] -> Float64) scratch: Bytes k: Int64 total: Int64 r: rg/Rng -> rg/Rng
  (if (>= k total) r
    (let [(r2 (resampleLoop! src n scratch 0 r))]
      (do (bytesSetFloat64 out k (stat (floatsOf scratch 0 n)))
          (statLoop! src n out stat scratch (+ k 1) total r2))))

fn ! bootstrapPercentile xs: (List Float64) stat: (fn [(List Float64)] -> Float64) resamples: Int64 conf: Float64 r: rg/Rng -> (Result BootResult String)
  (cond
    ((listEmpty? xs) (err (ds/statsEmpty)))
    ((< (listLength xs) 2) (err (ds/statsTooFew)))
    ((< resamples 10) (err "statsRange: at least 10 resamples"))
    ((> resamples 1000000) (err "statsRange: at most 1000000 resamples"))
    ((not (confOk? conf)) (err "statsRange: conf must be inside (0,1)"))
    (else
      (let [(n (listLength xs))
            (src (bytesAlloc (* n 8)))
            (_ (fillFloats! src xs 0))
            (out (bytesAlloc (* resamples 8)))
            (scratch (bytesAlloc (* n 8)))
            (r2 (statLoop! src n out stat scratch 0 resamples r))
            (stats (listSort (floatsOf out 0 resamples)))
            (al (/ (- 1.0 conf) 2.0))]
        (match (ds/percentileSorted stats (* 100.0 al))
          ((err e) (err e))
          ((ok lo)
            (match (ds/percentileSorted stats (* 100.0 (- 1.0 al)))
              ((err e) (err e))
              ((ok hi) (ok (BootResult :lo lo :hi hi :estimate (stat xs) :rng r2)))))))))

fn ! fillFloats! b: Bytes xs: (List Float64) i: Int64 -> Unit
  (match (listHead xs)
    ((none) ())
    ((some v) (do (bytesSetFloat64 b i v) (fillFloats! b (optionOr (listTail xs) (list)) (+ i 1)))))

fn twoProportionSampleSize p1: Float64 p2: Float64 alpha: Float64 power: Float64 -> (Result Int64 String)
  (cond
    ((or (isNan? p1) (or (isNan? p2) (or (isNan? alpha) (isNan? power)))) (err "statsRange: an argument is NaN"))
    ((or (<= p1 0.0) (or (>= p1 1.0) (or (<= p2 0.0) (>= p2 1.0)))) (err "statsRange: proportions must be inside (0,1)"))
    ((= p1 p2) (err "statsRange: the proportions are equal, no sample size detects a zero difference"))
    ((or (not (confOk? alpha)) (not (confOk? power))) (err "statsRange: alpha and power must be inside (0,1)"))
    (else
      (let [(za (sp/normalQuantile (- 1.0 (/ alpha 2.0))))
            (zb (sp/normalQuantile power))
            (pb (/ (+ p1 p2) 2.0))
            (a (* za (sqrt (* (* 2.0 pb) (- 1.0 pb)))))
            (b (* zb (sqrt (+ (* p1 (- 1.0 p1)) (* p2 (- 1.0 p2))))))
            (n (/ (* (+ a b) (+ a b)) (* (- p1 p2) (- p1 p2))))]
        (match (float64ToInt64 (ceil (- n 1.0e-9)))
          ((some k) (ok k))
          ((none) (err "statsRange: the sample size does not fit in Int64"))))))
