(module asl-vector/emitter :x [emitSvgHeader emitSvgFooter emitPathElement emitRectElement emitCircleElement emitVectorAsset quantizeCoord])

fn roundVal v: F64 -> Int
  (let [(n (float64ToInt64 (if (< v 0.0) (- v 0.5) (+ v 0.5))))]
    (do (assert (some? n) "roundVal: v must be finite and within Int64")
        (optionOr n 0)))

fn quantizeCoord val: F64 precision: F64 -> F64
  (let [(scaled (/ val precision)) (rounded (int64ToFloat64 (roundVal scaled)))] (* rounded precision))

fn emitSvgHeader width: Int height: Int viewBox: String -> String
  (str "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"" width "\" height=\"" height "\" viewBox=\"" viewBox "\">")

fn emitSvgFooter -> String
  "</svg>"

fn emitRectElement x: F64 y: F64 w: F64 h: F64 fill: String stroke: String sw: F64 -> String
  (str "<rect x=\"" (roundVal x) "\" y=\"" (roundVal y) "\" width=\"" (roundVal w) "\" height=\"" (roundVal h) "\" fill=\"" fill "\" stroke=\"" stroke "\" stroke-width=\"" sw "\"/>")

fn emitCircleElement cx: F64 cy: F64 r: F64 fill: String stroke: String sw: F64 -> String
  (str "<circle cx=\"" (roundVal cx) "\" cy=\"" (roundVal cy) "\" r=\"" (roundVal r) "\" fill=\"" fill "\" stroke=\"" stroke "\" stroke-width=\"" sw "\"/>")

fn emitPathElement poly: (List (List F64)) fill: String stroke: String sw: F64 -> String
  (let [(d (polyToPathData poly))] (str "<path d=\"" d "\" fill=\"" fill "\" stroke=\"" stroke "\" stroke-width=\"" sw "\" vector-effect=\"non-scaling-stroke\"/>"))

fn polyToPathData poly: (List (List F64)) -> String
  (if (listEmpty? poly) "" (let [(firstPt (optionOr (listHead poly) (list 0.0 0.0))) (startX (roundVal (optionOr (listHead firstPt) 0.0))) (startY (roundVal (optionOr (listHead (optionOr (listTail firstPt) (list))) 0.0))) (restPts (optionOr (listTail poly) (list))) (moveCmd (str "M" startX " " startY)) (lineCmds (pointsToLineCommands restPts startX startY))] (str moveCmd lineCmds "Z")))

fn pointsToLineCommands pts: (List (List F64)) prevX: Int prevY: Int -> String
  (if (listEmpty? pts) "" (let [(pt (optionOr (listHead pts) (list 0.0 0.0))) (tail (optionOr (listTail pts) (list))) (curX (roundVal (optionOr (listHead pt) 0.0))) (curY (roundVal (optionOr (listHead (optionOr (listTail pt) (list))) 0.0))) (cmd (if (== curY prevY) (str "H" curX) (if (== curX prevX) (str "V" curY) (str "L" curX " " curY))))] (str " " cmd (pointsToLineCommands tail curX curY))))

fn emitVectorAsset elements: (List String) width: Int height: Int -> String
  (let [(header (emitSvgHeader width height (str "0 0 " width " " height))) (body (joinStrings elements "\n  ")) (footer (emitSvgFooter))] (str header "\n  " body "\n" footer))

fn joinStrings items: (List String) sep: String -> String
  (if (listEmpty? items) "" (let [(first (optionOr (listHead items) "")) (tail (optionOr (listTail items) (list)))] (if (listEmpty? tail) first (str first sep (joinStrings tail sep)))))
