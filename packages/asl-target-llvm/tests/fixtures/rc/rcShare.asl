(module rcShare
  :x [main]
  :i [])

(schema Point (:f x Int64) (:f y Int64))

fn make i: Int64 -> Point
  (Point :x i :y (* i 2))

fn both a: Point b: Point -> Int64
  (+ a.x b.y)

fn loop i: Int64 n: Int64 acc: Int64 -> Int64
  (if (>= i n) acc (let [(p (make i)) (_ (make (+ i 1)))] (loop (+ i 1) n (+ acc (both p p)))))

fn ! main args: (List String) -> (Result Int64 String)
  (do (println (str (loop 0 1000 0)))
      (ok 0))
