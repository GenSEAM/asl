(module mapUnique
  :x [main]
  :i [])

fn keyAt i: Int64 -> Int64
  (mod (* i 7919) 100003)

fn fill i: Int64 n: Int64 m: (Map Int64 Int64) -> (Map Int64 Int64)
  (if (>= i n) m (fill (+ i 1) n (mapSet m (keyAt i) i)))

fn bump i: Int64 n: Int64 m: (Map Int64 Int64) -> (Map Int64 Int64)
  (if (>= i n) m (bump (+ i 1) n (mapSet m (keyAt i) (+ (mapGetOr m (keyAt i) 0) 1000000))))

fn drop i: Int64 n: Int64 m: (Map Int64 Int64) -> (Map Int64 Int64)
  (if (>= i n) m (drop (+ i 1) n (mapRemove m (keyAt i))))

fn total i: Int64 n: Int64 m: (Map Int64 Int64) acc: Int64 -> Int64
  (if (>= i n) acc (total (+ i 1) n m (+ acc (mapGetOr m (keyAt i) 0))))

fn ! main args: (List String) -> (Result Int64 String)
  (let [(m (drop 0 5000 (bump 0 10000 (fill 0 10000 (mapEmpty)))))]
    (do (println (str (mapSize m) " " (total 0 10000 m 0)))
        (ok 0)))
