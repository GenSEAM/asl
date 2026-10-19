(module rcSmall
  :x [main]
  :i [])

fn pick i: Int64 -> (List Int64)
  (if (> i 5000000) (list i) (list))

fn valueOr o: (Option Int64) -> Int64
  (mt o ((some x) x) ((none) 1))

fn count i: Int64 n: Int64 acc: Int64 -> Int64
  (if (>= i n) acc (count (+ i 1) n (+ acc (valueOr (listHead (pick i))))))

fn ! main args: (List String) -> (Result Int64 String)
  (do (println (str (count 0 100000 0)))
      (ok 0))
