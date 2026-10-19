(module asl-know/examples/coreList :x [summary selfTest] :i [])

fn summary xs: (List Int64) -> String
  (let [(sorted (listSortBy (fn [(x Int64)] -> Int64 (- 0 x)) xs))
        (doubled (map (fn [(x Int64)] -> Int64 (* 2 x)) (listTake sorted 2)))
        (big (filter (fn [(x Int64)] -> Bool (> x 2)) xs))]
    (str (listLength xs) " " (stringJoin (map stringFromInt64 doubled) ",") " " (listSum big) " " (optionOr (listLast xs) 0)))

fn selfTest -> Bool
  (and (= (summary [3 1 4 1 5]) "5 10,8 12 5") (= (summary []) "0  0 0"))
