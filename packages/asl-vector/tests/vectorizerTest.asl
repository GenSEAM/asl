(module asl-vector/tests/vectorizerTest :x [testColorMetrics testColorQuantization testMarchingSquares testPolygonGeometry testPrimitiveDetection testSvgEmitter testFullVectorizerPipeline runTests] :i [(color :a c) (marching :a m) (primitives :a p) (emitter :a e) (vectorizer :a v)])

fn testColorMetrics -> Bool
  (let [(whiteLab (c/rgbToLab 255 255 255)) (blackLab (c/rgbToLab 0 0 0)) (redLab (c/rgbToLab 255 0 0)) (greenLab (c/rgbToLab 0 255 0)) (distWhiteBlack (c/labDeltaE whiteLab blackLab)) (distRedGreen (c/labDeltaE redLab greenLab))] (assert (> distWhiteBlack 50.0) "white and black have high deltaE") (assert (> distRedGreen 40.0) "red and green have distinct deltaE") (refute (< distWhiteBlack 10.0) "white and black are not identical") true)

fn testColorQuantization -> Bool
  (let [(palette (list (list 0 0 0) (list 255 255 255) (list 255 0 0))) (darkRed (list 200 10 10)) (matched (c/quantizeColor darkRed palette)) (hexStr (c/formatHexColor matched))] (assert (== hexStr "#ff0000") "dark red quantizes to primary red") (refute (== hexStr "#000000") "dark red does not quantize to black") (assert (== (c/formatHexColor (list 0 0 0)) "#000000") "black hex format") (assert (== (c/formatHexColor (list 255 255 255)) "#ffffff") "white hex format") true)

fn testMarchingSquares -> Bool
  (let [(row0 (list 0 0 0 0 0)) (row1 (list 0 1 1 1 0)) (row2 (list 0 1 1 1 0)) (row3 (list 0 1 1 1 0)) (row4 (list 0 0 0 0 0)) (grid (list row0 row1 row2 row3 row4)) (contours (m/traceMaskContours grid 5 5 1))] (assert (> (listLength contours) 0) "marching squares extracts at least 1 contour") (let [(poly (optionOr (listHead contours) (list))) (area (m/polygonArea poly))] (assert (> area 4.0) "extracted square polygon has substantial area") (refute (< area 1.0) "contour is not degenerate noise")) true)

fn testPolygonGeometry -> Bool
  (let [(poly (list (list 0.0 0.0) (list 10.0 0.0) (list 10.0 10.0) (list 0.0 10.0))) (bbox (m/polygonBBox poly)) (area (m/polygonArea poly)) (inside (m/isPointInPolygon 5.0 5.0 poly)) (outside (m/isPointInPolygon 15.0 15.0 poly))] (assert (== area 100.0) "shoelace area of 10x10 square is 100") (assert (== (optionOr (listGet bbox 0) -1.0) 0.0) "minX is 0") (assert (== (optionOr (listGet bbox 2) -1.0) 10.0) "maxX is 10") (assert inside "point (5,5) is inside square") (refute outside "point (15,15) is outside square") true)

fn testPrimitiveDetection -> Bool
  (let [(rectPoly (list (list 2.0 2.0) (list 8.0 2.0) (list 8.0 6.0) (list 2.0 6.0) (list 2.0 2.0))) (rectRes (p/detectPrimitive rectPoly 0.5))] (mt rectRes ((some rData) (let [(kind (optionOr (listGet rData 0) ""))] (assert (== kind ":rect") "rectangle contour detected as :rect") (refute (== kind ":circle") "rectangle contour is not :circle"))) ((none) (assert false "rectangle should be detected"))) true)

fn testSvgEmitter -> Bool
  (let [(rectEl (e/emitRectElement 10.0 20.0 50.0 30.0 "#ff0000" "#000000" 1.5)) (circEl (e/emitCircleElement 25.0 25.0 15.0 "#00ff00" "none" 0.0)) (poly (list (list 0.0 0.0) (list 10.0 0.0) (list 10.0 10.0))) (pathEl (e/emitPathElement poly "#0000ff" "none" 0.0)) (doc (e/emitVectorAsset (list rectEl circEl pathEl) 100 100))] (assert (stringContains? rectEl "<rect x=\"10\" y=\"20\" width=\"50\" height=\"30\"") "rect element formatted") (assert (stringContains? circEl "<circle cx=\"25\" cy=\"25\" r=\"15\"") "circle element formatted") (assert (stringContains? pathEl "d=\"M0 0 H10 V10Z\"") "path uses H/V coordinate shortcuts") (assert (stringContains? doc "<svg xmlns=\"http://www.w3.org/2000/svg\"") "full svg doc formatted") (refute (stringContains? doc "undefined") "svg has zero undefined tokens") true)

fn testFullVectorizerPipeline -> Bool
  (let [(row0 (list 0 0 0 0 0 0)) (row1 (list 0 1 1 1 1 0)) (row2 (list 0 1 1 1 1 0)) (row3 (list 0 1 1 1 1 0)) (row4 (list 0 1 1 1 1 0)) (row5 (list 0 0 0 0 0 0)) (grid (list row0 row1 row2 row3 row4 row5)) (palette (list (list 0 128 255))) (svgDoc (v/vectorizeBitmap grid 6 6 palette))] (assert (> (stringLength svgDoc) 50) "vectorizer generates non-empty SVG") (assert (stringContains? svgDoc "<svg") "svg opening tag present") (assert (stringContains? svgDoc "</svg>") "svg closing tag present") (assert (stringContains? svgDoc "viewBox=\"0 0 6 6\"") "viewBox matches grid dimensions") (assert (stringContains? svgDoc "fill=\"#0080ff\"") "quantized palette hex color applied") (refute (stringContains? svgDoc "error") "vectorizer produces no error tokens") true)

fn runTests -> Bool
  (and (testColorMetrics) (and (testColorQuantization) (and (testMarchingSquares) (and (testPolygonGeometry) (and (testPrimitiveDetection) (and (testSvgEmitter) (testFullVectorizerPipeline)))))))
