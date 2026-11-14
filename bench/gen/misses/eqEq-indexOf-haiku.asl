fn indexFrom xs: (List Int64) target: Int64 i: Int64 -> (Option Int64)
  (cond
      ((>= i (listLength xs)) (none))
      (else (match (listGet xs i)
        ((some v) (cond
          ((= v target) (some i))
          (else (indexFrom xs target (+ i 1)))))
        ((none) (none)))))

fn indexOf xs: (List Int64) target: Int64 -> (Option Int64)
  (indexFrom xs target 0)
