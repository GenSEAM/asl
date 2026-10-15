(module jsFixtures/typed :x [area firstOr mapBoth describe origin isBig label])

enum Shape (circle r: Int64) (square side: Int64)

(schema Pt (:f x Int64) (:f y Int64))

fn area s: Shape -> Int64
  (mt s ((circle r) (* 3 (* r r))) ((square a) (* a a)))

fn firstOr xs: (List T) fallback: T -> T
  (optionOr (listHead xs) fallback)

fn mapBoth f: (fn [A] -> B) xs: (List A) -> (List B)
  (map f xs)

fn describe p: Pt -> String
  (str "(" p.x ", " p.y ")")

fn origin -> Pt
  (Pt :x 0 :y 0)

fn isBig? s: Shape -> Bool
  (> (area s) 10)

fn label s: Shape -> (Option String)
  (if (isBig? s) (some "big") (none))
