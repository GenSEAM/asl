fn sumDigits n: Int64 -> Int64
  (cond
    ((= n 0) 0)
    (else (+ (mod n 10) (sumDigits (/ n 10)))))
