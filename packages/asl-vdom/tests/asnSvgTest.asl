(module aslVdom/tests/asnSvgTest :x [runTests] :i [(asnSvg :a svg)])

fn testRenderRect -> Bool
  (let [(node (svg/SvgNode :kind "rc" :attrs (list (pair "x" "10") (pair "y" "20") (pair "w" "300") (pair "h" "200") (pair "rx" "16") (pair "f" "#090d16") (pair "s" "#38bdf8")) :children (list) :textContent "")) (xml (svg/renderRect node))] (assert (stringContains? xml "<rect x=\"10\"") "Rect XML must contain x=10") (assert (stringContains? xml "width=\"300\"") "Rect XML must contain width=300") (assert (stringContains? xml "rx=\"16\"") "Rect XML must contain rx=16") (assert (stringContains? xml "fill=\"#090d16\"") "Rect XML must contain fill color") true)

fn testRenderCircle -> Bool
  (let [(node (svg/SvgNode :kind "circ" :attrs (list (pair "cx" "160") (pair "cy" "160") (pair "r" "80") (pair "f" "#38bdf8") (pair "s" "#ffffff")) :children (list) :textContent "")) (xml (svg/renderCircle node))] (assert (stringContains? xml "<circle cx=\"160\"") "Circle XML must contain cx=160") (assert (stringContains? xml "r=\"80\"") "Circle XML must contain r=80") (assert (stringContains? xml "stroke=\"#ffffff\"") "Circle XML must contain stroke color") true)

fn testRenderPolyFallback -> Bool
  (let [(node (svg/SvgNode :kind "poly" :attrs (list (pair "points" "10,10 50,50 10,50")) :children (list) :textContent "")) (xml (svg/renderPolygon node))] (assert (stringContains? xml "<polygon points=\"10,10 50,50 10,50\"") "Polygon XML must contain points") (assert (stringContains? xml "stroke=\"#38bdf8\"") "Polygon XML must contain fallback stroke") true)

fn testRenderPathFallback -> Bool
  (let [(node (svg/SvgNode :kind "p" :attrs (list (pair "d" "M 10 10 L 50 50 Z")) :children (list) :textContent "")) (xml (svg/renderPath node))] (assert (stringContains? xml "<path d=\"M 10 10 L 50 50 Z\"") "Path XML must contain d attribute") (assert (stringContains? xml "stroke=\"#38bdf8\"") "Path XML must contain fallback stroke") true)

fn testAsnToSvg -> Bool
  (let [(res (svg/asnToSvg "(:svg :w 320 :h 320 (:rc :x 0 :y 0 :w 320 :h 320 :rx 24 :f \"#090d16\"))")) (xml res.svg) (ok res.success)] (assert ok "ASN to SVG transpilation must succeed") (assert (stringContains? xml "<svg xmlns=\"http://www.w3.org/2000/svg\"") "SVG must have xmlns") (assert (stringContains? xml "viewBox=\"0 0 320 320\"") "SVG must have viewBox") (assert (stringContains? xml "<rect x=\"0\"") "SVG must contain rect") true)

fn testMultiSiblingRects -> Bool
  (let [(res (svg/asnToSvg "(:svg :w 320 :h 320 (:rc :x 10 :y 10 :w 50 :h 50) (:rc :x 70 :y 10 :w 50 :h 50) (:rc :x 130 :y 10 :w 50 :h 50) (:rc :x 190 :y 10 :w 50 :h 50) (:rc :x 250 :y 10 :w 50 :h 50))")) (xml res.svg) (ok res.success)] (assert ok "ASN to SVG transpilation must succeed for 5 rects") (assert (stringContains? xml "<rect x=\"10\"") "Must contain rect 1") (assert (stringContains? xml "<rect x=\"70\"") "Must contain rect 2") (assert (stringContains? xml "<rect x=\"130\"") "Must contain rect 3") (assert (stringContains? xml "<rect x=\"190\"") "Must contain rect 4") (assert (stringContains? xml "<rect x=\"250\"") "Must contain rect 5") true)

fn testMultiSiblingMixedShapes -> Bool
  (let [(res (svg/asnToSvg "(:svg :w 320 :h 320 (:rc :x 10 :y 10 :w 40 :h 40) (:circ :cx 50 :cy 50 :r 20) (:ln :x1 0 :y1 0 :x2 100 :y2 100) (:rc :x 60 :y 60 :w 40 :h 40) (:circ :cx 150 :cy 150 :r 30))")) (xml res.svg) (ok res.success)] (assert ok "ASN to SVG transpilation must succeed for mixed shapes") (assert (stringContains? xml "<rect x=\"10\"") "Must contain rect 1") (assert (stringContains? xml "<rect x=\"60\"") "Must contain rect 2") (assert (stringContains? xml "<circle cx=\"50\"") "Must contain circle 1") (assert (stringContains? xml "<circle cx=\"150\"") "Must contain circle 2") (assert (stringContains? xml "<line x1=\"0\"") "Must contain line 1") true)

fn runTests -> Bool
  (and (testRenderRect) (testRenderCircle) (testRenderPolyFallback) (testRenderPathFallback) (testAsnToSvg) (testMultiSiblingRects) (testMultiSiblingMixedShapes))
