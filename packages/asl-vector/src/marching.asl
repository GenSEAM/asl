(module asl-vector/marching
  :d "Marching squares 2D contour tracer and polyline extraction for binary mask grids."
  :x [traceMaskContours
      polygonBBox
      polygonArea
      isPointInPolygon])

(df traceMaskContours [(grid (List (List Int))) (width Int) (height Int) (threshold Int)] -> (List (List (List F64)))
  (:d "Traces closed contours across a 2D binary/alpha mask grid using 16-case marching squares.")
  (let [(segments (scanGridSegments grid width height threshold))]
    (assemblePolylines segments)))

(df scanGridSegments [(grid (List (List Int))) (width Int) (height Int) (threshold Int)] -> (List (List F64))
  (:d "Scans each cell and computes edge crossings [x1 y1 x2 y2].")
  (scanRows grid width height threshold 0 (list)))

(df scanRows [(grid (List (List Int))) (width Int) (height Int) (threshold Int) (y Int) (acc (List (List F64)))] -> (List (List F64))
  (if (>= y (- height 1))
      acc
      (let [(rowAcc (scanCols grid width height threshold 0 y acc))]
        (scanRows grid width height threshold (+ y 1) rowAcc))))

(df scanCols [(grid (List (List Int))) (width Int) (height Int) (threshold Int) (x Int) (y Int) (acc (List (List F64)))] -> (List (List F64))
  (if (>= x (- width 1))
      acc
      (let [(cellSegments (evalMarchingCell grid x y threshold))
            (nextAcc (list-concat acc cellSegments))]
        (scanCols grid width height threshold (+ x 1) y nextAcc))))

(df evalMarchingCell [(grid (List (List Int))) (x Int) (y Int) (thresh Int)] -> (List (List F64))
  (:d "Evaluates marching squares 4-corner bitmask for cell at (x,y).")
  (let [(vTL (if (>= (getPixel grid x y) thresh) 1 0))
        (vTR (if (>= (getPixel grid (+ x 1) y) thresh) 2 0))
        (vBR (if (>= (getPixel grid (+ x 1) (+ y 1)) thresh) 4 0))
        (vBL (if (>= (getPixel grid x (+ y 1)) thresh) 8 0))
        (caseId (+ vTL (+ vTR (+ vBR vBL))))
        (fx (float x))
        (fy (float y))]
    (cellCaseToSegments caseId fx fy)))

(df getPixel [(grid (List (List Int))) (x Int) (y Int)] -> Int
  (let [(rowOpt (list-get grid y))]
    (mt rowOpt
      ((some row)
       (let [(valOpt (list-get row x))]
         (mt valOpt
           ((some v) v)
           ((none) 0))))
      ((none) 0))))

(df cellCaseToSegments [(caseId Int) (x F64) (y F64)] -> (List (List F64))
  (:d "Maps case 0..15 to interpolated mid-edge segment pairs [x1 y1 x2 y2].")
  (let [(topX (+ x 0.5)) (topY y)
        (rightX (+ x 1.0)) (rightY (+ y 0.5))
        (bottomX (+ x 0.5)) (bottomY (+ y 1.0))
        (leftX x) (leftY (+ y 0.5))]
    (if (or (== caseId 0) (== caseId 15))
        (list)
        (if (or (== caseId 1) (== caseId 14))
            (list (list leftX leftY topX topY))
        (if (or (== caseId 2) (== caseId 13))
            (list (list topX topY rightX rightY))
        (if (or (== caseId 3) (== caseId 12))
            (list (list leftX leftY rightX rightY))
        (if (or (== caseId 4) (== caseId 11))
            (list (list rightX rightY bottomX bottomY))
        (if (== caseId 5)
            (list (list leftX leftY topX topY) (list rightX rightY bottomX bottomY))
        (if (or (== caseId 6) (== caseId 9))
            (list (list topX topY bottomX bottomY))
        (if (or (== caseId 7) (== caseId 8))
            (list (list leftX leftY bottomX bottomY))
        (if (== caseId 10)
            (list (list topX topY rightX rightY) (list leftX leftY bottomX bottomY))
            (list))))))))))))

(df assemblePolylines [(segments (List (List F64)))] -> (List (List (List F64)))
  (:d "Chains edge segments into ordered closed vertex polygons.")
  (if (list-empty? segments)
      (list)
      (chainSegmentsHelper segments (list))))

(df chainSegmentsHelper [(remaining (List (List F64))) (polygons (List (List (List F64))))] -> (List (List (List F64)))
  (if (list-empty? remaining)
      polygons
      (let [(firstSeg (option-or (list-head remaining) (list)))
            (restSegs (option-or (list-tail remaining) (list)))
            (startX (option-or (list-get firstSeg 0) 0.0))
            (startY (option-or (list-get firstSeg 1) 0.0))
            (endX (option-or (list-get firstSeg 2) 0.0))
            (endY (option-or (list-get firstSeg 3) 0.0))
            (initialPoly (list (list startX startY) (list endX endY)))
            (buildRes (growPolyline initialPoly restSegs endX endY))
            (completedPoly (option-or (list-get buildRes 0) initialPoly))
            (leftoverSegs (option-or (list-get buildRes 1) (list)))]
        (chainSegmentsHelper leftoverSegs (list-concat polygons (list completedPoly))))))

(df growPolyline [(poly (List (List F64))) (segs (List (List F64))) (currX F64) (currY F64)] -> (List (List Any))
  (let [(findRes (findConnectingSegment segs currX currY))]
    (mt findRes
      ((some matchData)
       (let [(nextPoint (option-or (list-get matchData 0) (list currX currY)))
             (remainingSegs (option-or (list-get matchData 1) (list)))
             (nx (option-or (list-get nextPoint 0) currX))
             (ny (option-or (list-get nextPoint 1) currY))
             (updatedPoly (list-concat poly (list nextPoint)))]
         (growPolyline updatedPoly remainingSegs nx ny)))
      ((none)
       (list poly segs)))))

(df findConnectingSegment [(segs (List (List F64))) (targetX F64) (targetY F64)] -> (Option (List Any))
  (findConnectingHelper segs targetX targetY (list)))

(df findConnectingHelper [(segs (List (List F64))) (targetX F64) (targetY F64) (passed (List (List F64)))] -> (Option (List Any))
  (if (list-empty? segs)
      (none)
      (let [(seg (option-or (list-head segs) (list)))
            (rest (option-or (list-tail segs) (list)))
            (x1 (option-or (list-get seg 0) -999.0))
            (y1 (option-or (list-get seg 1) -999.0))
            (x2 (option-or (list-get seg 2) -999.0))
            (y2 (option-or (list-get seg 3) -999.0))
            (eps 0.01)]
        (if (and (< (abs (- x1 targetX)) eps) (< (abs (- y1 targetY)) eps))
            (some (list (list x2 y2) (list-concat passed rest)))
            (if (and (< (abs (- x2 targetX)) eps) (< (abs (- y2 targetY)) eps))
                (some (list (list x1 y1) (list-concat passed rest)))
                (findConnectingHelper rest targetX targetY (list-concat passed (list seg))))))))

(df polygonBBox [(poly (List (List F64)))] -> (List F64)
  (:d "Computes bounding box [minX minY maxX maxY] for a polygon.")
  (if (list-empty? poly)
      (list 0.0 0.0 0.0 0.0)
      (let [(firstPt (option-or (list-head poly) (list 0.0 0.0)))
            (fx (option-or (list-head firstPt) 0.0))
            (fy (option-or (list-head (option-or (list-tail firstPt) (list))) 0.0))]
        (bboxHelper poly fx fy fx fy))))

(df bboxHelper [(pts (List (List F64))) (minX F64) (minY F64) (maxX F64) (maxY F64)] -> (List F64)
  (if (list-empty? pts)
      (list minX minY maxX maxY)
      (let [(pt (option-or (list-head pts) (list minX minY)))
            (tail (option-or (list-tail pts) (list)))
            (px (option-or (list-head pt) minX))
            (py (option-or (list-head (option-or (list-tail pt) (list))) minY))
            (newMinX (if (< px minX) px minX))
            (newMinY (if (< py minY) py minY))
            (newMaxX (if (> px maxX) px maxX))
            (newMaxY (if (> py maxY) py maxY))]
        (bboxHelper tail newMinX newMinY newMaxX newMaxY))))

(df polygonArea [(poly (List (List F64)))] -> F64
  (:d "Computes polygon area using the shoelace formula.")
  (if (< (list-length poly) 3)
      0.0
      (let [(sum (shoelaceHelper poly 0.0))]
        (/ (abs sum) 2.0))))

(df shoelaceHelper [(pts (List (List F64))) (acc F64)] -> F64
  (if (or (list-empty? pts) (list-empty? (option-or (list-tail pts) (list))))
      acc
      (let [(p1 (option-or (list-head pts) (list 0.0 0.0)))
            (tail (option-or (list-tail pts) (list)))
            (p2 (option-or (list-head tail) (list 0.0 0.0)))
            (x1 (option-or (list-head p1) 0.0))
            (y1 (option-or (list-head (option-or (list-tail p1) (list))) 0.0))
            (x2 (option-or (list-head p2) 0.0))
            (y2 (option-or (list-head (option-or (list-tail p2) (list))) 0.0))
            (cross (- (* x1 y2) (* x2 y1)))]
        (shoelaceHelper tail (+ acc cross)))))

(df isPointInPolygon [(px F64) (py F64) (poly (List (List F64)))] -> Bool
  (:d "Ray-casting point in polygon test.")
  (rayCastHelper px py poly false))

(df rayCastHelper [(px F64) (py F64) (pts (List (List F64))) (inside Bool)] -> Bool
  (if (or (list-empty? pts) (list-empty? (option-or (list-tail pts) (list))))
      inside
      (let [(p1 (option-or (list-head pts) (list 0.0 0.0)))
            (tail (option-or (list-tail pts) (list)))
            (p2 (option-or (list-head tail) (list 0.0 0.0)))
            (x1 (option-or (list-head p1) 0.0))
            (y1 (option-or (list-head (option-or (list-tail p1) (list))) 0.0))
            (x2 (option-or (list-head p2) 0.0))
            (y2 (option-or (list-head (option-or (list-tail p2) (list))) 0.0))
            (dy (- y2 y1))
            (crosses (if (and (!= (> y1 py) (> y2 py)) (!= dy 0.0))
                         (< px (+ x1 (/ (* (- x2 x1) (- py y1)) dy)))
                         false))]
        (rayCastHelper px py tail (if crosses (not inside) inside)))))
