(module bench/histogram :export [histogram])

fn tally m: (Map String Int64) w: String -> (Map String Int64)
  (match (mapGet m w) ((some n) (mapSet m w (+ n 1))) ((none) (mapSet m w 1)))

fn histogram text: String -> (Map String Int64)
  (let [(words (filter (fn [(w String)] -> Bool (not (stringEmpty? w))) (stringSplit (stringTrim text) " "))) (counts (fold tally (mapEmpty) words))] (match (listMax (mapValues counts)) ((none) (mapEmpty)) ((some top) (mapFromPairs (filter (fn [(p (pair String Int64))] -> Bool (= (pairSecond p) top)) (mapPairs counts))))))
