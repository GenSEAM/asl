(module aslExamples/resultExample
  :x [parsePositive half halfOr describe])

fn parsePositive n: Int64 -> (Result Int64 String)
  (if (> n 0) (ok n) (err "not positive"))

fn half n: Int64 -> (Result Int64 String)
  (match (parsePositive n)
    ((ok v) (ok (/ v 2)))
    ((err e) (err e)))

fn halfOr n: Int64 d: Int64 -> Int64
  (resultOr (half n) d)

fn describe r: (Result Int64 String) -> String
  (match r
    ((ok v) (str "ok " (stringFromInt64 v)))
    ((err e) (str "err " e)))
