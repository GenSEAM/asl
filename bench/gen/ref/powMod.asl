fn powMod base: Int64 exponent: Int64 modulus: Int64 -> Int64
  (cond
    ((= exponent 0) (mod 1 modulus))
    ((= (mod exponent 2) 0)
      (let [(half (powMod base (/ exponent 2) modulus))]
        (mod (* half half) modulus)))
    (else (mod (* (mod base modulus) (powMod base (- exponent 1) modulus)) modulus)))
