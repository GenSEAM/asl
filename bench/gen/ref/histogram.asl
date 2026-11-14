fn tally counts: (Map String Int64) w: String -> (Map String Int64)
  (mapSet counts w (+ (mapGetOr counts w 0) 1))

fn histogram text: String -> (Map String Int64)
  (let [(words (filter (fn [w] (not (stringEmpty? w))) (stringSplit text " ")))
        (counts (fold tally (mapEmpty) words))]
    (match (listMax (mapValues counts))
      ((none) (mapEmpty))
      ((some top) (mapFromPairs (filter (fn [p] (= (pairSecond p) top)) (mapPairs counts))))))
