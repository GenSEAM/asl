(module asl-vector/emitter
  :d "Minimal-token SVG and pure-ASN vector generator with coordinate quantization and path optimization."
  :x [emitSvgHeader
      emitSvgFooter
      emitPathElement
      emitRectElement
      emitCircleElement
      emitVectorAsset
      quantizeCoord])

(df roundVal [(v F64)] -> Int
  (:d "Rounds float to nearest integer using int64-from-float.")
  (if (< v 0.0)
      (int64-from-float (- v 0.5))
      (int64-from-float (+ v 0.5))))

(df quantizeCoord [(val F64) (precision F64)] -> F64
  (:d "Quantizes coordinate to specified precision (e.g. 0.5 or 1.0) to eliminate token bloat.")
  (let [(scaled (/ val precision))
        (rounded (float (roundVal scaled)))]
    (* rounded precision)))

(df emitSvgHeader [(width Int) (height Int) (viewBox String)] -> String
  (:d "Emits standard XML/SVG envelope with non-scaling-stroke.")
  (str "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"" width "\" height=\"" height "\" viewBox=\"" viewBox "\">"))

(df emitSvgFooter [] -> String
  "</svg>")

(df emitRectElement [(x F64) (y F64) (w F64) (h F64) (fill String) (stroke String) (sw F64)] -> String
  (str "<rect x=\"" (roundVal x) "\" y=\"" (roundVal y) "\" width=\"" (roundVal w) "\" height=\"" (roundVal h)
       "\" fill=\"" fill "\" stroke=\"" stroke "\" stroke-width=\"" sw "\"/>"))

(df emitCircleElement [(cx F64) (cy F64) (r F64) (fill String) (stroke String) (sw F64)] -> String
  (str "<circle cx=\"" (roundVal cx) "\" cy=\"" (roundVal cy) "\" r=\"" (roundVal r)
       "\" fill=\"" fill "\" stroke=\"" stroke "\" stroke-width=\"" sw "\"/>"))

(df emitPathElement [(poly (List (List F64))) (fill String) (stroke String) (sw F64)] -> String
  (:d "Emits minimal token <path> with relative commands and Z closure.")
  (let [(d (polyToPathData poly))]
    (str "<path d=\"" d "\" fill=\"" fill "\" stroke=\"" stroke "\" stroke-width=\"" sw "\" vector-effect=\"non-scaling-stroke\"/>")))

(df polyToPathData [(poly (List (List F64)))] -> String
  (if (list-empty? poly)
      ""
      (let [(firstPt (option-or (list-head poly) (list 0.0 0.0)))
            (startX (roundVal (option-or (list-head firstPt) 0.0)))
            (startY (roundVal (option-or (list-head (option-or (list-tail firstPt) (list))) 0.0)))
            (restPts (option-or (list-tail poly) (list)))
            (moveCmd (str "M" startX " " startY))
            (lineCmds (pointsToLineCommands restPts startX startY))]
        (str moveCmd lineCmds "Z"))))

(df pointsToLineCommands [(pts (List (List F64))) (prevX Int) (prevY Int)] -> String
  (if (list-empty? pts)
      ""
      (let [(pt (option-or (list-head pts) (list 0.0 0.0)))
            (tail (option-or (list-tail pts) (list)))
            (curX (roundVal (option-or (list-head pt) 0.0)))
            (curY (roundVal (option-or (list-head (option-or (list-tail pt) (list))) 0.0)))
            (cmd (if (== curY prevY)
                     (str "H" curX)
                     (if (== curX prevX)
                         (str "V" curY)
                         (str "L" curX " " curY))))]
        (str " " cmd (pointsToLineCommands tail curX curY)))))

(df emitVectorAsset [(elements (List String)) (width Int) (height Int)] -> String
  (:d "Assembles full SVG document from rendered element strings.")
  (let [(header (emitSvgHeader width height (str "0 0 " width " " height)))
        (body (joinStrings elements "\n  "))
        (footer (emitSvgFooter))]
    (str header "\n  " body "\n" footer)))

(df joinStrings [(items (List String)) (sep String)] -> String
  (if (list-empty? items)
      ""
      (let [(first (option-or (list-head items) ""))
            (tail (option-or (list-tail items) (list)))]
        (if (list-empty? tail)
            first
            (str first sep (joinStrings tail sep))))))
