fn mergeSorted a: (List Int64) b: (List Int64) -> (List Int64)
  (listSort (listAppend a b))
