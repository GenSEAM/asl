(module asl-ui/layout
  :d "Pure AgentScript Deterministic Two-Pass Constraint Layout Engine"
  :x [LayoutConstraints
      makeConstraints
      Dimensions
      makeDimensions
      Rect
      makeRect
      LayoutBox
      makeLayoutBox
      clampDim
      resolveConstraint
      measure
      arrange]
  :i [(asl-ui/vnode :a ui)])

(dfs LayoutConstraints
  (:f minWidth Int64)
  (:f maxWidth Int64)
  (:f minHeight Int64)
  (:f maxHeight Int64))

(dfs Dimensions
  (:f width Int64)
  (:f height Int64))

(dfs Rect
  (:f x Int64)
  (:f y Int64)
  (:f width Int64)
  (:f height Int64))

(dfs LayoutBox
  (:f tag String)
  (:f key String)
  (:f bounds Rect)
  (:f children (List LayoutBox)))

(df makeConstraints [(minWidth Int64)
                     (maxWidth Int64)
                     (minHeight Int64)
                     (maxHeight Int64)] -> LayoutConstraints
  :d "Constructs layout constraints record"
  (LayoutConstraints :minWidth minWidth
                     :maxWidth maxWidth
                     :minHeight minHeight
                     :maxHeight maxHeight))

(df makeDimensions [(width Int64) (height Int64)] -> Dimensions
  :d "Constructs 2D dimensions record"
  (Dimensions :width width :height height))

(df makeRect [(x Int64) (y Int64) (width Int64) (height Int64)] -> Rect
  :d "Constructs bounding rectangle"
  (Rect :x x :y y :width width :height height))

(df makeLayoutBox [(tag String)
                   (key String)
                   (bounds Rect)
                   (children (List LayoutBox))] -> LayoutBox
  :d "Constructs arranged layout box"
  (LayoutBox :tag tag :key key :bounds bounds :children children))

(df clampDim [(minVal Int64) (val Int64) (maxVal Int64)] -> Int64
  :d "Clamps dimension value between non-negative min and max bounds with 0-clamping"
  (let [(minSafe (if (< minVal 0) 0 minVal))]
    (if (and (>= maxVal 0) (> minSafe maxVal))
      minSafe
      (if (< val minSafe)
        minSafe
        (if (and (>= maxVal 0) (> val maxVal))
          maxVal
          (if (< val 0) 0 val))))))

(df resolveConstraint [(minVal Int64) (maxVal Int64) (intrinsicVal Int64)] -> Int64
  :d "Resolves single axis constraint against intrinsic sizing without cyclic loops"
  (if (< maxVal 0)
    (let [(minSafe (if (< minVal 0) 0 minVal))]
      (if (< intrinsicVal minSafe) minSafe intrinsicVal))
    (clampDim minVal intrinsicVal maxVal)))

(df parseDimAttr [(attrs (Map String String)) (key String) (defaultVal Int64)] -> Int64
  :d "Parses integer attribute from node attrs map with fallback"
  (let [(s (option-or (map-get attrs key) ""))]
    (if (string-empty? s)
      defaultVal
      (option-or (string-to-int64 s) defaultVal))))

(df measureChildrenColLoop [(children (List ui/VNode))
                            (constraints LayoutConstraints)
                            (currentMaxW Int64)
                            (currentTotalH Int64)
                            (isFirst Bool)
                            (gap Int64)] -> Dimensions
  :d "Recursively calculates intrinsic dimensions for column child list"
  (if (list-empty? children)
    (makeDimensions currentMaxW currentTotalH)
    (let [(child (option-or (list-head children) (ui/makeText "" "")))
          (childDim (measure child constraints))
          (childW (.-width childDim))
          (childH (.-height childDim))
          (nextMaxW (if (> childW currentMaxW) childW currentMaxW))
          (stepH (+ (if isFirst 0 gap) childH))
          (nextTotalH (+ currentTotalH stepH))
          (tail (option-or (list-tail children) (list)))]
      (measureChildrenColLoop tail constraints nextMaxW nextTotalH false gap))))

(df measureChildrenRowLoop [(children (List ui/VNode))
                            (constraints LayoutConstraints)
                            (currentTotalW Int64)
                            (currentMaxH Int64)
                            (isFirst Bool)
                            (gap Int64)] -> Dimensions
  :d "Recursively calculates intrinsic dimensions for row child list"
  (if (list-empty? children)
    (makeDimensions currentTotalW currentMaxH)
    (let [(child (option-or (list-head children) (ui/makeText "" "")))
          (childDim (measure child constraints))
          (childW (.-width childDim))
          (childH (.-height childDim))
          (stepW (+ (if isFirst 0 gap) childW))
          (nextTotalW (+ currentTotalW stepW))
          (nextMaxH (if (> childH currentMaxH) childH currentMaxH))
          (tail (option-or (list-tail children) (list)))]
      (measureChildrenRowLoop tail constraints nextTotalW nextMaxH false gap))))

(df measure [(node ui/VNode) (constraints LayoutConstraints)] -> Dimensions
  :d "First pass bottom-up measurement calculating intrinsic and constrained node dimensions"
  (let [(tag (.-tag node))
        (attrs (.-attrs node))
        (attrW (parseDimAttr attrs "width" -1))
        (attrH (parseDimAttr attrs "height" -1))
        (nodeW (.-width node))
        (nodeH (.-height node))
        (explicitW (if (> attrW 0) attrW (if (> nodeW 0) nodeW -1)))
        (explicitH (if (> attrH 0) attrH (if (> nodeH 0) nodeH -1)))
        (intrinsicPair
          (if (and (> explicitW 0) (> explicitH 0))
            (makeDimensions explicitW explicitH)
            (if (= tag "text")
              (let [(calcW (if (> explicitW 0) explicitW (* (string-length (.-text node)) 8)))
                    (calcH (if (> explicitH 0) explicitH 20))]
                (makeDimensions calcW calcH))
              (if (= tag "container")
                (let [(layoutKind (option-or (map-get attrs "layout") "column"))
                      (gap (parseDimAttr attrs "gap" 0))
                      (looseConstraints (makeConstraints 0 -1 0 -1))
                      (childDim
                        (if (= layoutKind "row")
                          (measureChildrenRowLoop (.-children node) looseConstraints 0 0 true gap)
                          (measureChildrenColLoop (.-children node) looseConstraints 0 0 true gap)))
                      (calcW (if (> explicitW 0) explicitW (.-width childDim)))
                      (calcH (if (> explicitH 0) explicitH (.-height childDim)))]
                  (makeDimensions calcW calcH))
                (let [(calcW (if (> explicitW 0) explicitW 100))
                      (calcH (if (> explicitH 0) explicitH 32))]
                  (makeDimensions calcW calcH))))))
        (finalW (resolveConstraint (.-minWidth constraints) (.-maxWidth constraints) (.-width intrinsicPair)))
        (finalH (resolveConstraint (.-minHeight constraints) (.-maxHeight constraints) (.-height intrinsicPair)))]
    (makeDimensions finalW finalH)))

(df arrangeChildrenColLoop [(children (List ui/VNode))
                            (currentX Int64)
                            (currentY Int64)
                            (gap Int64)
                            (acc (List LayoutBox))] -> (List LayoutBox)
  :d "Recursively arranges children vertically in column layout"
  (if (list-empty? children)
    (list-reverse acc)
    (let [(child (option-or (list-head children) (ui/makeText "" "")))
          (childDim (measure child (makeConstraints 0 -1 0 -1)))
          (childW (.-width childDim))
          (childH (.-height childDim))
          (childBounds (makeRect currentX currentY childW childH))
          (arrangedChild (arrange child childBounds))
          (nextY (+ (+ currentY childH) gap))
          (tail (option-or (list-tail children) (list)))]
      (arrangeChildrenColLoop tail currentX nextY gap (list-cons arrangedChild acc)))))

(df arrangeChildrenRowLoop [(children (List ui/VNode))
                            (currentX Int64)
                            (currentY Int64)
                            (gap Int64)
                            (acc (List LayoutBox))] -> (List LayoutBox)
  :d "Recursively arranges children horizontally in row layout"
  (if (list-empty? children)
    (list-reverse acc)
    (let [(child (option-or (list-head children) (ui/makeText "" "")))
          (childDim (measure child (makeConstraints 0 -1 0 -1)))
          (childW (.-width childDim))
          (childH (.-height childDim))
          (childBounds (makeRect currentX currentY childW childH))
          (arrangedChild (arrange child childBounds))
          (nextX (+ (+ currentX childW) gap))
          (tail (option-or (list-tail children) (list)))]
      (arrangeChildrenRowLoop tail nextX currentY gap (list-cons arrangedChild acc)))))

(df arrange [(node ui/VNode) (bounds Rect)] -> LayoutBox
  :d "Second pass top-down placement arranging node and child bounding rectangles"
  (let [(tag (.-tag node))
        (key (.-key node))
        (attrs (.-attrs node))
        (layoutKind (option-or (map-get attrs "layout") "column"))
        (gap (parseDimAttr attrs "gap" 0))
        (startX (.-x bounds))
        (startY (.-y bounds))
        (arrangedChildren
          (if (= tag "container")
            (if (= layoutKind "row")
              (arrangeChildrenRowLoop (.-children node) startX startY gap (list))
              (arrangeChildrenColLoop (.-children node) startX startY gap (list)))
            (list)))]
    (makeLayoutBox tag key bounds arrangedChildren)))
