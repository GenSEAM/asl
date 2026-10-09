(module asl-forms/similarity :x [ratio getCloseMatches nearestSymbols] :i [])


(schema MatchBlock (:f i Int64) (:f j Int64) (:f size Int64))

(schema Scored (:f score Float64) (:f text String))


fn runLength a: Bytes b: Bytes i: Int64 j: Int64 ahi: Int64 bhi: Int64 k: Int64 -> Int64
  (if (and (< (+ i k) ahi) (< (+ j k) bhi) (= (bytesGet a (+ i k)) (bytesGet b (+ j k))))
    (runLength a b i j ahi bhi (+ k 1))
    k)

fn scanJ a: Bytes b: Bytes i: Int64 j: Int64 ahi: Int64 bhi: Int64 best: MatchBlock -> MatchBlock
  (if (>= j bhi)
    best
    (let [(k (runLength a b i j ahi bhi 0))]
      (scanJ a b i (+ j 1) ahi bhi (if (> k best.size) (MatchBlock :i i :j j :size k) best))))

fn longestMatch a: Bytes b: Bytes i: Int64 ahi: Int64 blo: Int64 bhi: Int64 best: MatchBlock -> MatchBlock
  (if (>= i ahi)
    best
    (longestMatch a b (+ i 1) ahi blo bhi (scanJ a b i blo ahi bhi best)))

fn matchedCount a: Bytes b: Bytes alo: Int64 ahi: Int64 blo: Int64 bhi: Int64 -> Int64
  (if (or (>= alo ahi) (>= blo bhi))
    0
    (let [(m (longestMatch a b alo ahi blo bhi (MatchBlock :i alo :j blo :size 0)))
          (k m.size)]
      (if (= k 0)
        0
        (+ k
           (matchedCount a b alo m.i blo m.j)
           (matchedCount a b (+ m.i k) ahi (+ m.j k) bhi)))))

fn ratio a: String b: String -> Float64
  (let [(la (stringLength a))
        (lb (stringLength b))]
    (if (= (+ la lb) 0)
      1.0
      (/ (* 2.0 (int64ToFloat64 (matchedCount (stringToBytes a) (stringToBytes b) 0 la 0 lb))) (int64ToFloat64 (+ la lb)))))

fn better? x: Scored y: Scored -> Bool
  (or (> x.score y.score) (and (= x.score y.score) (> x.text y.text)))

fn insertScored item: Scored items: (List Scored) -> (List Scored)
  (mt (listHead items)
    ((none) (list item))
    ((some hd) (if (better? item hd) (cons item items) (cons hd (insertScored item (optionOr (listTail items) (list)))))))

fn getCloseMatches word: String possibilities: (List String) n: Int64 cutoff: Float64 -> (List String)
  (let [(scored (fold (fn [(acc (List Scored)) (x String)] -> (List Scored)
                        (let [(r (ratio x word))]
                          (if (>= r cutoff) (insertScored (Scored :score r :text x) acc) acc)))
                      (list)
                      possibilities))]
    (map (fn [(s Scored)] -> String s.text) (listTake scored n)))

fn dedupSorted items: (List String) acc: (List String) -> (List String)
  (mt (listHead items)
    ((none) (listReverse acc))
    ((some x)
      (dedupSorted (optionOr (listTail items) (list)) (if (and (not (listEmpty? acc)) (= (optionOr (listHead acc) "") x)) acc (cons x acc)))))

fn fillNear names: (List String) low: String near: (List String) k: Int64 -> (List String)
  (mt (listHead names)
    ((none) near)
    ((some nm)
      (if (>= (listLength near) k)
        near
        (let [(lowNm (stringLower nm))
              (take (and (not (listContains? near nm)) (or (stringContains? lowNm low) (stringContains? low lowNm))))]
          (fillNear (optionOr (listTail names) (list)) low (if take (listAppend near (list nm)) near) k)))))

fn nearestSymbols sym: String names: (List String) k: Int64 -> (List String)
  (let [(sorted (dedupSorted (listSort names) (list)))
        (near (getCloseMatches sym sorted k 0.5))]
    (listTake (fillNear sorted (stringLower sym) near k) k))
