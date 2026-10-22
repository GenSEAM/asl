(module rcAppend
  :x [main]
  :i [])

fn sum xs: (List Int64) -> Int64
  (fold (fn [(a Int64) (x Int64)] -> Int64 (+ a x)) 0 xs)

fn grow n: Int64 -> (List Int64)
  (fold (fn [(acc (List Int64)) (x Int64)] -> (List Int64) (listAppend acc (list x))) (list) (range 0 n))

fn ! main args: (List String) -> (Result Int64 String)
  (let [(built (grow 2000))
        (shared (list 1 2 3))
        (spliced (listAppend (cons 0 shared) (list 9)))
        (whole (listAppend shared (list 7)))
        (kept (listAppend built (list 5)))]
    (do (println (str (sum built) " " (listLength built) " " (sum kept) " " (listLength kept)))
        (println (str (sum spliced) " " (listLength spliced) " " (sum whole) " " (sum shared) " " (listLength shared)))
        (ok 0)))
