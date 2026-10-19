(module asl-know/examples/coreMap :x [wordCounts selfTest] :i [])

fn wordCounts text: String -> (Map String Int64)
  (fold (fn [(m (Map String Int64)) (w String)] -> (Map String Int64) (mapSet m w (+ 1 (mapGetOr m w 0))))
        (mapEmpty)
        (filter (fn [(w String)] -> Bool (not (stringEmpty? w))) (stringSplit text " ")))

fn selfTest -> Bool
  (let [(m (wordCounts "a b a  c a"))]
    (and (= (mapGetOr m "a" 0) 3) (= (mapKeys m) ["a" "b" "c"]) (none? (mapGet m "z")) (= (mapSize m) 3)))
