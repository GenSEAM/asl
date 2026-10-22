(module rcBuiltins
  :x [main]
  :i [])

fn longer w: String -> Bool
  (> (stringLength w) 1)

fn piece s: String -> String
  (match (stringSlice s 0 4) ((some p) p) ((none) "none"))

fn tailLength xs: (List String) -> Int64
  (match (listTail xs) ((some t) (listLength t)) ((none) 0))

fn step i: Int64 -> Int64
  (let [(s (str "item-" i "-" (stringConcat "a" "b")))
        (u (piece s))
        (kept (filter longer (list s u "q")))
        (shown (map (fn [(w String)] -> String (str "<" w ">")) kept))]
    (+ (stringLength (stringConcat s u)) (+ (tailLength shown) (listLength kept))))

fn loop i: Int64 n: Int64 total: Int64 -> Int64
  (if (>= i n) total (loop (+ i 1) n (+ total (step i))))

fn ! main args: (List String) -> (Result Int64 String)
  (do (println (str (loop 0 20000 0)))
      (ok 0))
