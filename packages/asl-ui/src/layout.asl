(module asl-ui/layout :x [LayoutConstraints makeConstraints Dimensions makeDimensions Rect makeRect LayoutBox makeLayoutBox clampDim resolveConstraint measure arrange] :i [(asl-ui/vnode :a ui)])

(schema LayoutConstraints (:f minWidth Int64) (:f maxWidth Int64) (:f minHeight Int64) (:f maxHeight Int64))

(schema Dimensions (:f width Int64) (:f height Int64))

(schema Rect (:f x Int64) (:f y Int64) (:f width Int64) (:f height Int64))

(schema LayoutBox (:f tag String) (:f key String) (:f bounds Rect) (:f children (List LayoutBox)))

fn makeConstraints minWidth: Int64 maxWidth: Int64 minHeight: Int64 maxHeight: Int64 -> LayoutConstraints
  (LayoutConstraints :minWidth minWidth :maxWidth maxWidth :minHeight minHeight :maxHeight maxHeight)

fn makeDimensions width: Int64 height: Int64 -> Dimensions
  (Dimensions :width width :height height)

fn makeRect x: Int64 y: Int64 width: Int64 height: Int64 -> Rect
  (Rect :x x :y y :width width :height height)

fn makeLayoutBox tag: String key: String bounds: Rect children: (List LayoutBox) -> LayoutBox
  (LayoutBox :tag tag :key key :bounds bounds :children children)

fn clampDim minVal: Int64 val: Int64 maxVal: Int64 -> Int64
  (let [(minSafe (if (< minVal 0) 0 minVal))] (if (and (>= maxVal 0) (> minSafe maxVal)) minSafe (if (< val minSafe) minSafe (if (and (>= maxVal 0) (> val maxVal)) maxVal (if (< val 0) 0 val)))))

fn resolveConstraint minVal: Int64 maxVal: Int64 intrinsicVal: Int64 -> Int64
  (if (< maxVal 0) (let [(minSafe (if (< minVal 0) 0 minVal))] (if (< intrinsicVal minSafe) minSafe intrinsicVal)) (clampDim minVal intrinsicVal maxVal))

fn parseDimAttr attrs: (Map String String) key: String defaultVal: Int64 -> Int64
  (let [(s (optionOr (mapGet attrs key) ""))] (if (stringEmpty? s) defaultVal (optionOr (stringToInt64 s) defaultVal)))

fn measureChildrenColLoop children: (List ui/VNode) constraints: LayoutConstraints currentMaxW: Int64 currentTotalH: Int64 isFirst: Bool gap: Int64 -> Dimensions
  (if (listEmpty? children) (makeDimensions currentMaxW currentTotalH) (let [(child (optionOr (listHead children) (ui/makeText "" ""))) (childDim (measure child constraints)) (childW childDim.width) (childH childDim.height) (nextMaxW (if (> childW currentMaxW) childW currentMaxW)) (stepH (+ (if isFirst 0 gap) childH)) (nextTotalH (+ currentTotalH stepH)) (tail (optionOr (listTail children) (list)))] (measureChildrenColLoop tail constraints nextMaxW nextTotalH false gap)))

fn measureChildrenRowLoop children: (List ui/VNode) constraints: LayoutConstraints currentTotalW: Int64 currentMaxH: Int64 isFirst: Bool gap: Int64 -> Dimensions
  (if (listEmpty? children) (makeDimensions currentTotalW currentMaxH) (let [(child (optionOr (listHead children) (ui/makeText "" ""))) (childDim (measure child constraints)) (childW childDim.width) (childH childDim.height) (stepW (+ (if isFirst 0 gap) childW)) (nextTotalW (+ currentTotalW stepW)) (nextMaxH (if (> childH currentMaxH) childH currentMaxH)) (tail (optionOr (listTail children) (list)))] (measureChildrenRowLoop tail constraints nextTotalW nextMaxH false gap)))

fn measure node: ui/VNode constraints: LayoutConstraints -> Dimensions
  (let [(tag node.tag) (attrs node.attrs) (attrW (parseDimAttr attrs "width" -1)) (attrH (parseDimAttr attrs "height" -1)) (nodeW node.width) (nodeH node.height) (explicitW (if (> attrW 0) attrW (if (> nodeW 0) nodeW -1))) (explicitH (if (> attrH 0) attrH (if (> nodeH 0) nodeH -1))) (intrinsicPair (if (and (> explicitW 0) (> explicitH 0)) (makeDimensions explicitW explicitH) (if (= tag "text") (let [(calcW (if (> explicitW 0) explicitW (* (stringLength node.text) 8))) (calcH (if (> explicitH 0) explicitH 20))] (makeDimensions calcW calcH)) (if (= tag "container") (let [(layoutKind (optionOr (mapGet attrs "layout") "column")) (gap (parseDimAttr attrs "gap" 0)) (looseConstraints (makeConstraints 0 -1 0 -1)) (childDim (if (= layoutKind "row") (measureChildrenRowLoop node.children looseConstraints 0 0 true gap) (measureChildrenColLoop node.children looseConstraints 0 0 true gap))) (calcW (if (> explicitW 0) explicitW childDim.width)) (calcH (if (> explicitH 0) explicitH childDim.height))] (makeDimensions calcW calcH)) (let [(calcW (if (> explicitW 0) explicitW 100)) (calcH (if (> explicitH 0) explicitH 32))] (makeDimensions calcW calcH)))))) (finalW (resolveConstraint constraints.minWidth constraints.maxWidth intrinsicPair.width)) (finalH (resolveConstraint constraints.minHeight constraints.maxHeight intrinsicPair.height))] (makeDimensions finalW finalH))

fn arrangeChildrenColLoop children: (List ui/VNode) currentX: Int64 currentY: Int64 gap: Int64 acc: (List LayoutBox) -> (List LayoutBox)
  (if (listEmpty? children) (listReverse acc) (let [(child (optionOr (listHead children) (ui/makeText "" ""))) (childDim (measure child (makeConstraints 0 -1 0 -1))) (childW childDim.width) (childH childDim.height) (childBounds (makeRect currentX currentY childW childH)) (arrangedChild (arrange child childBounds)) (nextY (+ (+ currentY childH) gap)) (tail (optionOr (listTail children) (list)))] (arrangeChildrenColLoop tail currentX nextY gap (cons arrangedChild acc))))

fn arrangeChildrenRowLoop children: (List ui/VNode) currentX: Int64 currentY: Int64 gap: Int64 acc: (List LayoutBox) -> (List LayoutBox)
  (if (listEmpty? children) (listReverse acc) (let [(child (optionOr (listHead children) (ui/makeText "" ""))) (childDim (measure child (makeConstraints 0 -1 0 -1))) (childW childDim.width) (childH childDim.height) (childBounds (makeRect currentX currentY childW childH)) (arrangedChild (arrange child childBounds)) (nextX (+ (+ currentX childW) gap)) (tail (optionOr (listTail children) (list)))] (arrangeChildrenRowLoop tail nextX currentY gap (cons arrangedChild acc))))

fn arrange node: ui/VNode bounds: Rect -> LayoutBox
  (let [(tag node.tag) (key node.key) (attrs node.attrs) (layoutKind (optionOr (mapGet attrs "layout") "column")) (gap (parseDimAttr attrs "gap" 0)) (startX bounds.x) (startY bounds.y) (arrangedChildren (if (= tag "container") (if (= layoutKind "row") (arrangeChildrenRowLoop node.children startX startY gap (list)) (arrangeChildrenColLoop node.children startX startY gap (list))) (list)))] (makeLayoutBox tag key bounds arrangedChildren))
