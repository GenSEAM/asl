(module bench/histogram :export [histogram])

fn histogram text: String -> (Map String Int64)
  (let [(words (filter (fn [(w String)] -> Bool (not (stringEmpty? w))) (stringSplit (stringTrim text) " "))) (counts (fold (fn [(m (Map String Int64)) (w String)] -> (Map String Int64) (mapSet m w (+ (optionOr (mapGet m w) 0) 1))) (mapEmpty) words))] (match (listMax (mapValues counts)) ((none) (mapEmpty)) ((some top) (mapFromPairs (filter (fn [(p (pair String Int64))] -> Bool (= p.second top)) (mapPairs counts))))))
