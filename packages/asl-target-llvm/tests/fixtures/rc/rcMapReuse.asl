(module rcMapReuse
  :x [main]
  :i [])

fn keyAt i: Int64 -> Int64
  (mod (* i 7919) 100003)

fn fill i: Int64 n: Int64 m: (Map Int64 Int64) -> (Map Int64 Int64)
  (if (>= i n) m (fill (+ i 1) n (mapSet m (keyAt i) i)))

fn bump i: Int64 n: Int64 m: (Map Int64 Int64) -> (Map Int64 Int64)
  (if (>= i n) m (bump (+ i 1) n (mapSet m (keyAt i) (+ (mapGetOr m (keyAt i) 0) 1))))

fn present i: Int64 n: Int64 m: (Map Int64 Int64) acc: Int64 -> Int64
  (if (>= i n) acc (present (+ i 1) n m (if (mapHas? m (keyAt i)) (+ acc 1) acc)))

fn total i: Int64 n: Int64 m: (Map Int64 Int64) acc: Int64 -> Int64
  (if (>= i n) acc (total (+ i 1) n m (+ acc (mapGetOr m (keyAt i) 0))))

fn ! main args: (List String) -> (Result Int64 String)
  (let [(m1 (fill 0 3000 (mapEmpty)))
        (snap m1)
        (m2 (fill 3000 4000 m1))
        (m3 (bump 0 1000 m2))]
    (do (println (str (mapSize snap) " " (present 3000 4000 snap 0) " " (total 0 3000 snap 0) " "
                      (mapSize m2) " " (present 3000 4000 m2 0) " " (total 0 1000 m2 0) " "
                      (mapSize m3) " " (total 0 1000 m3 0)))
        (ok 0)))
