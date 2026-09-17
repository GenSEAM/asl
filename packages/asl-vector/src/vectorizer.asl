(module asl-vector/vectorizer
  :d "Pure AgentScript end-to-end Image-to-SVG vector synthesizer with primitive-first optimization."
  :x [vectorizeBitmap
      vectorizeLayer
      extractColorLayers]
  :i [(color :a c)
      (marching :a m)
      (primitives :a p)
      (emitter :a e)])

fn vectorizeBitmap grid: (List (List Int)) width: Int height: Int palette: (List (List Int)) -> String
  let layers = (extractColorLayers grid width height palette)
  let elements = (vectorizeAllLayers layers width height (list))
  e/emitVectorAsset elements width height

fn extractColorLayers grid: (List (List Int)) width: Int height: Int palette: (List (List Int)) -> (List (List Any))
  extractLayersHelper grid width height palette (list)

fn extractLayersHelper grid: (List (List Int)) width: Int height: Int palette: (List (List Int)) acc: (List (List Any)) -> (List (List Any))
  if (list-empty? palette) acc (let color = (option-or (list-head palette) (list 0 0 0)) in (let tail = (option-or (list-tail palette) (list)) in (let mask = (buildColorMask grid width height color) in (let layerData = (list color mask) in (let nextAcc = (list-concat acc (list layerData)) in (extractLayersHelper grid width height tail nextAcc))))))

fn buildColorMask grid: (List (List Int)) width: Int height: Int targetColor: (List Int) -> (List (List Int))
  buildMaskRows grid targetColor 0 (list)

fn buildMaskRows grid: (List (List Int)) targetColor: (List Int) y: Int acc: (List (List Int)) -> (List (List Int))
  if (>= y (list-length grid)) acc (let row = (option-or (list-get grid y) (list)) in (let maskRow = (buildMaskCols row targetColor 0 (list)) in (let nextAcc = (list-concat acc (list maskRow)) in (buildMaskRows grid targetColor (+ y 1) nextAcc))))

fn buildMaskCols row: (List Int) targetColor: (List Int) x: Int acc: (List Int) -> (List Int)
  if (>= x (list-length row)) acc (let val = (option-or (list-get row x) 0) in (let match = (if (> val 0) 1 0) in (let nextAcc = (list-concat acc (list match)) in (buildMaskCols row targetColor (+ x 1) nextAcc))))

fn vectorizeAllLayers layers: (List (List Any)) width: Int height: Int acc: (List String) -> (List String)
  if (list-empty? layers) acc (let layer = (option-or (list-head layers) (list)) in (let tail = (option-or (list-tail layers) (list)) in (let colorRgb = (option-or (list-get layer 0) (list 0 0 0)) in (let maskGrid = (option-or (list-get layer 1) (list)) in (let layerElements = (vectorizeLayer maskGrid width height colorRgb) in (let nextAcc = (list-concat acc layerElements) in (vectorizeAllLayers tail width height nextAcc)))))))

fn vectorizeLayer mask: (List (List Int)) width: Int height: Int rgb: (List Int) -> (List String)
  let hexColor = (c/formatHexColor rgb)
  let contours = (m/traceMaskContours mask width height 1)
  processContours contours hexColor (list)

fn processContours contours: (List (List (List F64))) color: String acc: (List String) -> (List String)
  if (list-empty? contours) acc (let poly = (option-or (list-head contours) (list)) in (let tail = (option-or (list-tail contours) (list)) in (let area = (m/polygonArea poly) in (if (< area 2.0) (processContours tail color acc) (let primOpt = (p/detectPrimitive poly 1.5) in (let elementStr = (mt primOpt ((some primData) (let kind = (option-or (list-get primData 0) "") in (let p1 = (option-or (list-get primData 1) 0.0) in (let p2 = (option-or (list-get primData 2) 0.0) in (let p3 = (option-or (list-get primData 3) 0.0) in (if (== kind ":circle") (e/emitCircleElement p1 p2 p3 color "none" 0.0) (if (== kind ":rect") (let p4 = (option-or (list-get primData 4) 0.0) in (e/emitRectElement p1 p2 p3 p4 color "none" 0.0)) (e/emitPathElement poly color "none" 0.0)))))))) ((none) (e/emitPathElement poly color "none" 0.0))) in (let nextAcc = (list-concat acc (list elementStr)) in (processContours tail color nextAcc))))))))
