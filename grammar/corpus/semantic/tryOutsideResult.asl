fn parseIt s: String -> (Result Int64 String)
  (ok 1)

fn useIt -> Int64
  (try (parseIt "1"))
