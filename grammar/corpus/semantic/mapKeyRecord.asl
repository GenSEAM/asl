"expect-only: map-key-order"

"A record is orderable only if every field is. Point holds a Float64, so the"

"Rust lowering derives no Ord for it and BTreeMap<Point, _> does not compile."

(schema Point (:f x Float64 "Horizontal coordinate") (:f y Float64 "Vertical coordinate"))

fn lookup m: (Map Point Int64) k: Point -> (Option Int64)
  (mapGet m k)
