"String builtins, let bindings, Result propagation by match."

fn shout s: String -> String
  (str (stringUpper (stringTrim s)) "!")

fn initials full: String -> String
  (let [(parts (stringSplit full " ")) (heads (map (fn [(w String)] -> String (match (stringSlice w 0 1) ((some c) (stringUpper c)) ((none) ""))) parts))] (stringJoin heads "."))

fn parsePair s: String -> (Result Int64 String)
  (let [(trimmed (stringTrim s))] (match (optionToResult (stringToInt64 trimmed) "not a number") ((ok n) (ok (* n 2))) ((err e) (err e))))

fn evensBelow limit: Int64 -> (List Int64)
  (filter (fn [(n Int64)] -> Bool (= (mod n 2) 0)) (range 0 limit))

fn total xs: (List Int64) -> Int64
  (fold (fn [(acc Int64) (x Int64)] -> Int64 (+ acc x)) 0 xs)
