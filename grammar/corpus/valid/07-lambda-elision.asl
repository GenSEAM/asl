"Lambda annotations elided: each of these positions is an argument to a builtin"

"whose signature fixes the parameter and return types completely, so writing"

"them again could not differ from what the position already says."

fn evens xs: (List Int64) -> (List Int64)
  (filter (fn [x] (= (mod x 2) 0)) xs)

fn doubled xs: (List Int64) -> (List Int64)
  (map (fn [x] (* x 2)) xs)

fn total xs: (List Int64) -> Int64
  (fold (fn [acc x] (+ acc x)) 0 xs)

fn longest ws: (List String) -> Int64
  (fold (fn [(best Int64) (w String)] -> Int64 (max best (stringLength w))) 0 ws)

fn byLength ws: (List String) -> (List String)
  (listSortBy (fn [w] (stringLength w)) ws)
