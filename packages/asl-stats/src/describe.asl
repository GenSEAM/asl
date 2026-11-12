(module asl-stats/describe
  :x [sumKahan mean variance popVariance stddev median percentile percentileSorted percentileOf mad robustZ cohenD hedgesG statsEmpty statsTooFew]
  :i [])

; (:m :ref workspace-20261031-experimentStats :do "every statistic returns (Result Float64 String): empty input is statsEmpty, a sample statistic with one value is statsTooFew, a zero spread where one is divided by is statsConstant, a bad argument is statsRange; sums are Neumaier compensated; variance is the sample (n-1) variance unless called popVariance; percentile is linear interpolation between order statistics (R type 7)")
fn statsEmpty -> String
  "statsEmpty: no values"

fn statsTooFew -> String
  "statsTooFew: at least two values are needed"

fn ! neumaier! xs: (List Float64) s: Float64 c: Float64 -> Float64
  (match (listHead xs)
    ((none) (+ s c))
    ((some x)
      (let [(t (+ s x))
            (c2 (if (>= (abs s) (abs x)) (+ c (+ (- s t) x)) (+ c (+ (- x t) s))))]
        (neumaier! (optionOr (listTail xs) (list)) t c2))))

fn sumKahan xs: (List Float64) -> Float64
  (neumaier! xs 0.0 0.0)

fn mean xs: (List Float64) -> (Result Float64 String)
  (if (listEmpty? xs) (err (statsEmpty))
    (ok (/ (sumKahan xs) (int64ToFloat64 (listLength xs)))))

fn squares xs: (List Float64) m: Float64 -> (List Float64)
  (map (fn [(x Float64)] -> Float64 (* (- x m) (- x m))) xs)

fn popVariance xs: (List Float64) -> (Result Float64 String)
  (match (mean xs)
    ((err e) (err e))
    ((ok m) (ok (/ (sumKahan (squares xs m)) (int64ToFloat64 (listLength xs))))))

fn variance xs: (List Float64) -> (Result Float64 String)
  (cond
    ((listEmpty? xs) (err (statsEmpty)))
    ((< (listLength xs) 2) (err (statsTooFew)))
    (else
      (match (mean xs)
        ((err e) (err e))
        ((ok m) (ok (/ (sumKahan (squares xs m)) (int64ToFloat64 (- (listLength xs) 1))))))))

fn stddev xs: (List Float64) -> (Result Float64 String)
  (match (variance xs)
    ((err e) (err e))
    ((ok v) (ok (sqrt v))))

fn percentileSorted sorted: (List Float64) p: Float64 -> (Result Float64 String)
  (cond
    ((listEmpty? sorted) (err (statsEmpty)))
    ((or (< p 0.0) (> p 100.0)) (err "statsRange: percentile must be 0..100"))
    (else
      (let [(n (listLength sorted))
            (h (/ (* (int64ToFloat64 (- n 1)) p) 100.0))
            (lo (optionOr (float64ToInt64 (floor h)) 0))
            (hi (min (- n 1) (+ lo 1)))
            (a (optionOr (listGet sorted lo) 0.0))
            (b (optionOr (listGet sorted hi) 0.0))]
        (ok (+ a (* (- h (int64ToFloat64 lo)) (- b a)))))))

fn percentile xs: (List Float64) p: Float64 -> (Result Float64 String)
  (percentileSorted (listSort xs) p)

fn median xs: (List Float64) -> (Result Float64 String)
  (percentile xs 50.0)

fn mad xs: (List Float64) -> (Result Float64 String)
  (match (median xs)
    ((err e) (err e))
    ((ok m) (median (map (fn [(x Float64)] -> Float64 (abs (- x m))) xs))))

fn robustZ x: Float64 xs: (List Float64) -> (Result Float64 String)
  (match (median xs)
    ((err e) (err e))
    ((ok m)
      (match (mad xs)
        ((err e) (err e))
        ((ok d)
          (if (= d 0.0) (err "statsConstant: the median absolute deviation is zero")
            (ok (/ (- x m) (* 1.482602218505602 d))))))))

fn percentileOf xs: (List Float64) v: Float64 -> (Result Float64 String)
  (if (listEmpty? xs) (err (statsEmpty))
    (let [(below (listLength (filter (fn [(x Float64)] -> Bool (< x v)) xs)))
          (same (listLength (filter (fn [(x Float64)] -> Bool (= x v)) xs)))]
      (ok (/ (* 100.0 (+ (int64ToFloat64 below) (* 0.5 (int64ToFloat64 same)))) (int64ToFloat64 (listLength xs))))))

fn cohenD a: (List Float64) b: (List Float64) -> (Result Float64 String)
  (match (variance a)
    ((err e) (err e))
    ((ok va)
      (match (variance b)
        ((err e) (err e))
        ((ok vb)
          (let [(na (int64ToFloat64 (listLength a)))
                (nb (int64ToFloat64 (listLength b)))
                (sp (sqrt (/ (+ (* (- na 1.0) va) (* (- nb 1.0) vb)) (- (+ na nb) 2.0))))]
            (if (= sp 0.0) (err "statsConstant: pooled standard deviation is zero")
              (ok (/ (- (/ (sumKahan a) na) (/ (sumKahan b) nb)) sp))))))))

fn hedgesG a: (List Float64) b: (List Float64) -> (Result Float64 String)
  (match (cohenD a b)
    ((err e) (err e))
    ((ok d)
      (let [(n (int64ToFloat64 (+ (listLength a) (listLength b))))]
        (ok (* d (- 1.0 (/ 3.0 (- (* 4.0 n) 9.0))))))))
