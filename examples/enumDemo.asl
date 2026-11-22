(module asl/examples/enumDemo
  :x [Shape area]
  :i [])

(enum Shape (:c circle [(r Int64)]) (:c rect [(w Int64) (h Int64)]))

fn area s: Shape -> Int64
  (match s
    ((circle r) (* 3 (* r r)))
    ((rect w h) (* w h)))
