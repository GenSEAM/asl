fn gcd a: Int64 b: Int64 -> Int64
  (if (= b 0) a (gcd b (mod a b)))
