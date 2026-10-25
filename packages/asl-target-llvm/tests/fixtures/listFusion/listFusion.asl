(module listFusion
  :x [main]
  :i [])

fn pushBatch i: Int64 cap: Int64 start: Int64 acc: (List Int64) -> (List Int64)
  (if (= i cap) acc (pushBatch (+ i 1) cap start (cons (+ start i) acc)))

fn pushEvens i: Int64 n: Int64 acc: (List Int64) -> (List Int64)
  (if (= i n) acc
    (if (= (mod i 2) 0) (pushEvens (+ i 1) n (cons (* i 3) acc)) (pushEvens (+ i 1) n acc)))

fn drainSum items: (List Int64) acc: Int64 -> Int64
  (match (listHead items)
    ((none) acc)
    ((some v) (drainSum (optionOr (listTail items) (list)) (+ acc v))))

fn maxOf items: (List Int64) best: Int64 -> Int64
  (match (listHead items)
    ((none) best)
    ((some v) (maxOf (optionOr (listTail items) (list)) (if (> v best) v best))))

fn lastOf items: (List Int64) prev: Int64 -> Int64
  (match (listHead items)
    ((none) prev)
    ((some v) (lastOf (optionOr (listTail items) (list)) v)))

fn drainDiv items: (List Int64) acc: Int64 -> Int64
  (match (listHead items)
    ((none) acc)
    ((some v) (drainDiv (optionOr (listTail items) (list)) (+ acc (/ 1000000 v)))))

fn firstAbove items: (List Int64) k: Int64 -> Int64
  (match (listHead items)
    ((none) -1)
    ((some v) (if (> v k) v (firstAbove (optionOr (listTail items) (list)) k))))

fn fuseRing i: Int64 total: Int64 cap: Int64 produced: Int64 acc: Int64 -> Int64
  (if (= i total) acc
    (let [(batch (listReverse (pushBatch 0 cap produced (list))))
          (sum (drainSum batch 0))]
      (fuseRing (+ i 1) total cap (+ produced cap) (+ acc sum))))

fn fuseEvens n: Int64 -> Int64
  (maxOf (listReverse (pushEvens 0 n (list))) -1)

fn fuseLast n: Int64 -> Int64
  (lastOf (listReverse (pushBatch 0 n 7 (list))) -1)

fn fuseEmpty n: Int64 -> Int64
  (drainSum (listReverse (pushBatch 0 0 n (list))) 42)

fn keepTwice n: Int64 -> Int64
  (let [(b (listReverse (pushBatch 0 n 1 (list))))
        (s (drainSum b 0))]
    (+ s (listLength b)))

fn keepBuilt n: Int64 -> Int64
  (let [(xs (pushBatch 0 n 1 (list)))
        (s (drainSum (listReverse xs) 0))]
    (+ s (lastOf xs -1)))

fn keepTrap n: Int64 -> Int64
  (drainDiv (listReverse (pushBatch 0 n 1 (list))) 0)

fn keepNoReverse n: Int64 -> Int64
  (lastOf (pushBatch 0 n 7 (list)) -1)

fn keepEarly n: Int64 -> Int64
  (firstAbove (listReverse (pushBatch 0 n 1 (list))) 5)

fn helper x: Int64 -> Int64
  (+ x 1)

fn pushCall i: Int64 n: Int64 acc: (List Int64) -> (List Int64)
  (if (= i n) acc (pushCall (+ i 1) n (cons (helper i) acc)))

fn drainCall items: (List Int64) acc: Int64 -> Int64
  (match (listHead items)
    ((none) acc)
    ((some v) (drainCall (optionOr (listTail items) (list)) (+ acc (helper v)))))

fn gen i: Int64 k: Int64 acc: (List Int64) -> (List Int64)
  (if (< i 4) acc (gen (/ i 2) k (cons (/ k (/ i 4)) acc)))

fn divAll items: (List Int64) s: Int64 -> Int64
  (match (listHead items)
    ((none) s)
    ((some v) (divAll (optionOr (listTail items) (list)) (/ s v))))

fn pushWrap i: Int64 n: Int64 start: Int64 acc: (List Int64) -> (List Int64)
  (if (= i n) acc (pushWrap (+ i 1) n start (cons (match (some acc) ((some _) (+ start i)) ((none) 0)) acc)))

fn pushDup i: Int64 n: Int64 acc: (List Int64) other: (List Int64) -> (List Int64)
  (if (= i n) acc (pushDup (+ i 1) n (cons i acc) acc))

fn forever x: Int64 acc: (List Int64) -> (List Int64)
  (if (< x 0) acc (forever x (cons x acc)))

fn keepSeeded n: Int64 -> Int64
  (drainSum (listReverse (pushBatch 0 n 1 (list 5))) 0)

fn keepCallP n: Int64 -> Int64
  (drainSum (listReverse (pushCall 0 n (list))) 0)

fn keepCallC n: Int64 -> Int64
  (drainCall (listReverse (pushBatch 0 n 1 (list))) 0)

fn keepBetween n: Int64 -> Int64
  (let [(xs (listReverse (pushBatch 0 n 1 (list))))
        (d (/ 100 n))
        (s (drainSum xs d))]
    s)

fn keepSkipTrap n: Int64 -> Int64
  (drainSum (listReverse (pushEvens 0 n (list))) 0)

fn keepTwoCodes n: Int64 -> Int64
  (divAll (listReverse (gen n 1000 (list))) 1000000000000000000)

fn keepAccUsed n: Int64 -> Int64
  (drainSum (listReverse (pushWrap 0 n 1 (list))) 0)

fn keepAccOther n: Int64 -> Int64
  (drainSum (listReverse (pushDup 0 n (list) (list))) 0)

fn fuseEndless x: Int64 -> Int64
  (drainSum (listReverse (forever x (list))) 0)

fn ! main args: (List String) -> (Result Unit String)
  (if (= (optionOr (listHead args) "") "endless")
    (do (println (str (fuseEndless 4611686018427387904)))
        (ok ()))
    (do (println (str (fuseRing 0 100 1000 0 0) " " (fuseEvens 100001) " " (fuseLast 100000) " " (fuseEmpty 9)))
        (println (str (keepTwice 1000) " " (keepBuilt 1000) " " (keepTrap 1000) " " (keepNoReverse 1000) " " (keepEarly 1000)))
        (println (str (keepSeeded 1000) " " (keepCallP 1000) " " (keepCallC 1000) " " (keepBetween 1000) " " (keepSkipTrap 1000) " " (keepTwoCodes 64) " " (keepAccUsed 1000) " " (keepAccOther 1000)))
        (ok ())))
