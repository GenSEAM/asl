(module rcLoop
  :x [main]
  :i [])

(schema Point (:f x Int64) (:f y Int64))

fn step p: Point i: Int64 -> Point
  (Point :x (+ p.x i) :y (- p.y i))

fn loop p: Point i: Int64 n: Int64 -> Point
  (if (>= i n) p (loop (step p i) (+ i 1) n))

fn ! main args: (List String) -> (Result Int64 String)
  (let [(p (loop (Point :x 0 :y 0) 0 1000))]
    (do (println (str p.x " " p.y))
        (ok 0)))
