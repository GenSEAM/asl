(module gcUntraced
  :x [main]
  :i [])

(schema Cell
  (:f a Int64)
  (:f b Int64))

fn build i: Int64 n: Int64 acc: (List Cell) -> (List Cell)
  (if (= i n) acc (build (+ i 1) n (cons (Cell :a i :b (* i 3)) acc)))

fn ! main args: (List String) -> (Result Int64 String)
  (let [(cells (build 0 1000000 (list)))
        (total (fold (fn [(s Int64) (c Cell)] -> Int64 (+ s (+ c.a c.b))) 0 cells))]
    (do (println (str total " " (listLength cells)))
        (ok 0)))
