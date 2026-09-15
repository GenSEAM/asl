"expect-only: map-key-order"
"The key is the type argument of a generic function, fixed only by the argument"
"at the call site: `probe` writes no Map, and `blank`'s own key is the rigid K"
"of its binder. Nothing an annotation-reading rule can see is wrong here."

(df {K} blank [(seed K)] -> (Map K Int64)
  (map-empty))

(df probe [(x Float64)] -> Int64
  (map-size (blank x)))
