(module asl-html/tests/svgTest
  :x [runTests]
  :i [(asl-html/html :a h) (asl-html/svg :a s) (asl-html/asnSvg :a conv)])

fn drawing -> String
  "(:svg :w 100 :h 50 (:rc :x 0 :y 0 :w 100 :h 50 :rx 8 :f \"#222\") (:circ :cx 25 :cy 25 :r 10 :s \"#fff\" :strokeWidth 2) (:txt :x 50 :y 30 :anchor \"middle\" \"a < b\"))"

fn errorsOf src: String -> (List String)
  (mt (conv/asnToSvg src) ((ok _) []) ((err es) es))

fn runTests -> Bool
  (do
    (assert (= (s/num 2.0) "2") "integral numbers drop .0")
    (assert (= (s/num 2.5) "2.5") "fractions stay")
    (assert (= (s/pathData [(s/moveTo 0.0 0.0) (s/lineTo 10.0 0.0) (s/curveTo 10.0 5.0 5.0 10.0 0.0 10.0) (s/arcTo 5.0 5.0 0.0 false true 0.0 0.0) (s/close)]) "M0 0 L10 0 C10 5 5 10 0 10 A5 5 0 0 1 0 0 Z") "path commands")
    (assert (= (h/render (s/canvas 100.0 50.0 [(s/circleAt 10.0 10.0 5.0 [(s/fill "red")])])) "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"100\" height=\"50\" viewBox=\"0 0 100 50\"><circle cx=\"10\" cy=\"10\" r=\"5\" fill=\"red\"/></svg>") "a canvas with a circle")
    (assert (= (h/render (s/polygonOf [(pair 0.0 0.0) (pair 10.0 0.0) (pair 5.0 8.5)] [])) "<polygon points=\"0,0 10,0 5,8.5\"/>") "polygon points")
    (assert (= (h/render (s/group [(s/transform [(s/translate 5.0 5.0) (s/rotate 45.0)])] [(s/textAt 0.0 0.0 "x & y" [(s/fontSize 12.0)])])) "<g transform=\"translate(5 5) rotate(45)\"><text x=\"0\" y=\"0\" font-size=\"12\">x &amp; y</text></g>") "groups, transforms and escaped text")
    (assert (stringStartsWith? (s/renderSvg (s/canvas 1.0 1.0 [])) "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<svg") "a standalone file starts with the XML prolog")
    (assert (= (conv/asnToSvg (drawing)) (ok "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"100\" height=\"50\" viewBox=\"0 0 100 50\"><rect x=\"0\" y=\"0\" width=\"100\" height=\"50\" rx=\"8\" fill=\"#222\"/><circle cx=\"25\" cy=\"25\" r=\"10\" stroke=\"#fff\" stroke-width=\"2\"/><text x=\"50\" y=\"30\" text-anchor=\"middle\">a &lt; b</text></svg>\n")) "an ASN drawing with aliases and camelCase attributes converts")
    (assert (= (errorsOf "(:svg (:rectangle :x 1))") ["svg[0] > rectangle[0]: unknown element :rectangle; known: svg g defs symbol use path rect circle ellipse line polyline polygon text tspan textPath title desc a image linearGradient radialGradient stop clipPath mask pattern marker filter feGaussianBlur feOffset feBlend feColorMatrix feFlood feComposite feMerge feMergeNode feDropShadow and the aliases rc circ el ln pl poly p txt group"]) "an unknown element is named with the list of known ones")
    (assert (= (errorsOf "(:svg (:rc :fil \"red\"))") ["svg[0] > rect[0]: unknown attribute :fil (as fil)"]) "a misspelled attribute is an error, not silently kept")
    (assert (= (errorsOf "(:svg (:g \"oops\"))") ["svg[0] > g[0]: stray \"oops\"; text belongs in text, tspan, textPath, title or desc"]) "text outside a text element is an error")
    (assert (= (errorsOf "(:html)") ["the drawing must be one (:svg ...) form"]) "the root must be svg")
    (assert (= (conv/attributeName "fontFamily") "font-family") "camelCase attributes become kebab-case")
    (assert (= (conv/attributeName "viewBox") "viewBox") "SVG's own camelCase attributes are kept")
    true)
