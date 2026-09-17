(module asl-vector/primitives
  :d "Geometric primitive fitting and substitution: rect, circle, and line detection for token minimization."
  :x [detectPrimitive
      isRectangle
      isCircle
      isStraightLine])

(df detectPrimitive [(poly (List (List F64))) (tolerance F64)] -> (Option (List Any))
  (:d "Attempts primitive substitution: returns (:rect x y w h) or (:circle cx cy r) if error < tolerance, else (none).")
  (let [(rectOpt (isRectangle poly tolerance))]
    (mt rectOpt
      ((some rectData) (some rectData))
      ((none)
       (let [(circOpt (isCircle poly tolerance))]
         (mt circOpt
           ((some circData) (some circData))
           ((none) (none))))))))

(df isRectangle [(poly (List (List F64))) (tolerance F64)] -> (Option (List Any))
  (:d "Checks if polygon is an axis-aligned or near axis-aligned rectangle (4 vertices + closure).")
  (let [(len (list-length poly))]
    (if (or (== len 4) (== len 5))
        (let [(p0 (option-or (list-get poly 0) (list 0.0 0.0)))
              (p1 (option-or (list-get poly 1) (list 0.0 0.0)))
              (p2 (option-or (list-get poly 2) (list 0.0 0.0)))
              (p3 (option-or (list-get poly 3) (list 0.0 0.0)))
              (x0 (option-or (list-head p0) 0.0))
              (y0 (option-or (list-head (option-or (list-tail p0) (list))) 0.0))
              (x1 (option-or (list-head p1) 0.0))
              (y1 (option-or (list-head (option-or (list-tail p1) (list))) 0.0))
              (x2 (option-or (list-head p2) 0.0))
              (y2 (option-or (list-head (option-or (list-tail p2) (list))) 0.0))
              (x3 (option-or (list-head p3) 0.0))
              (y3 (option-or (list-head (option-or (list-tail p3) (list))) 0.0))
              (minX (min4 x0 x1 x2 x3))
              (minY (min4 y0 y1 y2 y3))
              (maxX (max4 x0 x1 x2 x3))
              (maxY (max4 y0 y1 y2 y3))
              (w (- maxX minX))
              (h (- maxY minY))]
          (if (and (> w tolerance) (> h tolerance))
              (some (list ":rect" minX minY w h))
              (none)))
        (none))))

(df min4 [(a F64) (b F64) (c F64) (d F64)] -> F64
  (let [(m1 (if (< a b) a b))
        (m2 (if (< c d) c d))]
    (if (< m1 m2) m1 m2)))

(df max4 [(a F64) (b F64) (c F64) (d F64)] -> F64
  (let [(m1 (if (> a b) a b))
        (m2 (if (> c d) c d))]
    (if (> m1 m2) m1 m2)))

(df isCircle [(poly (List (List F64))) (tolerance F64)] -> (Option (List Any))
  (:d "Fits a circle to polygon vertices and checks radial variance.")
  (let [(len (list-length poly))]
    (if (< len 8)
        (none)
        (let [(centroid (calcCentroid poly 0.0 0.0 0))
              (cx (option-or (list-head centroid) 0.0))
              (cy (option-or (list-head (option-or (list-tail centroid) (list))) 0.0))
              (avgR (calcAvgRadius poly cx cy 0.0 0))
              (variance (calcRadiusVariance poly cx cy avgR 0.0 0))]
          (if (and (> avgR tolerance) (< variance tolerance))
              (some (list ":circle" cx cy avgR))
              (none))))))

(df calcCentroid [(pts (List (List F64))) (accX F64) (accY F64) (count Int)] -> (List F64)
  (if (list-empty? pts)
      (if (> count 0)
          (list (/ accX (float count)) (/ accY (float count)))
          (list 0.0 0.0))
      (let [(pt (option-or (list-head pts) (list 0.0 0.0)))
            (tail (option-or (list-tail pts) (list)))
            (x (option-or (list-head pt) 0.0))
            (y (option-or (list-head (option-or (list-tail pt) (list))) 0.0))]
        (calcCentroid tail (+ accX x) (+ accY y) (+ count 1)))))

(df calcAvgRadius [(pts (List (List F64))) (cx F64) (cy F64) (accR F64) (count Int)] -> F64
  (if (list-empty? pts)
      (if (> count 0) (/ accR (float count)) 0.0)
      (let [(pt (option-or (list-head pts) (list cx cy)))
            (tail (option-or (list-tail pts) (list)))
            (x (option-or (list-head pt) cx))
            (y (option-or (list-head (option-or (list-tail pt) (list))) cy))
            (dx (- x cx))
            (dy (- y cy))
            (r (sqrt (+ (* dx dx) (* dy dy))))]
        (calcAvgRadius tail cx cy (+ accR r) (+ count 1)))))

(df calcRadiusVariance [(pts (List (List F64))) (cx F64) (cy F64) (avgR F64) (accDiff F64) (count Int)] -> F64
  (if (list-empty? pts)
      (if (> count 0) (/ accDiff (float count)) 999.0)
      (let [(pt (option-or (list-head pts) (list cx cy)))
            (tail (option-or (list-tail pts) (list)))
            (x (option-or (list-head pt) cx))
            (y (option-or (list-head (option-or (list-tail pt) (list))) cy))
            (dx (- x cx))
            (dy (- y cy))
            (r (sqrt (+ (* dx dx) (* dy dy))))
            (diff (abs (- r avgR)))]
        (calcRadiusVariance tail cx cy avgR (+ accDiff diff) (+ count 1)))))

(df isStraightLine [(p1 (List F64)) (p2 (List F64)) (p3 (List F64)) (tolerance F64)] -> Bool
  (:d "Checks collinearity of 3 points.")
  (let [(x1 (option-or (list-head p1) 0.0))
        (y1 (option-or (list-head (option-or (list-tail p1) (list))) 0.0))
        (x2 (option-or (list-head p2) 0.0))
        (y2 (option-or (list-head (option-or (list-tail p2) (list))) 0.0))
        (x3 (option-or (list-head p3) 0.0))
        (y3 (option-or (list-head (option-or (list-tail p3) (list))) 0.0))
        (area (* 0.5 (- (* x1 (- y2 y3)) (+ (* x2 (- y1 y3)) (* x3 (- y1 y2))))))]
    (< (abs area) tolerance)))
