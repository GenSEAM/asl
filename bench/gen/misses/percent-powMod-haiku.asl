fn powModGo b: Int64 e: Int64 m: Int64 acc: Int64 -> Int64
  (cond
      ((= e 0) acc)
      ((= (mod e 2) 1) (powModGo (mod (* b b) m) (/ e 2) m (mod (* acc b) m)))
      (else (powModGo (mod (* b b) m) (/ e 2) m acc)))

fn powMod base: Int64 exponent: Int64 modulus: Int64 -> Int64
  (powModGo (mod base modulus) exponent modulus (mod 1 modulus))
