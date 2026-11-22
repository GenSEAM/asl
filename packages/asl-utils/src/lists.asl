(module asl-utils/lists
  :x [binarySearch lowerBound windows groupAdjacent dedupSorted]
  :i [])

; (:m :ref SORTED-LISTS :do "sorted-list helpers: binarySearch and lowerBound probe by index through listGet, windows slices by index, groupAdjacent and dedupSorted walk the list once; every loop is tail-recursive so a 100000-element list does not grow the stack")

fn bsLoop xs: (List Int64) x: Int64 lo: Int64 hi: Int64 -> (Option Int64)
  (if (> lo hi) none
    (let [mid (+ lo (/ (- hi lo) 2))]
      (match (listGet xs mid)
        ((none) none)
        ((some v)
          (cond
            ((= v x) (some mid))
            ((< v x) (bsLoop xs x (+ mid 1) hi))
            (else (bsLoop xs x lo (- mid 1))))))))

fn binarySearch xs: (List Int64) x: Int64 -> (Option Int64)
  (bsLoop xs x 0 (- (listLength xs) 1))

fn lbLoop xs: (List Int64) x: Int64 lo: Int64 hi: Int64 -> Int64
  (if (>= lo hi) lo
    (let [mid (+ lo (/ (- hi lo) 2))]
      (match (listGet xs mid)
        ((none) lo)
        ((some v) (if (< v x) (lbLoop xs x (+ mid 1) hi) (lbLoop xs x lo mid))))))

fn lowerBound xs: (List Int64) x: Int64 -> Int64
  (lbLoop xs x 0 (listLength xs))

fn windowsFrom xs: (List T) n: Int64 i: Int64 len: Int64 acc: (List (List T)) -> (List (List T))
  (if (> (+ i n) len) (listReverse acc)
    (match (listSlice xs i (+ i n))
      ((none) (listReverse acc))
      ((some w) (windowsFrom xs n (+ i 1) len (cons w acc)))))

fn windows xs: (List T) n: Int64 -> (List (List T))
  (if (<= n 0) (list) (windowsFrom xs n 0 (listLength xs) (list)))

fn gaLoop xs: (List T) key: (fn [T] -> K) cur: (List T) curKey: (Option K) acc: (List (List T)) -> (List (List T))
  (if (listEmpty? xs)
    (listReverse (if (listEmpty? cur) acc (cons (listReverse cur) acc)))
    (let [h (match (listHead xs) ((some v) v))
          t (match (listTail xs) ((some v) v))
          k (key h)]
      (if (match curKey ((some ck) (= ck k)) ((none) false))
        (gaLoop t key (cons h cur) curKey acc)
        (gaLoop t key (list h) (some k) (if (listEmpty? cur) acc (cons (listReverse cur) acc))))))

fn groupAdjacent xs: (List T) key: (fn [T] -> K) -> (List (List T))
  (gaLoop xs key (list) none (list))

fn ddLoop xs: (List T) last: (Option T) acc: (List T) -> (List T)
  (if (listEmpty? xs) (listReverse acc)
    (let [h (match (listHead xs) ((some v) v))
          t (match (listTail xs) ((some v) v))]
      (if (match last ((some l) (= l h)) ((none) false))
        (ddLoop t last acc)
        (ddLoop t (some h) (cons h acc)))))

fn dedupSorted xs: (List T) -> (List T)
  (ddLoop xs none (list))
