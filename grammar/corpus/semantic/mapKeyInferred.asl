fn tally ps: (List (Pair Float64 Int64)) -> Int64
  (mapSize (mapFromPairs ps))
