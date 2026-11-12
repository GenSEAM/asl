(module asl-stats/agree
  :x [ranks spearman pearson cohenKappa weightedKappa]
  :i [(asl-stats/describe :a ds)])

; (:m :ref workspace-20261031-experimentStats :do "agreement and rank statistics: ranks are 1-based average ranks so ties share the mean of the ranks they span; spearman is the Pearson correlation of the average ranks; kappa takes a square table of non-negative counts, rows are rater A, columns rater B; weighted kappa uses linear or quadratic agreement weights; empty or one-element input is statsEmpty or statsTooFew, a constant series or a chance agreement of 1 is statsConstant")
fn ! rankLoop! sorted: (List (Pair Int64 Float64)) out: Bytes i: Int64 n: Int64 -> Unit
  (if (>= i n) ()
    (let [(v (pairSecond (optionOr (listGet sorted i) (pair 0 0.0))))
          (j (tieEnd sorted v (+ i 1) n))
          (r (/ (+ (int64ToFloat64 (+ i 1)) (int64ToFloat64 j)) 2.0))]
      (do (setRange! sorted out i j r)
          (rankLoop! sorted out j n))))

fn tieEnd sorted: (List (Pair Int64 Float64)) v: Float64 j: Int64 n: Int64 -> Int64
  (if (and (< j n) (= (pairSecond (optionOr (listGet sorted j) (pair 0 0.0))) v)) (tieEnd sorted v (+ j 1) n) j)

fn ! setRange! sorted: (List (Pair Int64 Float64)) out: Bytes i: Int64 j: Int64 r: Float64 -> Unit
  (if (>= i j) ()
    (do (bytesSetFloat64 out (pairFirst (optionOr (listGet sorted i) (pair 0 0.0))) r)
        (setRange! sorted out (+ i 1) j r)))

fn floatsOf b: Bytes i: Int64 n: Int64 -> (List Float64)
  (if (>= i n) (list) (cons (bytesGetFloat64 b i) (floatsOf b (+ i 1) n)))

fn indexedList xs: (List Float64) i: Int64 -> (List (Pair Int64 Float64))
  (match (listHead xs)
    ((none) (list))
    ((some v) (cons (pair i v) (indexedList (optionOr (listTail xs) (list)) (+ i 1)))))

; (:m :ref STATSLOWS-LOWS2 :do "one finite check for the package: describe.asl#finiteValue?")
fn finiteAll? xs: (List Float64) -> Bool
  (listAll? ds/finiteValue? xs)

fn ! ranks xs: (List Float64) -> (Result (List Float64) String)
  (if (not (finiteAll? xs)) (err "statsRange: a value is NaN or infinite")
    (let [(n (listLength xs))
          (out (bytesAlloc (* (max n 1) 8)))
          (sorted (listSortBy (fn [(p (Pair Int64 Float64))] -> Float64 (pairSecond p)) (indexedList xs 0)))
          (_ (rankLoop! sorted out 0 n))]
      (ok (floatsOf out 0 n))))

fn pearson xs: (List Float64) ys: (List Float64) -> (Result Float64 String)
  (cond
    ((or (listEmpty? xs) (listEmpty? ys)) (err (ds/statsEmpty)))
    ((!= (listLength xs) (listLength ys)) (err "statsRange: the two series differ in length"))
    ((< (listLength xs) 2) (err (ds/statsTooFew)))
    ((not (and (finiteAll? xs) (finiteAll? ys))) (err "statsRange: a value is NaN or infinite"))
    (else
      (match (ds/mean xs)
        ((err e) (err e))
        ((ok mx)
          (match (ds/mean ys)
            ((err e) (err e))
            ((ok my)
              (let [(dx (map (fn [(x Float64)] -> Float64 (- x mx)) xs))
                    (dy (map (fn [(y Float64)] -> Float64 (- y my)) ys))
                    (sxy (ds/sumKahan (map (fn [(p (Pair Float64 Float64))] -> Float64 (* (pairFirst p) (pairSecond p))) (zip dx dy))))
                    (sxx (ds/sumKahan (map (fn [(a Float64)] -> Float64 (* a a)) dx)))
                    (syy (ds/sumKahan (map (fn [(a Float64)] -> Float64 (* a a)) dy)))]
                (if (or (= sxx 0.0) (= syy 0.0)) (err "statsConstant: a series has no spread")
                  (ok (/ sxy (sqrt (* sxx syy))))))))))))

fn ! spearman xs: (List Float64) ys: (List Float64) -> (Result Float64 String)
  (cond
    ((or (listEmpty? xs) (listEmpty? ys)) (err (ds/statsEmpty)))
    ((!= (listLength xs) (listLength ys)) (err "statsRange: the two series differ in length"))
    (else
      (match (ranks xs)
        ((err e) (err e))
        ((ok rx)
          (match (ranks ys)
            ((err e) (err e))
            ((ok ry) (pearson rx ry)))))))

fn tableOk? t: (List (List Int64)) -> Bool
  (let [(k (listLength t))]
    (and (>= k 2) (listAll? (fn [(row (List Int64))] -> Bool (and (= (listLength row) k) (listAll? (fn [(c Int64)] -> Bool (>= c 0)) row))) t)))

fn rowSums t: (List (List Int64)) -> (List Float64)
  (map (fn [(row (List Int64))] -> Float64 (int64ToFloat64 (fold (fn [(a Int64) (b Int64)] -> Int64 (+ a b)) 0 row))) t)

fn colSums t: (List (List Int64)) k: Int64 -> (List Float64)
  (map (fn [(j Int64)] -> Float64 (int64ToFloat64 (fold (fn [(a Int64) (row (List Int64))] -> Int64 (+ a (optionOr (listGet row j) 0))) 0 t))) (range 0 k))

fn cell t: (List (List Int64)) i: Int64 j: Int64 -> Float64
  (int64ToFloat64 (optionOr (listGet (optionOr (listGet t i) (list)) j) 0))

fn weightAt kind: String i: Int64 j: Int64 k: Int64 -> Float64
  (let [(d (/ (int64ToFloat64 (abs (- i j))) (int64ToFloat64 (- k 1))))]
    (cond
      ((= kind "linear") (- 1.0 d))
      ((= kind "quadratic") (- 1.0 (* d d)))
      (else (if (= i j) 1.0 0.0))))

fn weightedSum f: (fn [Int64 Int64] -> Float64) k: Int64 -> Float64
  (ds/sumKahan (listFlatMap (fn [(i Int64)] -> (List Float64) (map (fn [(j Int64)] -> Float64 (f i j)) (range 0 k))) (range 0 k)))

fn weightedKappa t: (List (List Int64)) kind: String -> (Result Float64 String)
  (cond
    ((not (tableOk? t)) (err "statsRange: the table must be square, at least 2x2, with non-negative counts"))
    ((not (or (= kind "none") (or (= kind "linear") (= kind "quadratic")))) (err "statsRange: weights must be none, linear or quadratic"))
    (else
      (let [(k (listLength t))
            (rs (rowSums t))
            (cs (colSums t k))
            (total (ds/sumKahan rs))]
        (if (= total 0.0) (err (ds/statsEmpty))
          (let [(po (/ (weightedSum (fn [(i Int64) (j Int64)] -> Float64 (* (weightAt kind i j k) (cell t i j))) k) total))
                (pe (/ (weightedSum (fn [(i Int64) (j Int64)] -> Float64 (* (weightAt kind i j k) (* (optionOr (listGet rs i) 0.0) (optionOr (listGet cs j) 0.0)))) k) (* total total)))]
            (if (= pe 1.0) (err "statsConstant: chance agreement is 1, kappa is undefined")
              (ok (/ (- po pe) (- 1.0 pe)))))))))

fn cohenKappa t: (List (List Int64)) -> (Result Float64 String)
  (weightedKappa t "none")
