fn follow table: (Map String String) name: String -> String
  (match (mapGet table name)
    ((none) name)
    ((some next) (follow table next)))

fn lookupChain table: (Map String String) start: String -> (Option String)
  (optionMap (fn [next] (follow table next)) (mapGet table start))
