(module asl/examples/recordDemo
  :x [Point moveRight]
  :i [])

(schema Point (:f x Int64) (:f y Int64))

fn moveRight p: Point dx: Int64 -> Point
  (with p :x (+ p.x dx))
