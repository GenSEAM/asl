fn gcd a: Int64 b: Int64 -> Int64
  (cond
      ((= b 0) a)
      (else (gcd b (mod a b))))
