(module jsFixtures/shapes :x [main])

enum Shape (circle r: Int64) (square side: Int64)

(schema Pt (:f x Int64) (:f y Int64))

fn area s: Shape -> Int64
  (mt s ((circle r) (* 3 (* r r))) ((square a) (* a a)))

fn ! main -> Int64
  (let [(p (Pt :x 2 :y 5))
        (xs (map area [(circle 1) (square p.y)]))
        (adder (fn [(n Int64)] -> Int64 (+ n p.x)))]
    (do (println (str (optionOr (listGet xs 1) 0) " " (map adder xs) " " p " " (with p :x 9) " " (square 4)))
        (println (str (mt (mapGet (mapSet (mapEmpty) "k" 7) "k") ((some v) v) ((none) 0)) " " (listSum xs) " " (fold (fn [(a Int64) (b Int64)] -> Int64 (- a b)) 0 xs)))
        3))
