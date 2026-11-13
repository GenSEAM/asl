fn maxOf xs: (List Int64) acc: Int64 -> Int64
  (match (listHead xs)
    ((none) acc)
    ((some v) (maxOf (optionOr (listTail xs) (list)) (cond ((> v acc) v) (else acc)))))

fn listMax xs: (List Int64) -> (Option Int64)
  (match (listHead xs)
    ((none) (none))
    ((some h) (some (maxOf (optionOr (listTail xs) (list)) h))))

fn keepBest v: Int64 m: Int64 best: (Option Int64) -> (Option Int64)
  (cond ((>= v m) best)
    (else (match best
      ((none) (some v))
      ((some b) (cond ((> v b) (some v)) (else best))))))

fn secondBelow xs: (List Int64) m: Int64 best: (Option Int64) -> (Option Int64)
  (match (listHead xs)
    ((none) best)
    ((some v) (secondBelow (optionOr (listTail xs) (list)) m (keepBest v m best))))

fn secondLargest xs: (List Int64) -> (Option Int64)
  (match (listMax xs)
    ((none) (none))
    ((some m) (secondBelow xs m (none))))
