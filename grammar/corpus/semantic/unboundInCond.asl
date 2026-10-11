fn classify n: Int64 -> String
  (cond ((> n 0) (describeSign n)) (else "non-positive"))
