(schema Point (:f x Int64 "Horizontal coordinate") (:f y Int64 "Vertical coordinate"))

(schema Config (:f name String "Display name") (:f retries Int64 "Attempt count" :default 3))

fn origin -> Point
  (Point :x 0 :y 0)

fn manhattan p: Point q: Point -> Int64
  (+ (abs (- p.x q.x)) (abs (- p.y q.y)))

fn scale p: Point k: Int64 -> Point
  (Point :x (* p.x k) :y (* p.y k))
