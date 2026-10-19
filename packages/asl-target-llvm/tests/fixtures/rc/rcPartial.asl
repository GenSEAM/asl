(module rcPartial
  :x [main]
  :i [])

fn add3 a: Int64 b: Int64 c: Int64 -> Int64
  (+ a (+ b c))

fn ! main args: (List String) -> (Result Int64 String)
  (do (println (str ((partial add3 1 2) 3 4)))
      (ok 0))
