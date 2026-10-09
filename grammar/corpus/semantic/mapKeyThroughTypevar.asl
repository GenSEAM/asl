"expect-only: map-key-order"

"The key is the type argument of a generic function, fixed only by the argument"

"at the call site: `probe` writes no Map, and `blank`'s own key is the rigid K"

"of its signature (the host reads no {K} binder). Nothing an annotation-reading rule can see is wrong here."

fn blank seed: K -> (Map K Int64)
  (mapEmpty)

fn probe x: Float64 -> Int64
  (mapSize (blank x))
