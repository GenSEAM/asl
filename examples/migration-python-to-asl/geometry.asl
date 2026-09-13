(module migrationGeometry/geometry
  :d "High-performance geometric calculations ported from legacy Python."
  :x [Point2D euclideanDistance batchClosestPoint]
  :i [])

(dfs Point2D
  (:f x F64 "X coordinate")
  (:f y F64 "Y coordinate"))

(df euclideanDistance [(p1 Point2D) (p2 Point2D)] -> F64
  :d "Computes Euclidean distance between two 2D points."
  (let [(dx (- (.-x p1) (.-x p2)))
        (dy (- (.-y p1) (.-y p2)))]
    (sqrt (+ (* dx dx) (* dy dy)))))

(df batchClosestPoint [(target Point2D) (points (List Point2D))] -> Point2D
  :d "Finds point with minimum Euclidean distance to target point."
  (fold (fn [(best Point2D) (pt Point2D)] -> Point2D
          (let [(dBest (euclideanDistance target best))
                (dCurr (euclideanDistance target pt))]
            (if (< dCurr dBest) pt best)))
        (list-head points)
        points))
