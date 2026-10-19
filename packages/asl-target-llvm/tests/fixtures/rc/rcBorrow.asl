(module rcBorrow
  :x [main]
  :i [])

(schema Cfg (:f scale Int64) (:f name String))

fn walk cfg: Cfg xs: (List Int64) acc: Int64 -> Int64
  (mt (listHead xs)
    ((some x) (mt (listTail xs) ((some t) (walk cfg t (+ acc (* x cfg.scale)))) ((none) acc)))
    ((none) acc))

fn ! main args: (List String) -> (Result Int64 String)
  (let [(cfg (Cfg :scale 3 :name "c"))
        (xs (range 0 100000))]
    (do (println (str (walk cfg xs 0) " " (stringLength cfg.name)))
        (ok 0)))
