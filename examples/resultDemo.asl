(module asl/examples/resultDemo
  :x [parsePort]
  :i [])

fn parsePort text: String -> (Result Int64 String)
  (match (stringToInt64 text)
    ((some n) (if (and (> n 0) (< n 65536)) (ok n) (err "port out of range")))
    ((none) (err "port is not a number")))
