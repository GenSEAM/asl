(module asl-stats/order
  :x [sortF64 quantileF64 quantileSortedF64 quantilesF64 selectF64 hasNanF64]
  :i [])

; (:m :ref NUM-LINALG-STATS :do "F64Array order statistics in Bytes scratch: sortF64 is a stable bottom-up merge sort, O(n log n), ascending, NaN last (the order listSort uses); quantile is R type 7, h=(n-1)p and linear interpolation between the order statistics at floor(h) and floor(h)+1, with no interpolation (the order statistic itself) when h is an integer, so infinities at p = 0 or 1 stay infinite; the quantile and select functions refuse NaN input with statsNaN, an empty array with statsEmpty and p outside [0,1] with statsRange, instead of sorting NaN into a number; selectF64 is a three-way quickselect, expected O(n), with the kth smallest 0-based")
fn ! copyIn! b: Bytes a: F64Array i: Int64 n: Int64 -> Bytes
  (if (>= i n) b
    (do (bytesSetFloat64 b i (f64ArrayGet a i))
        (copyIn! b a (+ i 1) n)))

fn ! toBuf a: F64Array -> Bytes
  (copyIn! (bytesAlloc (* 8 (f64ArrayLen a))) a 0 (f64ArrayLen a))

fn ! fromBuf b: Bytes n: Int64 -> F64Array
  (f64ArrayGenerate n (fn [(i Int64)] -> Float64 (bytesGetFloat64 b i)))

fn nan? x: Float64 -> Bool
  (not (= x x))

fn after? x: Float64 y: Float64 -> Bool
  (if (nan? x) (not (nan? y)) (and (not (nan? y)) (> x y)))

fn hasNanF64 a: F64Array -> Bool
  (f64ArrayFold (fn [(acc Bool) (x Float64)] -> Bool (or acc (nan? x))) false a)

fn ! mergeRuns! src: Bytes dst: Bytes lo: Int64 mid: Int64 hi: Int64 i: Int64 j: Int64 k: Int64 -> Int64
  (cond
    ((>= k hi) 0)
    ((>= i mid) (do (bytesSetFloat64 dst k (bytesGetFloat64 src j)) (mergeRuns! src dst lo mid hi i (+ j 1) (+ k 1))))
    ((>= j hi) (do (bytesSetFloat64 dst k (bytesGetFloat64 src i)) (mergeRuns! src dst lo mid hi (+ i 1) j (+ k 1))))
    ((after? (bytesGetFloat64 src i) (bytesGetFloat64 src j))
      (do (bytesSetFloat64 dst k (bytesGetFloat64 src j)) (mergeRuns! src dst lo mid hi i (+ j 1) (+ k 1))))
    (else
      (do (bytesSetFloat64 dst k (bytesGetFloat64 src i)) (mergeRuns! src dst lo mid hi (+ i 1) j (+ k 1)))))

fn ! mergePass! src: Bytes dst: Bytes n: Int64 width: Int64 lo: Int64 -> Int64
  (if (>= lo n) 0
    (let [(mid (min n (+ lo width)))
          (hi (min n (+ lo (* 2 width))))]
      (do (mergeRuns! src dst lo mid hi lo mid lo)
          (mergePass! src dst n width hi))))

fn ! mergeSort! src: Bytes dst: Bytes n: Int64 width: Int64 -> Bytes
  (if (>= width n) src
    (do (mergePass! src dst n width 0)
        (mergeSort! dst src n (* width 2))))

fn ! sortF64 a: F64Array -> F64Array
  (let [(n (f64ArrayLen a))]
    (if (< n 2) a
      (fromBuf (mergeSort! (toBuf a) (bytesAlloc (* 8 n)) n 1) n)))

fn quantileSortedF64 s: F64Array p: Float64 -> (Result Float64 String)
  (let [(n (f64ArrayLen s))]
    (cond
      ((= n 0) (err "statsEmpty: no values"))
      ((not (and (>= p 0.0) (<= p 1.0))) (err "statsRange: p must be in [0,1]"))
      ((hasNanF64 s) (err "statsNaN: input contains NaN"))
      (else
        (let [(h (* (int64ToFloat64 (- n 1)) p))
              (lo (optionOr (float64ToInt64 (floor h)) 0))
              (hi (min (- n 1) (+ lo 1)))
              (a (f64ArrayGet s lo))
              (b (f64ArrayGet s hi))]
          (ok (if (= h (int64ToFloat64 lo)) a (+ a (* (- h (int64ToFloat64 lo)) (- b a)))))))))

fn quantileF64 a: F64Array p: Float64 -> (Result Float64 String)
  (cond
    ((= (f64ArrayLen a) 0) (err "statsEmpty: no values"))
    ((hasNanF64 a) (err "statsNaN: input contains NaN"))
    (else (quantileSortedF64 (sortF64 a) p)))

fn quantilesF64 a: F64Array ps: (List Float64) -> (Result (List Float64) String)
  (cond
    ((= (f64ArrayLen a) 0) (err "statsEmpty: no values"))
    ((hasNanF64 a) (err "statsNaN: input contains NaN"))
    (else
      (let [(s (sortF64 a))]
        (collectQ s ps (list)))))

fn collectQ s: F64Array ps: (List Float64) acc: (List Float64) -> (Result (List Float64) String)
  (match (listHead ps)
    ((none) (ok (listReverse acc)))
    ((some p)
      (match (quantileSortedF64 s p)
        ((err e) (err e))
        ((ok v) (collectQ s (optionOr (listTail ps) (list)) (cons v acc))))))

fn ! swapAt! b: Bytes i: Int64 j: Int64 -> Int64
  (let [(t (bytesGetFloat64 b i))]
    (do (bytesSetFloat64 b i (bytesGetFloat64 b j))
        (bytesSetFloat64 b j t)
        0))

fn ! part3! b: Bytes pivot: Float64 lt: Int64 i: Int64 gt: Int64 -> (Pair Int64 Int64)
  (if (> i gt) (pair lt gt)
    (let [(x (bytesGetFloat64 b i))]
      (cond
        ((< x pivot) (do (swapAt! b lt i) (part3! b pivot (+ lt 1) (+ i 1) gt)))
        ((> x pivot) (do (swapAt! b i gt) (part3! b pivot lt i (- gt 1))))
        (else (part3! b pivot lt (+ i 1) gt)))))

fn ! quickSelect! b: Bytes lo: Int64 hi: Int64 k: Int64 -> Float64
  (if (>= lo hi) (bytesGetFloat64 b k)
    (let [(pivot (bytesGetFloat64 b (+ lo (/ (- hi lo) 2))))
          (r (part3! b pivot lo lo hi))]
      (cond
        ((< k (pairFirst r)) (quickSelect! b lo (- (pairFirst r) 1) k))
        ((> k (pairSecond r)) (quickSelect! b (+ (pairSecond r) 1) hi k))
        (else pivot))))

fn ! selectF64 a: F64Array k: Int64 -> (Result Float64 String)
  (let [(n (f64ArrayLen a))]
    (cond
      ((= n 0) (err "statsEmpty: no values"))
      ((or (< k 0) (>= k n)) (err "statsRange: k must be in [0,n)"))
      ((hasNanF64 a) (err "statsNaN: input contains NaN"))
      (else (ok (quickSelect! (toBuf a) 0 (- n 1) k)))))
