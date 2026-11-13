fn secondLargest xs: (List Int64) -> (Option Int64)
  (match (listMax xs)
    ((none) (none))
    ((some top) (listMax (filter (fn [x] (< x top)) xs))))
