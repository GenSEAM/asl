fn collatzSteps n: Int64 -> Int64
  (cond
    ((= n 1) 0)
    ((= (mod n 2) 0) (+ 1 (collatzSteps (/ n 2))))
    (else (+ 1 (collatzSteps (+ (* 3 n) 1)))))
