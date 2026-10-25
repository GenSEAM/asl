(module mapArena
  :x [main]
  :i [])

fn fill i: Int64 n: Int64 m: (Map Int64 Int64) -> (Map Int64 Int64)
  (if (>= i n) m (fill (+ i 1) n (mapSet m (mod (* i 7919) 1009) i)))

fn view m: (Map Int64 Int64) -> Int64
  (fold (fn [(a Int64) (p (Pair Int64 Int64))] -> Int64 (mod (+ (* a 31) (+ (* 7 (pairFirst p)) (pairSecond p))) 1000000007)) (mapSize m) (mapPairs m))

fn ! main args: (List String) -> (Result Int64 String)
  (let [(outer (fill 0 300 (mapEmpty)))
        (r (arenaRun (fn [] -> Int64 (view (fill 300 600 outer)))))
        (outer2 (fill 0 500 outer))]
    (do (println (str "r " r " outer " (view outer) " outer2 " (view outer2)))
        (ok 0)))
