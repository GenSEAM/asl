(module jsFixtures/map :x [main])

fn ! main -> Int64
  (let [(values (mapSet (mapSet (mapEmpty) "answer" 42) "other" 7))
        (updated (mapSet values "answer" 5))
        (selected (+ (optionOr (mapGet updated "answer") 0) (optionOr (mapGet updated "other") 0)))
        (withMissing (+ selected (optionOr (mapGet updated "missing") 3)))]
    (do (print (stringFromInt64 withMissing)) withMissing))
