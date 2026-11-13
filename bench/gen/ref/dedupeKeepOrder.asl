fn dedupeKeepOrder xs: (List Int64) -> (List Int64)
  (fold (fn [acc x] (if (listContains? acc x) acc (listAppend acc (list x)))) (list) xs)
