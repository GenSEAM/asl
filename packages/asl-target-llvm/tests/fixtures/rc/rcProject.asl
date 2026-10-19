(module rcProject
  :x [main]
  :i [])

(schema Box (:f items (List Int64)) (:f tag String))

fn second xs: (List Int64) -> (List Int64)
  (mt (listTail xs) ((some t) t) ((none) xs))

fn dropN xs: (List Int64) n: Int64 -> (List Int64)
  (if (= n 0) xs (mt (listTail xs) ((some t) (dropN t (- n 1))) ((none) xs)))

fn itemsOf b: Box -> (List Int64)
  b.items

fn sumFrom xs: (List Int64) acc: Int64 -> Int64
  (mt (listHead xs)
    ((some x) (mt (listTail xs) ((some t) (sumFrom t (+ acc x))) ((none) (+ acc x))))
    ((none) acc))

fn rounds k: Int64 acc: Int64 -> Int64
  (if (= k 0) acc
    (let [(b (Box :items (range 0 200) :tag "t"))
          (kept (second (dropN (itemsOf b) 150)))]
      (rounds (- k 1) (+ acc (sumFrom kept 0)))))

fn collect k: Int64 acc: (List (List Int64)) -> (List (List Int64))
  (if (= k 0) acc (collect (- k 1) (cons (dropN (range 0 10) (mod k 5)) acc)))

fn ! main args: (List String) -> (Result Int64 String)
  (let [(tails (collect 300 (list)))]
    (do (println (str (rounds 300 0) " " (fold (fn [(a Int64) (xs (List Int64))] -> Int64 (+ a (listLength xs))) 0 tails)
                      " " (fold (fn [(a Int64) (xs (List Int64))] -> Int64 (+ a (mt (listHead xs) ((some x) x) ((none) 0)))) 0 tails)))
        (ok 0)))
