"Nested list destructuring. A list is not a pattern on the host (cons in an arm"

"is an unknown symbol, and patterns nest one level), so two heads are taken one"

"level at a time through listHead and listTail."

fn pairwise xs: (List Int64) -> (List Int64)
  (match (listHead xs) ((none) (list)) ((some a) (let [(rest (optionOr (listTail xs) (list)))] (match (listHead rest) ((none) (list a)) ((some b) (cons (+ a b) (pairwise (optionOr (listTail rest) (list)))))))))

fn leading xs: (List Int64) -> Int64
  (optionOr (listHead xs) 0)
