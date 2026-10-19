(module rcTail
  :x [main]
  :i [])

(schema Point (:f x Int64) (:f y Int64))

fn bounce k: (fn [Point Int64] -> Point) p: Point i: Int64 -> Point
  (k p i)

fn run p: Point i: Int64 -> Point
  (if (>= i 3000000) p (bounce (fn [(q Point) (j Int64)] -> Point (run q j)) (Point :x (+ p.x 1) :y p.y) (+ i 1)))

fn ! main args: (List String) -> (Result Int64 String)
  (let [(p (run (Point :x 0 :y 5) 0))]
    (do (println (str p.x " " p.y))
        (ok 0)))
