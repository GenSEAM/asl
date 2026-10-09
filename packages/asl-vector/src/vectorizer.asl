(module asl-vector/vectorizer
  :x [vectorizeBitmap vectorizeLayer extractColorLayers]
  :i [(color :a c) (marching :a m) (primitives :a p) (emitter :a e)])

fn vectorizeBitmap grid: (List (List Int)) width: Int height: Int palette: (List (List Int)) -> String
  (let [(layers (extractColorLayers grid width height palette))
        (elements (vectorizeAllLayers layers width height (list)))]
    (e/emitVectorAsset elements width height))

fn extractColorLayers grid: (List (List Int)) width: Int height: Int palette: (List (List Int)) -> (List (List Any))
  (extractLayersHelper grid width height palette (list))

fn extractLayersHelper grid: (List (List Int)) width: Int height: Int palette: (List (List Int)) acc: (List (List Any)) -> (List (List Any))
  (if (listEmpty? palette) acc
    (let [(color (optionOr (listHead palette) (list 0 0 0)))
          (tail (optionOr (listTail palette) (list)))
          (mask (buildColorMask grid width height color))
          (layerData (list color mask))
          (nextAcc (listAppend acc (list layerData)))]
      (extractLayersHelper grid width height tail nextAcc)))

fn buildColorMask grid: (List (List Int)) width: Int height: Int targetColor: (List Int) -> (List (List Int))
  (buildMaskRows grid targetColor 0 (list))

fn buildMaskRows grid: (List (List Int)) targetColor: (List Int) y: Int acc: (List (List Int)) -> (List (List Int))
  (if (>= y (listLength grid)) acc
    (let [(row (optionOr (listGet grid y) (list)))
          (maskRow (buildMaskCols row targetColor 0 (list)))
          (nextAcc (listAppend acc (list maskRow)))]
      (buildMaskRows grid targetColor (+ y 1) nextAcc)))

fn buildMaskCols row: (List Int) targetColor: (List Int) x: Int acc: (List Int) -> (List Int)
  (if (>= x (listLength row)) acc
    (let [(val (optionOr (listGet row x) 0))
          (matched (if (> val 0) 1 0))
          (nextAcc (listAppend acc (list matched)))]
      (buildMaskCols row targetColor (+ x 1) nextAcc)))

fn vectorizeAllLayers layers: (List (List Any)) width: Int height: Int acc: (List String) -> (List String)
  (if (listEmpty? layers) acc
    (let [(layer (optionOr (listHead layers) (list)))
          (tail (optionOr (listTail layers) (list)))
          (colorRgb (optionOr (listGet layer 0) (list 0 0 0)))
          (maskGrid (optionOr (listGet layer 1) (list)))
          (layerElements (vectorizeLayer maskGrid width height colorRgb))
          (nextAcc (listAppend acc layerElements))]
      (vectorizeAllLayers tail width height nextAcc)))

fn vectorizeLayer mask: (List (List Int)) width: Int height: Int rgb: (List Int) -> (List String)
  (let [(hexColor (c/formatHexColor rgb))
        (contours (m/traceMaskContours mask width height 1))]
    (processContours contours hexColor (list)))

fn processContours contours: (List (List (List F64))) color: String acc: (List String) -> (List String)
  (if (listEmpty? contours) acc
    (let [(poly (optionOr (listHead contours) (list)))
          (tail (optionOr (listTail contours) (list)))
          (area (m/polygonArea poly))]
      (if (< area 2.0)
        (processContours tail color acc)
        (let [(primOpt (p/detectPrimitive poly 1.5))
              (elementStr (mt primOpt
                ((some primData)
                  (let [(kind (optionOr (listGet primData 0) ""))
                        (p1 (optionOr (listGet primData 1) 0.0))
                        (p2 (optionOr (listGet primData 2) 0.0))
                        (p3 (optionOr (listGet primData 3) 0.0))]
                    (if (== kind ":circle")
                      (e/emitCircleElement p1 p2 p3 color "none" 0.0)
                      (if (== kind ":rect")
                        (let [(p4 (optionOr (listGet primData 4) 0.0))]
                          (e/emitRectElement p1 p2 p3 p4 color "none" 0.0))
                        (e/emitPathElement poly color "none" 0.0)))))
                ((none) (e/emitPathElement poly color "none" 0.0))))
              (nextAcc (listAppend acc (list elementStr)))]
          (processContours tail color nextAcc)))))
