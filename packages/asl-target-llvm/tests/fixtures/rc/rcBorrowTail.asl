(module rcBorrowTail
  :x [main]
  :i [])

fn total xs: (List Int64) acc: Int64 -> Int64
  (match (listHead xs)
    ((some x) (match (listTail xs) ((some t) (total t (+ acc x))) ((none) (+ acc x))))
    ((none) acc))

fn probe n: Int64 -> Int64
  (total (range 0 n) 0)

fn count k: Int64 acc: Int64 -> Int64
  (if (= k 0) acc (count (- k 1) (+ acc (probe 1000))))

fn ! main args: (List String) -> (Result Int64 String)
  (do (println (str (count 300 0)))
      (ok 0))
