(module asl-vector/vectorizer
  :d "Pure AgentScript end-to-end Image-to-SVG vector synthesizer with primitive-first optimization."
  :x [vectorizeBitmap
      vectorizeLayer
      extractColorLayers]
  :i [(color :a c)
      (marching :a m)
      (primitives :a p)
      (emitter :a e)])

(df vectorizeBitmap [(grid (List (List Int))) (width Int) (height Int) (palette (List (List Int)))] -> String
  (:d "High-level raster-to-SVG vectorizer pipeline.")
  (let [(layers (extractColorLayers grid width height palette))
        (elements (vectorizeAllLayers layers width height (list)))]
    (e/emitVectorAsset elements width height)))

(df extractColorLayers [(grid (List (List Int))) (width Int) (height Int) (palette (List (List Int)))] -> (List (List Any))
  (:d "Separates 2D raster grid into discrete binary color mask layers.")
  (extractLayersHelper grid width height palette (list)))

(df extractLayersHelper [(grid (List (List Int))) (width Int) (height Int) (palette (List (List Int))) (acc (List (List Any)))] -> (List (List Any))
  (if (list-empty? palette)
      acc
      (let [(color (option-or (list-head palette) (list 0 0 0)))
            (tail (option-or (list-tail palette) (list)))
            (mask (buildColorMask grid width height color))
            (layerData (list color mask))
            (nextAcc (list-concat acc (list layerData)))]
        (extractLayersHelper grid width height tail nextAcc))))

(df buildColorMask [(grid (List (List Int))) (width Int) (height Int) (targetColor (List Int))] -> (List (List Int))
  (:d "Builds a binary mask where cell is 1 if pixel equals targetColor index/value, else 0.")
  (buildMaskRows grid targetColor 0 (list)))

(df buildMaskRows [(grid (List (List Int))) (targetColor (List Int)) (y Int) (acc (List (List Int)))] -> (List (List Int))
  (if (>= y (list-length grid))
      acc
      (let [(row (option-or (list-get grid y) (list)))
            (maskRow (buildMaskCols row targetColor 0 (list)))
            (nextAcc (list-concat acc (list maskRow)))]
        (buildMaskRows grid targetColor (+ y 1) nextAcc))))

(df buildMaskCols [(row (List Int)) (targetColor (List Int)) (x Int) (acc (List Int))] -> (List Int)
  (if (>= x (list-length row))
      acc
      (let [(val (option-or (list-get row x) 0))
            (match (if (> val 0) 1 0))
            (nextAcc (list-concat acc (list match)))]
        (buildMaskCols row targetColor (+ x 1) nextAcc))))

(df vectorizeAllLayers [(layers (List (List Any))) (width Int) (height Int) (acc (List String))] -> (List String)
  (if (list-empty? layers)
      acc
      (let [(layer (option-or (list-head layers) (list)))
            (tail (option-or (list-tail layers) (list)))
            (colorRgb (option-or (list-get layer 0) (list 0 0 0)))
            (maskGrid (option-or (list-get layer 1) (list)))
            (layerElements (vectorizeLayer maskGrid width height colorRgb))
            (nextAcc (list-concat acc layerElements))]
        (vectorizeAllLayers tail width height nextAcc))))

(df vectorizeLayer [(mask (List (List Int))) (width Int) (height Int) (rgb (List Int))] -> (List String)
  (:d "Extracts contours for a single mask and attempts primitive-first substitution.")
  (let [(hexColor (c/formatHexColor rgb))
        (contours (m/traceMaskContours mask width height 1))]
    (processContours contours hexColor (list))))

(df processContours [(contours (List (List (List F64)))) (color String) (acc (List String))] -> (List String)
  (if (list-empty? contours)
      acc
      (let [(poly (option-or (list-head contours) (list)))
            (tail (option-or (list-tail contours) (list)))
            (area (m/polygonArea poly))]
        (if (< area 2.0)
            (processContours tail color acc)
            (let [(primOpt (p/detectPrimitive poly 1.5))
                  (elementStr
                    (mt primOpt
                      ((some primData)
                       (let [(kind (option-or (list-get primData 0) ""))
                             (p1 (option-or (list-get primData 1) 0.0))
                             (p2 (option-or (list-get primData 2) 0.0))
                             (p3 (option-or (list-get primData 3) 0.0))]
                         (if (== kind ":circle")
                             (e/emitCircleElement p1 p2 p3 color "none" 0.0)
                             (if (== kind ":rect")
                                 (let [(p4 (option-or (list-get primData 4) 0.0))]
                                   (e/emitRectElement p1 p2 p3 p4 color "none" 0.0))
                                 (e/emitPathElement poly color "none" 0.0)))))
                      ((none)
                       (e/emitPathElement poly color "none" 0.0))))
                  (nextAcc (list-concat acc (list elementStr)))]
              (processContours tail color nextAcc))))))
