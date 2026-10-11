fn sumList xs: (List Int64) -> Int64
  (match (listHead xs) ((none) 0) ((some h) (+ h (sumList (optionOr (listTail xs) (list))))))

fn firstOr xs: (List Int64) fallback: Int64 -> Int64
  (match (listHead xs) ((some v) v) ((none) fallback))

fn safeDiv a: Int64 b: Int64 -> (Result Int64 String)
  (if (= b 0) (err "division by zero") (ok (/ a b)))

fn describe r: (Result Int64 String) -> String
  (match r ((ok n) (stringFromInt64 n)) ((err msg) msg))

fn classify n: Int64 -> String
  (cond ((< n 0) "negative") ((= n 0) "zero") (else "positive"))
