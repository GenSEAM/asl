(module asl-vector/marching :x [traceMaskContours polygonBBox polygonArea isPointInPolygon])

fn traceMaskContours grid: (List (List Int)) width: Int height: Int threshold: Int -> (List (List (List F64)))
  (let [(segments (scanGridSegments grid width height threshold))] (assemblePolylines segments))

fn scanGridSegments grid: (List (List Int)) width: Int height: Int threshold: Int -> (List (List F64))
  (scanRows grid width height threshold 0 (list))

fn scanRows grid: (List (List Int)) width: Int height: Int threshold: Int y: Int acc: (List (List F64)) -> (List (List F64))
  (if (>= y (- height 1)) acc (let [(rowAcc (scanCols grid width height threshold 0 y acc))] (scanRows grid width height threshold (+ y 1) rowAcc)))

fn scanCols grid: (List (List Int)) width: Int height: Int threshold: Int x: Int y: Int acc: (List (List F64)) -> (List (List F64))
  (if (>= x (- width 1)) acc (let [(cellSegments (evalMarchingCell grid x y threshold)) (nextAcc (listAppend acc cellSegments))] (scanCols grid width height threshold (+ x 1) y nextAcc)))

fn evalMarchingCell grid: (List (List Int)) x: Int y: Int thresh: Int -> (List (List F64))
  (let [(vTL (if (>= (getPixel grid x y) thresh) 1 0)) (vTR (if (>= (getPixel grid (+ x 1) y) thresh) 2 0)) (vBR (if (>= (getPixel grid (+ x 1) (+ y 1)) thresh) 4 0)) (vBL (if (>= (getPixel grid x (+ y 1)) thresh) 8 0)) (caseId (+ vTL (+ vTR (+ vBR vBL)))) (fx (int64ToFloat64 x)) (fy (int64ToFloat64 y))] (cellCaseToSegments caseId fx fy))

fn getPixel grid: (List (List Int)) x: Int y: Int -> Int
  (let [(rowOpt (listGet grid y))] (mt rowOpt ((some row) (let [(valOpt (listGet row x))] (mt valOpt ((some v) v) ((none) 0)))) ((none) 0)))

fn cellCaseToSegments caseId: Int x: F64 y: F64 -> (List (List F64))
  (let [(topX (+ x 0.5)) (topY y) (rightX (+ x 1.0)) (rightY (+ y 0.5)) (bottomX (+ x 0.5)) (bottomY (+ y 1.0)) (leftX x) (leftY (+ y 0.5))] (if (or (== caseId 0) (== caseId 15)) (list) (if (or (== caseId 1) (== caseId 14)) (list (list leftX leftY topX topY)) (if (or (== caseId 2) (== caseId 13)) (list (list topX topY rightX rightY)) (if (or (== caseId 3) (== caseId 12)) (list (list leftX leftY rightX rightY)) (if (or (== caseId 4) (== caseId 11)) (list (list rightX rightY bottomX bottomY)) (if (== caseId 5) (list (list leftX leftY topX topY) (list rightX rightY bottomX bottomY)) (if (or (== caseId 6) (== caseId 9)) (list (list topX topY bottomX bottomY)) (if (or (== caseId 7) (== caseId 8)) (list (list leftX leftY bottomX bottomY)) (if (== caseId 10) (list (list topX topY rightX rightY) (list leftX leftY bottomX bottomY)) (list)))))))))))

fn assemblePolylines segments: (List (List F64)) -> (List (List (List F64)))
  (if (listEmpty? segments) (list) (chainSegmentsHelper segments (list)))

fn chainSegmentsHelper remaining: (List (List F64)) polygons: (List (List (List F64))) -> (List (List (List F64)))
  (if (listEmpty? remaining) polygons (let [(firstSeg (optionOr (listHead remaining) (list))) (restSegs (optionOr (listTail remaining) (list))) (startX (optionOr (listGet firstSeg 0) 0.0)) (startY (optionOr (listGet firstSeg 1) 0.0)) (endX (optionOr (listGet firstSeg 2) 0.0)) (endY (optionOr (listGet firstSeg 3) 0.0)) (initialPoly (list (list startX startY) (list endX endY))) (buildRes (growPolyline initialPoly restSegs endX endY)) (completedPoly (optionOr (listGet buildRes 0) initialPoly)) (leftoverSegs (optionOr (listGet buildRes 1) (list)))] (chainSegmentsHelper leftoverSegs (listAppend polygons (list completedPoly)))))

fn growPolyline poly: (List (List F64)) segs: (List (List F64)) currX: F64 currY: F64 -> (List (List Any))
  (let [(findRes (findConnectingSegment segs currX currY))] (mt findRes ((some matchData) (let [(nextPoint (optionOr (listGet matchData 0) (list currX currY))) (remainingSegs (optionOr (listGet matchData 1) (list))) (nx (optionOr (listGet nextPoint 0) currX)) (ny (optionOr (listGet nextPoint 1) currY)) (updatedPoly (listAppend poly (list nextPoint)))] (growPolyline updatedPoly remainingSegs nx ny))) ((none) (list poly segs))))

fn findConnectingSegment segs: (List (List F64)) targetX: F64 targetY: F64 -> (Option (List Any))
  (findConnectingHelper segs targetX targetY (list))

fn findConnectingHelper segs: (List (List F64)) targetX: F64 targetY: F64 passed: (List (List F64)) -> (Option (List Any))
  (if (listEmpty? segs) (none) (let [(seg (optionOr (listHead segs) (list))) (rest (optionOr (listTail segs) (list))) (x1 (optionOr (listGet seg 0) -999.0)) (y1 (optionOr (listGet seg 1) -999.0)) (x2 (optionOr (listGet seg 2) -999.0)) (y2 (optionOr (listGet seg 3) -999.0)) (eps 0.01)] (if (and (< (abs (- x1 targetX)) eps) (< (abs (- y1 targetY)) eps)) (some (list (list x2 y2) (listAppend passed rest))) (if (and (< (abs (- x2 targetX)) eps) (< (abs (- y2 targetY)) eps)) (some (list (list x1 y1) (listAppend passed rest))) (findConnectingHelper rest targetX targetY (listAppend passed (list seg)))))))

fn polygonBBox poly: (List (List F64)) -> (List F64)
  (if (listEmpty? poly) (list 0.0 0.0 0.0 0.0) (let [(firstPt (optionOr (listHead poly) (list 0.0 0.0))) (fx (optionOr (listHead firstPt) 0.0)) (fy (optionOr (listHead (optionOr (listTail firstPt) (list))) 0.0))] (bboxHelper poly fx fy fx fy)))

fn bboxHelper pts: (List (List F64)) minX: F64 minY: F64 maxX: F64 maxY: F64 -> (List F64)
  (if (listEmpty? pts) (list minX minY maxX maxY) (let [(pt (optionOr (listHead pts) (list minX minY))) (tail (optionOr (listTail pts) (list))) (px (optionOr (listHead pt) minX)) (py (optionOr (listHead (optionOr (listTail pt) (list))) minY)) (newMinX (if (< px minX) px minX)) (newMinY (if (< py minY) py minY)) (newMaxX (if (> px maxX) px maxX)) (newMaxY (if (> py maxY) py maxY))] (bboxHelper tail newMinX newMinY newMaxX newMaxY)))

fn polygonArea poly: (List (List F64)) -> F64
  (if (< (listLength poly) 3) 0.0 (let [(sum (shoelaceHelper poly 0.0))] (/ (abs sum) 2.0)))

fn shoelaceHelper pts: (List (List F64)) acc: F64 -> F64
  (if (or (listEmpty? pts) (listEmpty? (optionOr (listTail pts) (list)))) acc (let [(p1 (optionOr (listHead pts) (list 0.0 0.0))) (tail (optionOr (listTail pts) (list))) (p2 (optionOr (listHead tail) (list 0.0 0.0))) (x1 (optionOr (listHead p1) 0.0)) (y1 (optionOr (listHead (optionOr (listTail p1) (list))) 0.0)) (x2 (optionOr (listHead p2) 0.0)) (y2 (optionOr (listHead (optionOr (listTail p2) (list))) 0.0)) (cross (- (* x1 y2) (* x2 y1)))] (shoelaceHelper tail (+ acc cross))))

fn isPointInPolygon px: F64 py: F64 poly: (List (List F64)) -> Bool
  (rayCastHelper px py poly false)

fn rayCastHelper px: F64 py: F64 pts: (List (List F64)) inside: Bool -> Bool
  (if (or (listEmpty? pts) (listEmpty? (optionOr (listTail pts) (list)))) inside (let [(p1 (optionOr (listHead pts) (list 0.0 0.0))) (tail (optionOr (listTail pts) (list))) (p2 (optionOr (listHead tail) (list 0.0 0.0))) (x1 (optionOr (listHead p1) 0.0)) (y1 (optionOr (listHead (optionOr (listTail p1) (list))) 0.0)) (x2 (optionOr (listHead p2) 0.0)) (y2 (optionOr (listHead (optionOr (listTail p2) (list))) 0.0)) (dy (- y2 y1)) (crosses (if (and (!= (> y1 py) (> y2 py)) (!= dy 0.0)) (< px (+ x1 (/ (* (- x2 x1) (- py y1)) dy))) false))] (rayCastHelper px py tail (if crosses (not inside) inside))))
