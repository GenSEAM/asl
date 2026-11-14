enum Shape (circle r: Int64) (rect w: Int64 h: Int64) (square side: Int64) (triangle b: Int64 h: Int64)

fn shapeArea s: Shape -> Int64
  (match s
    ((circle r) (* 3 (* r r)))
    ((rect w h) (* w h))
    ((square side) (* side side))
    ((triangle b h) (/ (* b h) 2)))
