fn sumDigits n: Int64 -> Int64
  (if (< n 10) n (+ (mod n 10) (sumDigits (/ n 10))))
