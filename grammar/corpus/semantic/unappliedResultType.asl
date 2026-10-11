fn parseIt s: String -> (Result Int64 String)
  (ok 1)

fn useIt s: String -> Result
  (parseIt s)
