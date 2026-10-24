(module rcClash
  :x [main]
  :i [])

; (:m :ref RC-BORROW-CONSUME-CLASH :do "one list passed twice to one call: borrowed and consumed (mapAlias, pick), consumed twice (both), borrowed twice (lens), and captured by the closure a builder walks it with")
fn mapAlias names: (List String) xs: (List String) acc: (List String) -> (List String)
  (match (listHead xs) ((some x) (mapAlias names (optionOr (listTail xs) (list)) (cons (str x (stringFromInt64 (listLength names))) acc))) ((none) (listReverse acc)))

fn pick keep: (List Int64) look: (List Int64) -> Int64
  (let [(r (listReverse keep))
        (s (+ (* 100 (optionOr (listHead r) 0)) (listSum r)))]
    (+ s (+ (* 1000 (optionOr (listHead look) 0)) (listSum look))))

fn both a: (List Int64) b: (List Int64) -> Int64
  (let [(ra (listReverse a))
        (rb (listReverse b))]
    (+ (* 10 (optionOr (listHead ra) 0)) (optionOr (listHead rb) 0)))

fn lens a: (List Int64) b: (List Int64) -> Int64
  (+ (listLength a) (listSum b))

fn sumWalk xs: (List Int64) acc: Int64 -> Int64
  (match (listHead xs) ((some v) (sumWalk (optionOr (listTail xs) (list)) (+ acc v))) ((none) acc))

fn round k: Int64 acc: Int64 -> Int64
  (if (>= k 3) acc
    (let [(xs (range 1 (+ 6 k)))
          (ys (range 1 (+ 6 k)))
          (zs (range 1 (+ 6 k)))
          (ws (range 1 (+ 6 k)))
          (shifted (map (fn [(n Int64)] -> Int64 (+ n (listLength ws))) ws))]
      (round (+ k 1) (+ acc (+ (pick xs xs) (+ (both ys ys) (+ (lens zs zs) (+ (sumWalk (range 1 (+ 6 k)) 0) (listSum shifted)))))))))

fn ! main args: (List String) -> (Result Int64 String)
  (let [(names (list "a" "bb" "ccc"))
        (more (list "x" "yy" "zzz" "w"))]
    (do (println (stringJoin (mapAlias names names (list)) ","))
        (println (stringJoin (mapAlias (optionOr (listTail more) (list)) more (list)) ","))
        (println (str (round 0 0)))
        (ok 0)))
