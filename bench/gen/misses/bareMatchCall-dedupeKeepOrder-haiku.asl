fn containsFrom xs: (List Int64) v: Int64 i: Int64 -> Bool
  (match (listGet xs i)
    ((some x) (cond ((= x v) true) (else (containsFrom xs v (+ i 1)))))
    ((none) false))

fn dedupeGo xs: (List Int64) acc: (List Int64) i: Int64 -> (List Int64)
  (match (listGet xs i)
    ((some x) (cond ((containsFrom acc x 0) (dedupeGo xs acc (+ i 1))) (else (dedupeGo xs (listAppend acc (list x)) (+ i 1)))))
    ((none) acc))

fn dedupeKeepOrder xs: (List Int64) -> (List Int64)
  (dedupeGo xs (list) 0)
