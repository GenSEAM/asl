(module asl-text/distance :x [levenshtein commonPrefixLength nearest] :i [])

(schema Candidate (:f idx Int64) (:f name String) (:f dist Int64))

fn initialRow c2s: (List String) -> (List Int64)
  (cons 0 (map (fn [p] (+ (pairFirst p) 1)) (enumerate c2s)))

fn min3 a: Int64 b: Int64 c: Int64 -> Int64
  (let [(m (if (<= a b) a b))]
    (if (<= m c) m c))

fn nextRow c1: String c2s: (List String) prevRow: (List Int64) rowIdx: Int64 -> (List Int64)
  (let [(init (pair rowIdx (pair prevRow (cons rowIdx (list)))))]
    (let [(final (fold (fn [st p]
                         (let [(prevLeft (pairFirst st))
                               (prevTail (pairFirst (pairSecond st)))
                               (accRev (pairSecond (pairSecond st)))
                               (pDiag (optionOr (listHead prevTail) 0))
                               (pUp (optionOr (listHead (optionOr (listTail prevTail) (list))) 0))
                               (c2 (pairSecond p))
                               (cost (if (= c1 c2) 0 1))
                               (curr (min3 (+ prevLeft 1) (+ pUp 1) (+ pDiag cost)))]
                           (pair curr (pair (optionOr (listTail prevTail) (list)) (cons curr accRev)))))
                       init
                       (enumerate c2s)))]
      (listReverse (pairSecond (pairSecond final)))))

fn levenshtein a: String b: String -> Int64
  (let [(c1 (stringChars a))
        (c2 (stringChars b))
        (r0 (initialRow c2))]
    (let [(finalRow (fold (fn [row p] (nextRow (pairSecond p) c2 row (+ (pairFirst p) 1))) r0 (enumerate c1)))]
      (optionOr (listLast finalRow) 0)))

fn commonPrefixLength a: String b: String -> Int64
  (let [(ca (stringChars a))
        (cb (stringChars b))]
    (pairSecond (fold (fn [st p]
                        (if (pairFirst st)
                          (let [(i (pairFirst p))
                                (ch (pairSecond p))]
                            (if (= (optionOr (listGet cb i) "") ch)
                              (pair true (+ (pairSecond st) 1))
                              (pair false (pairSecond st))))
                          st))
                      (pair true 0)
                      (enumerate ca))))

fn nearest name: String candidates: (List String) limit: Int64 -> (List String)
  (let [(threshold (max 2 (/ (stringLength name) 3)))
        (scored (map (fn [p] (Candidate :idx (pairFirst p) :name (pairSecond p) :dist (levenshtein name (pairSecond p)))) (enumerate candidates)))]
    (let [(kept (filter (fn [c] (<= c.dist threshold)) scored))]
      (let [(ordered (listSortBy (fn [c] (+ (* c.dist 1000000) c.idx)) kept))]
        (listTake (map (fn [c] c.name) ordered) limit))))
