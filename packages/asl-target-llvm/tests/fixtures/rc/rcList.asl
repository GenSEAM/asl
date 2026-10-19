(module rcList
  :x [main]
  :i [])

(schema Point (:f x Int64) (:f y Int64))

fn build i: Int64 n: Int64 acc: (List Point) -> (List Point)
  (if (>= i n) acc (build (+ i 1) n (cons (Point :x i :y (- 0 i)) acc)))

fn sumX xs: (List Point) -> Int64
  (fold (fn [(a Int64) (p Point)] -> Int64 (+ a p.x)) 0 xs)

fn round k: Int64 acc: Int64 -> Int64
  (if (>= k 20) acc (let [(xs (build 0 200 (list)))
                          (base (Point :x k :y k))
                          (shifted (map (fn [(p Point)] -> Point (Point :x (+ p.x base.x) :y p.y)) xs))]
                      (round (+ k 1) (+ acc (+ (sumX xs) (sumX shifted))))))

fn ! main args: (List String) -> (Result Int64 String)
  (do (println (str (round 0 0)))
      (ok 0))
