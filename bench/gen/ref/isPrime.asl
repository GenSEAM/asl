fn hasDivisorFrom n: Int64 d: Int64 -> Bool
  (cond
    ((> (* d d) n) false)
    ((= (mod n d) 0) true)
    (else (hasDivisorFrom n (+ d 1))))

fn isPrime n: Int64 -> Bool
  (if (< n 2) false (not (hasDivisorFrom n 2)))
