"expect-only: map-key-order"

"No Map is written anywhere: mapFromPairs takes the key type from the list it"

"is given, so a rule reading annotations has nothing to look at and this program"

"reached rustc, where the f64: Ord bound in rt rejected it."

fn tally ps: (List (Pair Float64 Int64)) -> Int64
  (mapSize (mapFromPairs ps))
