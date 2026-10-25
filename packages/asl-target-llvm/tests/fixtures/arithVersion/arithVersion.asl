(module arithVersion
  :x [main]
  :i [])

fn sumAffine i: Int64 n: Int64 k: Int64 acc: Int64 -> Int64
  (if (= i n) acc (sumAffine (+ i 1) n k (+ acc (+ (* i 3) k))))

fn hashLoop i: Int64 n: Int64 acc: Int64 -> Int64
  (if (= i n) acc (hashLoop (+ i 1) n (mod (+ (* acc 31) i) 1000000007)))

fn squares i: Int64 n: Int64 acc: Int64 -> Int64
  (if (= i n) acc (squares (+ i 1) n (+ (* acc acc) i)))

fn stepTwo i: Int64 n: Int64 acc: Int64 -> Int64
  (if (= i n) acc (stepTwo (+ i 2) n (+ acc i)))

fn pushBatch i: Int64 cap: Int64 start: Int64 acc: (List Int64) -> (List Int64)
  (if (= i cap) acc (pushBatch (+ i 1) cap start (cons (+ start i) acc)))

fn drainSum items: (List Int64) acc: Int64 -> Int64
  (match (listHead items)
    ((none) acc)
    ((some v) (drainSum (optionOr (listTail items) (list)) (+ acc v))))

fn ringRounds i: Int64 total: Int64 cap: Int64 produced: Int64 acc: Int64 -> Int64
  (if (= i total) acc
    (let [(batch (listReverse (pushBatch 0 cap produced (list))))
          (sum (drainSum batch 0))]
      (ringRounds (+ i 1) total cap (+ produced cap) (+ acc sum))))

fn line label: String v: Int64 -> Unit
  (println (str label " " (stringFromInt64 v)))

fn ! run which: String -> Unit
  (cond
    ((= which "ok") (do (line "affine" (sumAffine 0 100000 7 0))
                        (line "affineNeg" (sumAffine -50000 50000 -9 -5))
                        (line "affineEmpty" (sumAffine 9 9 1 3))
                        (line "affineBigAcc" (sumAffine 0 1000 1 4611686018427387904))
                        (line "hash" (hashLoop 0 100000 0))
                        (line "hashBigStart" (hashLoop 0 1000 200000000000000000))
                        (line "squares" (squares 0 5 1))
                        (line "stepTwo" (stepTwo 0 100000 0))
                        (line "accUnder" (sumAffine 0 100 -1 -9223372036854775700))
                        (line "ring" (ringRounds 0 100 1000 0 0))))
    ((= which "accOver") (line "accOver" (sumAffine 0 100 1 9223372036854775700)))
    ((= which "termOver") (line "termOver" (sumAffine 0 100 9223372036854775800 0)))
    ((= which "squareOver") (line "squareOver" (squares 0 10 3)))
    ((= which "tripOver") (line "tripOver" (sumAffine 0 7000000 1099511627776 2305843009213693952)))
    ((= which "backward") (line "backward" (sumAffine 5 3 1 0)))
    (else (line "unknown" 0)))

fn ! main args: (List String) -> (Result Unit String)
  (do (run (optionOr (listHead args) "ok"))
      (ok ()))
