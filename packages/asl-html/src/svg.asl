(module asl-html/svg
  :x [PathCmd num moveTo lineTo hLine vLine curveTo quadTo arcTo close pathData
      canvas rectAt roundRect circleAt ellipseAt lineFrom polylineOf polygonOf pathOf textAt group
      translate rotate scale transform fill stroke strokeWidth opacity fontSize anchor
      linearGradient gradientStop defs renderSvg]
  :i [(asl-html/html :a h)])

(enum PathCmd (:c moveTo [(x Float64) (y Float64)] "M x y") (:c lineTo [(x Float64) (y Float64)] "L x y") (:c hLine [(x Float64)] "H x") (:c vLine [(y Float64)] "V y") (:c curveTo [(x1 Float64) (y1 Float64) (x2 Float64) (y2 Float64) (x Float64) (y Float64)] "C cubic Bezier") (:c quadTo [(x1 Float64) (y1 Float64) (x Float64) (y Float64)] "Q quadratic Bezier") (:c arcTo [(rx Float64) (ry Float64) (rotation Float64) (large Bool) (sweep Bool) (x Float64) (y Float64)] "A elliptical arc") (:c close [] "Z"))

fn num x: Float64 -> String
  (let [(s (stringFromFloat64 x))]
    (if (stringEndsWith? s ".0") (optionOr (stringSlice s 0 (- (stringLength s) 2)) s) s))

fn nums xs: (List Float64) -> String
  (stringJoin (map num xs) " ")

fn flagNum b: Bool -> String
  (if b "1" "0")

fn cmdText c: PathCmd -> String
  (mt c
    ((moveTo x y) (str "M" (nums [x y])))
    ((lineTo x y) (str "L" (nums [x y])))
    ((hLine x) (str "H" (num x)))
    ((vLine y) (str "V" (num y)))
    ((curveTo x1 y1 x2 y2 x y) (str "C" (nums [x1 y1 x2 y2 x y])))
    ((quadTo x1 y1 x y) (str "Q" (nums [x1 y1 x y])))
    ((arcTo rx ry rotation large sweep x y) (str "A" (nums [rx ry rotation]) " " (flagNum large) " " (flagNum sweep) " " (nums [x y])))
    ((close) "Z"))

fn pathData cmds: (List PathCmd) -> String
  (stringJoin (map cmdText cmds) " ")

fn canvas width: Float64 height: Float64 kids: (List h/Node) -> h/Node
  (h/svg [(h/attr "width" (num width)) (h/attr "height" (num height)) (h/attr "viewBox" (str "0 0 " (num width) " " (num height)))] kids)

fn rectAt x: Float64 y: Float64 w: Float64 hgt: Float64 attrs: (List h/Attr) -> h/Node
  (h/rect (listAppend [(h/attr "x" (num x)) (h/attr "y" (num y)) (h/attr "width" (num w)) (h/attr "height" (num hgt))] attrs))

fn roundRect x: Float64 y: Float64 w: Float64 hgt: Float64 radius: Float64 attrs: (List h/Attr) -> h/Node
  (rectAt x y w hgt (cons (h/attr "rx" (num radius)) attrs))

fn circleAt cx: Float64 cy: Float64 r: Float64 attrs: (List h/Attr) -> h/Node
  (h/circle (listAppend [(h/attr "cx" (num cx)) (h/attr "cy" (num cy)) (h/attr "r" (num r))] attrs))

fn ellipseAt cx: Float64 cy: Float64 rx: Float64 ry: Float64 attrs: (List h/Attr) -> h/Node
  (h/ellipse (listAppend [(h/attr "cx" (num cx)) (h/attr "cy" (num cy)) (h/attr "rx" (num rx)) (h/attr "ry" (num ry))] attrs))

fn lineFrom x1: Float64 y1: Float64 x2: Float64 y2: Float64 attrs: (List h/Attr) -> h/Node
  (h/line (listAppend [(h/attr "x1" (num x1)) (h/attr "y1" (num y1)) (h/attr "x2" (num x2)) (h/attr "y2" (num y2))] attrs))

fn pointsText points: (List (Pair Float64 Float64)) -> String
  (stringJoin (map (fn [(p (Pair Float64 Float64))] -> String (str (num (pairFirst p)) "," (num (pairSecond p)))) points) " ")

fn polylineOf points: (List (Pair Float64 Float64)) attrs: (List h/Attr) -> h/Node
  (h/polyline (cons (h/attr "points" (pointsText points)) attrs))

fn polygonOf points: (List (Pair Float64 Float64)) attrs: (List h/Attr) -> h/Node
  (h/polygon (cons (h/attr "points" (pointsText points)) attrs))

fn pathOf cmds: (List PathCmd) attrs: (List h/Attr) -> h/Node
  (h/path (cons (h/attr "d" (pathData cmds)) attrs))

fn textAt x: Float64 y: Float64 content: String attrs: (List h/Attr) -> h/Node
  (h/svgText (listAppend [(h/attr "x" (num x)) (h/attr "y" (num y))] attrs) [(h/text content)])

fn group attrs: (List h/Attr) kids: (List h/Node) -> h/Node
  (h/g attrs kids)

fn translate x: Float64 y: Float64 -> String
  (str "translate(" (nums [x y]) ")")

fn rotate degrees: Float64 -> String
  (str "rotate(" (num degrees) ")")

fn scale k: Float64 -> String
  (str "scale(" (num k) ")")

fn transform parts: (List String) -> h/Attr
  (h/attr "transform" (stringJoin parts " "))

fn fill color: String -> h/Attr
  (h/attr "fill" color)

fn stroke color: String -> h/Attr
  (h/attr "stroke" color)

fn strokeWidth w: Float64 -> h/Attr
  (h/attr "stroke-width" (num w))

fn opacity x: Float64 -> h/Attr
  (h/attr "opacity" (num x))

fn fontSize x: Float64 -> h/Attr
  (h/attr "font-size" (num x))

fn anchor where: String -> h/Attr
  (h/attr "text-anchor" where)

fn gradientStop offset: Float64 color: String -> h/Node
  (h/stop [(h/attr "offset" (num offset)) (h/attr "stop-color" color)] [])

fn linearGradient gid: String x1: Float64 y1: Float64 x2: Float64 y2: Float64 stops: (List h/Node) -> h/Node
  (h/linearGradient [(h/id gid) (h/attr "x1" (num x1)) (h/attr "y1" (num y1)) (h/attr "x2" (num x2)) (h/attr "y2" (num y2))] stops)

fn defs kids: (List h/Node) -> h/Node
  (h/defs [] kids)

fn renderSvg root: h/Node -> String
  (str "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n" (h/render root) "\n")
