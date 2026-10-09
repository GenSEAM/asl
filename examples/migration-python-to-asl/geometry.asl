(module migrationGeometry/geometry :x [Point2D euclideanDistance batchClosestPoint] :i [])

(schema Point2D (:f x F64) (:f y F64))

fn euclideanDistance p1: Point2D p2: Point2D -> F64
  (let [(dx (- p1.x p2.x)) (dy (- p1.y p2.y))] (sqrt (+ (* dx dx) (* dy dy))))

fn batchClosestPoint target: Point2D points: (List Point2D) -> Point2D
  (mt (listHead points)
    ((some first) (fold (fn [(best Point2D) (pt Point2D)] -> Point2D (let [(dBest (euclideanDistance target best)) (dCurr (euclideanDistance target pt))] (if (< dCurr dBest) pt best))) first points))
    ((none) (Point2D :x 0.0 :y 0.0)))
