fn parseIt s: String -> (Result Int64 String)
  (ok 1)

fn sumAll xs: (List String) -> (Result (List Int64) String)
  (ok (map (fn [(x String)] -> Int64 (try (parseIt x))) xs))
