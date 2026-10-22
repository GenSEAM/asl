(module asl-know/examples/coreLang :x [Point Shape area describe total selfTest] :i [])

(schema Point (:f x Int64) (:f y Int64))

enum Shape
  (circle r: Int64)
  (rect w: Int64 h: Int64)

fn area s: Shape -> Int64
  (match s
    ((circle r) (* 3 (* r r)))
    ((rect w h) (* w h)))

fn describe n: Int64 -> String
  (cond
    ((< n 0) "negative")
    ((= n 0) "zero")
    (else (str "positive " n)))

fn total xs: (List Int64) -> Int64
  (let [(evens (filter (fn [(x Int64)] -> Bool (= (mod x 2) 0)) xs))
        (sum (fold (fn [(acc Int64) (x Int64)] -> Int64 (+ acc x)) 0 evens))
        (first (optionOr (listHead xs) 0))]
    (if (> sum 0) (+ sum first) first))

fn ! selfTest -> Bool
  (let [(p (Point :x 1 :y 2))
        (q (with p :y 5))
        (m (mapSet (mapEmpty) "k" 7))]
    (do
      (println (describe q.y))
      (and (= (area (rect 2 3)) 6) (= (area (circle 1)) 3) (= q.y 5) (= p.y 2)
           (= (describe 0) "zero") (= (total [1 2 3 4]) 7)
           (= (mapGetOr m "k" 0) 7)
           (= (match (mapGet m "z") ((some v) v) ((none) -1)) -1))))
