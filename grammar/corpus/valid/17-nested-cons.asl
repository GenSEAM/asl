fn pairwise xs: (List Int64) -> (List Int64)
  (match (listHead xs) ((none) (list)) ((some a) (let [(rest (optionOr (listTail xs) (list)))] (match (listHead rest) ((none) (list a)) ((some b) (cons (+ a b) (pairwise (optionOr (listTail rest) (list)))))))))

fn leading xs: (List Int64) -> Int64
  (optionOr (listHead xs) 0)
