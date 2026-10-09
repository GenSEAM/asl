"expect-only: map-key-order"

"A Float64 Map key type-checked and could reach no backend: BTreeMap needs Ord,"

"and the specification asks mapKeys for sorted order, which f64 cannot give."

fn lookup m: (Map Float64 Int64) k: Float64 -> (Option Int64)
  (mapGet m k)
