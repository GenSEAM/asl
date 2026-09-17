(module asl-vector/tests/vectorizerTest
  :d "Unit tests for pure AgentScript Image-to-SVG vectorizer and gestalt primitives."
  :x [testColorMetrics
      testColorQuantization
      testMarchingSquares
      testPolygonGeometry
      testPrimitiveDetection
      testSvgEmitter
      testFullVectorizerPipeline
      runTests]
  :i [(color :a c)
      (marching :a m)
      (primitives :a p)
      (emitter :a e)
      (vectorizer :a v)])

(df testColorMetrics [] -> Bool
  (:d "Asserts RGB to Lab conversion and Delta-E perceptual distance.")
  (let [(whiteLab (c/rgbToLab 255 255 255))
        (blackLab (c/rgbToLab 0 0 0))
        (redLab (c/rgbToLab 255 0 0))
        (greenLab (c/rgbToLab 0 255 0))
        (distWhiteBlack (c/labDeltaE whiteLab blackLab))
        (distRedGreen (c/labDeltaE redLab greenLab))]
    (assert (> distWhiteBlack 50.0) "white and black have high deltaE")
    (assert (> distRedGreen 40.0) "red and green have distinct deltaE")
    (refute (< distWhiteBlack 10.0) "white and black are not identical")
    true))

(df testColorQuantization [] -> Bool
  (:d "Asserts palette nearest-neighbor matching and hex formatting.")
  (let [(palette (list (list 0 0 0) (list 255 255 255) (list 255 0 0)))
        (darkRed (list 200 10 10))
        (matched (c/quantizeColor darkRed palette))
        (hexStr (c/formatHexColor matched))]
    (assert (== hexStr "#ff0000") "dark red quantizes to primary red")
    (refute (== hexStr "#000000") "dark red does not quantize to black")
    (assert (== (c/formatHexColor (list 0 0 0)) "#000000") "black hex format")
    (assert (== (c/formatHexColor (list 255 255 255)) "#ffffff") "white hex format")
    true))

(df testMarchingSquares [] -> Bool
  (:d "Asserts contour extraction from synthetic 2D binary grid.")
  (let [(row0 (list 0 0 0 0 0))
        (row1 (list 0 1 1 1 0))
        (row2 (list 0 1 1 1 0))
        (row3 (list 0 1 1 1 0))
        (row4 (list 0 0 0 0 0))
        (grid (list row0 row1 row2 row3 row4))
        (contours (m/traceMaskContours grid 5 5 1))]
    (assert (> (list-length contours) 0) "marching squares extracts at least 1 contour")
    (let [(poly (option-or (list-head contours) (list)))
          (area (m/polygonArea poly))]
      (assert (> area 4.0) "extracted square polygon has substantial area")
      (refute (< area 1.0) "contour is not degenerate noise"))
    true))

(df testPolygonGeometry [] -> Bool
  (:d "Asserts polygon bounding box, area calculation, and point inclusion.")
  (let [(poly (list (list 0.0 0.0) (list 10.0 0.0) (list 10.0 10.0) (list 0.0 10.0)))
        (bbox (m/polygonBBox poly))
        (area (m/polygonArea poly))
        (inside (m/isPointInPolygon 5.0 5.0 poly))
        (outside (m/isPointInPolygon 15.0 15.0 poly))]
    (assert (== area 100.0) "shoelace area of 10x10 square is 100")
    (assert (== (option-or (list-get bbox 0) -1.0) 0.0) "minX is 0")
    (assert (== (option-or (list-get bbox 2) -1.0) 10.0) "maxX is 10")
    (assert inside "point (5,5) is inside square")
    (refute outside "point (15,15) is outside square")
    true))

(df testPrimitiveDetection [] -> Bool
  (:d "Asserts geometric primitive substitution for rect and circle.")
  (let [(rectPoly (list (list 2.0 2.0) (list 8.0 2.0) (list 8.0 6.0) (list 2.0 6.0) (list 2.0 2.0)))
        (rectRes (p/detectPrimitive rectPoly 0.5))]
    (mt rectRes
      ((some rData)
       (let [(kind (option-or (list-get rData 0) ""))]
         (assert (== kind ":rect") "rectangle contour detected as :rect")
         (refute (== kind ":circle") "rectangle contour is not :circle")))
      ((none) (assert false "rectangle should be detected")))
    true))

(df testSvgEmitter [] -> Bool
  (:d "Asserts minimal-token SVG emission with non-scaling strokes and relative commands.")
  (let [(rectEl (e/emitRectElement 10.0 20.0 50.0 30.0 "#ff0000" "#000000" 1.5))
        (circEl (e/emitCircleElement 25.0 25.0 15.0 "#00ff00" "none" 0.0))
        (poly (list (list 0.0 0.0) (list 10.0 0.0) (list 10.0 10.0)))
        (pathEl (e/emitPathElement poly "#0000ff" "none" 0.0))
        (doc (e/emitVectorAsset (list rectEl circEl pathEl) 100 100))]
    (assert (string-contains? rectEl "<rect x=\"10\" y=\"20\" width=\"50\" height=\"30\"") "rect element formatted")
    (assert (string-contains? circEl "<circle cx=\"25\" cy=\"25\" r=\"15\"") "circle element formatted")
    (assert (string-contains? pathEl "d=\"M0 0 H10 V10Z\"") "path uses H/V coordinate shortcuts")
    (assert (string-contains? doc "<svg xmlns=\"http://www.w3.org/2000/svg\"") "full svg doc formatted")
    (refute (string-contains? doc "undefined") "svg has zero undefined tokens")
    true))

(df testFullVectorizerPipeline [] -> Bool
  (:d "Asserts full end-to-end raster to SVG synthesis with primitive substitution.")
  (let [(row0 (list 0 0 0 0 0 0))
        (row1 (list 0 1 1 1 1 0))
        (row2 (list 0 1 1 1 1 0))
        (row3 (list 0 1 1 1 1 0))
        (row4 (list 0 1 1 1 1 0))
        (row5 (list 0 0 0 0 0 0))
        (grid (list row0 row1 row2 row3 row4 row5))
        (palette (list (list 0 128 255)))
        (svgDoc (v/vectorizeBitmap grid 6 6 palette))]
    (assert (> (string-length svgDoc) 50) "vectorizer generates non-empty SVG")
    (assert (string-contains? svgDoc "<svg") "svg opening tag present")
    (assert (string-contains? svgDoc "</svg>") "svg closing tag present")
    (assert (string-contains? svgDoc "viewBox=\"0 0 6 6\"") "viewBox matches grid dimensions")
    (assert (string-contains? svgDoc "fill=\"#0080ff\"") "quantized palette hex color applied")
    (refute (string-contains? svgDoc "error") "vectorizer produces no error tokens")
    true))

(df runTests [] -> Bool
  (and (testColorMetrics)
  (and (testColorQuantization)
  (and (testMarchingSquares)
  (and (testPolygonGeometry)
  (and (testPrimitiveDetection)
  (and (testSvgEmitter)
       (testFullVectorizerPipeline))))))))
