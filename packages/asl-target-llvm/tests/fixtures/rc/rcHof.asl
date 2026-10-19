(module rcHof
  :x [main]
  :i [])

fn walk f: (fn [(List Int64) Int64] -> (List Int64)) acc: (List Int64) xs: (List Int64) -> (List Int64)
  (mt (listHead xs) ((some x) (mt (listTail xs) ((some t) (walk f (f acc x) t)) ((none) (cons x acc)))) ((none) acc))

fn push acc: (List Int64) x: Int64 -> (List Int64)
  (cons x acc)

fn ! main args: (List String) -> (Result Int64 String)
  (let [(outer (fn [(acc (List Int64)) (b Int64)] -> (List Int64) (walk push acc (range 0 (mod b 7)))))]
    (do (println (str (listLength (walk outer (list) (range 0 300)))))
        (ok 0)))
