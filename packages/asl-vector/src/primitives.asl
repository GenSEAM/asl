(module asl-vector/primitives :x [detectPrimitive isRectangle isCircle isStraightLine])

fn detectPrimitive poly: (List (List F64)) tolerance: F64 -> (Option (List Any))
  (let [(rectOpt (isRectangle poly tolerance))] (mt rectOpt ((some rectData) (some rectData)) ((none) (let [(circOpt (isCircle poly tolerance))] (mt circOpt ((some circData) (some circData)) ((none) (none)))))))

fn isRectangle poly: (List (List F64)) tolerance: F64 -> (Option (List Any))
  (let [(len (listLength poly))] (if (or (== len 4) (== len 5)) (let [(p0 (optionOr (listGet poly 0) (list 0.0 0.0))) (p1 (optionOr (listGet poly 1) (list 0.0 0.0))) (p2 (optionOr (listGet poly 2) (list 0.0 0.0))) (p3 (optionOr (listGet poly 3) (list 0.0 0.0))) (x0 (optionOr (listHead p0) 0.0)) (y0 (optionOr (listHead (optionOr (listTail p0) (list))) 0.0)) (x1 (optionOr (listHead p1) 0.0)) (y1 (optionOr (listHead (optionOr (listTail p1) (list))) 0.0)) (x2 (optionOr (listHead p2) 0.0)) (y2 (optionOr (listHead (optionOr (listTail p2) (list))) 0.0)) (x3 (optionOr (listHead p3) 0.0)) (y3 (optionOr (listHead (optionOr (listTail p3) (list))) 0.0)) (minX (min4 x0 x1 x2 x3)) (minY (min4 y0 y1 y2 y3)) (maxX (max4 x0 x1 x2 x3)) (maxY (max4 y0 y1 y2 y3)) (w (- maxX minX)) (h (- maxY minY))] (if (and (> w tolerance) (> h tolerance)) (some (list ":rect" minX minY w h)) (none))) (none)))

fn min4 a: F64 b: F64 c: F64 d: F64 -> F64
  (let [(m1 (if (< a b) a b)) (m2 (if (< c d) c d))] (if (< m1 m2) m1 m2))

fn max4 a: F64 b: F64 c: F64 d: F64 -> F64
  (let [(m1 (if (> a b) a b)) (m2 (if (> c d) c d))] (if (> m1 m2) m1 m2))

fn isCircle poly: (List (List F64)) tolerance: F64 -> (Option (List Any))
  (let [(len (listLength poly))] (if (< len 8) (none) (let [(centroid (calcCentroid poly 0.0 0.0 0)) (cx (optionOr (listHead centroid) 0.0)) (cy (optionOr (listHead (optionOr (listTail centroid) (list))) 0.0)) (avgR (calcAvgRadius poly cx cy 0.0 0)) (variance (calcRadiusVariance poly cx cy avgR 0.0 0))] (if (and (> avgR tolerance) (< variance tolerance)) (some (list ":circle" cx cy avgR)) (none)))))

fn calcCentroid pts: (List (List F64)) accX: F64 accY: F64 count: Int -> (List F64)
  (if (listEmpty? pts) (if (> count 0) (list (/ accX (int64ToFloat64 count)) (/ accY (int64ToFloat64 count))) (list 0.0 0.0)) (let [(pt (optionOr (listHead pts) (list 0.0 0.0))) (tail (optionOr (listTail pts) (list))) (x (optionOr (listHead pt) 0.0)) (y (optionOr (listHead (optionOr (listTail pt) (list))) 0.0))] (calcCentroid tail (+ accX x) (+ accY y) (+ count 1))))

fn calcAvgRadius pts: (List (List F64)) cx: F64 cy: F64 accR: F64 count: Int -> F64
  (if (listEmpty? pts) (if (> count 0) (/ accR (int64ToFloat64 count)) 0.0) (let [(pt (optionOr (listHead pts) (list cx cy))) (tail (optionOr (listTail pts) (list))) (x (optionOr (listHead pt) cx)) (y (optionOr (listHead (optionOr (listTail pt) (list))) cy)) (dx (- x cx)) (dy (- y cy)) (r (sqrt (+ (* dx dx) (* dy dy))))] (calcAvgRadius tail cx cy (+ accR r) (+ count 1))))

fn calcRadiusVariance pts: (List (List F64)) cx: F64 cy: F64 avgR: F64 accDiff: F64 count: Int -> F64
  (if (listEmpty? pts) (if (> count 0) (/ accDiff (int64ToFloat64 count)) 999.0) (let [(pt (optionOr (listHead pts) (list cx cy))) (tail (optionOr (listTail pts) (list))) (x (optionOr (listHead pt) cx)) (y (optionOr (listHead (optionOr (listTail pt) (list))) cy)) (dx (- x cx)) (dy (- y cy)) (r (sqrt (+ (* dx dx) (* dy dy)))) (diff (abs (- r avgR)))] (calcRadiusVariance tail cx cy avgR (+ accDiff diff) (+ count 1))))

fn isStraightLine p1: (List F64) p2: (List F64) p3: (List F64) tolerance: F64 -> Bool
  (let [(x1 (optionOr (listHead p1) 0.0)) (y1 (optionOr (listHead (optionOr (listTail p1) (list))) 0.0)) (x2 (optionOr (listHead p2) 0.0)) (y2 (optionOr (listHead (optionOr (listTail p2) (list))) 0.0)) (x3 (optionOr (listHead p3) 0.0)) (y3 (optionOr (listHead (optionOr (listTail p3) (list))) 0.0)) (area (* 0.5 (- (* x1 (- y2 y3)) (+ (* x2 (- y1 y3)) (* x3 (- y1 y2))))))] (< (abs area) tolerance))
