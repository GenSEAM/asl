(module asl-utils/stats
  :x [mean median variance stddev percentile histogram]
  :i [])

fn fmin a: Float64 b: Float64 -> Float64
  (if (< a b) a b)

fn fmax a: Float64 b: Float64 -> Float64
  (if (> a b) a b)

fn sumF xs: (List Float64) -> Float64
  (fold (fn [(acc Float64) (x Float64)] -> Float64 (+ acc x)) 0.0 xs)

fn mean xs: (List Float64) -> (Result Float64 String)
  (if (listEmpty? xs)
    (err "stats: mean of an empty list")
    (ok (/ (sumF xs) (int64ToFloat64 (listLength xs)))))

fn median xs: (List Float64) -> (Result Float64 String)
  (if (listEmpty? xs)
    (err "stats: median of an empty list")
    (let [(s (listSort xs))
          (n (listLength s))
          (mid (/ n 2))]
      (if (= (mod n 2) 0)
        (ok (/ (+ (optionOr (listGet s (- mid 1)) 0.0) (optionOr (listGet s mid) 0.0)) 2.0))
        (ok (optionOr (listGet s mid) 0.0)))))

fn variance xs: (List Float64) -> (Result Float64 String)
  (match (mean xs)
    ((err e) (err e))
    ((ok m)
      (let [(ss (fold (fn [(acc Float64) (x Float64)] -> Float64
                        (let [(d (- x m))] (+ acc (* d d))))
                      0.0 xs))]
        (ok (/ ss (int64ToFloat64 (listLength xs)))))))

fn stddev xs: (List Float64) -> (Result Float64 String)
  (match (variance xs)
    ((err e) (err e))
    ((ok v) (ok (sqrt v))))

fn percentile xs: (List Float64) p: Float64 -> (Result Float64 String)
  (if (listEmpty? xs)
    (err "stats: percentile of an empty list")
    (if (or (< p 0.0) (> p 100.0))
      (err "stats: percentile p must be between 0 and 100")
      (let [(s (listSort xs))
            (n (listLength s))
            (rank (* (/ p 100.0) (int64ToFloat64 (- n 1))))
            (lo (optionOr (float64ToInt64 rank) 0))
            (hi (min (+ lo 1) (- n 1)))
            (frac (- rank (int64ToFloat64 lo)))
            (a (optionOr (listGet s lo) 0.0))
            (b (optionOr (listGet s hi) 0.0))]
        (ok (+ a (* frac (- b a)))))))

fn binOf x: Float64 lo: Float64 width: Float64 bins: Int64 -> Int64
  (if (<= width 0.0)
    0
    (let [(i (optionOr (float64ToInt64 (/ (- x lo) width)) 0))]
      (if (< i 0) 0 (if (>= i bins) (- bins 1) i))))

fn countBin xs: (List Float64) lo: Float64 width: Float64 bins: Int64 i: Int64 -> Int64
  (listCount (fn [(x Float64)] -> Bool (= (binOf x lo width bins) i)) xs)

fn rangeFrom i: Int64 n: Int64 acc: (List Int64) -> (List Int64)
  (if (>= i n) (listReverse acc) (rangeFrom (+ i 1) n (cons i acc)))

fn histogram xs: (List Float64) bins: Int64 -> (Result (List Int64) String)
  (if (listEmpty? xs)
    (err "stats: histogram of an empty list")
    (if (<= bins 0)
      (err "stats: histogram needs at least one bin")
      (let [(x0 (optionOr (listHead xs) 0.0))
            (lo (fold (fn [(a Float64) (x Float64)] -> Float64 (fmin a x)) x0 xs))
            (hi (fold (fn [(a Float64) (x Float64)] -> Float64 (fmax a x)) x0 xs))
            (width (/ (- hi lo) (int64ToFloat64 bins)))]
        (ok (map (fn [(i Int64)] -> Int64 (countBin xs lo width bins i)) (rangeFrom 0 bins (list)))))))
