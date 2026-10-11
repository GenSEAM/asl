(schema Point (:f x Float64 "Horizontal coordinate") (:f y Float64 "Vertical coordinate"))

fn lookup m: (Map Point Int64) k: Point -> (Option Int64)
  (mapGet m k)
