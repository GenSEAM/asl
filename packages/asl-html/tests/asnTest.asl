(module asl-html/tests/asnTest
  :x [runTests]
  :i [(asl-html/asnHtml :a ph) (asl-html/asnCss :a pc)])

fn page -> String
  "(:html :lang \"en\" (:head (:meta :charset \"utf-8\") (:title \"Hi & bye\") (:style (:rule \"h1\" :color \"red\" :fontSize \"2rem\") (:media \"(min-width: 600px)\" (:rule \".a\" :padding 0)))) (:body (:h1 :cls \"big\" \"Hello <world>\") (:input :type \"checkbox\" :checked true :disabled false) (:button \"Go\") (:svg :w 10 :h 10 (:circ :cx 5 :cy 5 :r 4))))"

fn sheet -> String
  "(:css (:import \"/base.css\") (:layerOrder \"reset\" \"site\") (:rule \"a:hover\" :color \"var(--signal)\" :--ring \"2px\") (:supports \"(display: grid)\" (:rule \".g\" :display \"grid\")) (:keyframes \"fade\" (:at \"from\" :opacity 0) (:at \"to\" :opacity 1)) (:fontFace :fontFamily \"\\\"Mono\\\"\" :src \"url(/m.woff2)\"))"

fn errorsOf r: (Result String (List String)) -> (List String)
  (mt r ((ok _) []) ((err es) es))

fn runTests -> Bool
  (do
    (assert (= (ph/asnToHtml (page)) (ok "<!doctype html><html lang=\"en\"><head><meta charset=\"utf-8\"/><title>Hi &amp; bye</title><style>h1{color:red;font-size:2rem}\n@media (min-width: 600px){.a{padding:0}}</style></head><body><h1 class=\"big\">Hello &lt;world&gt;</h1><input type=\"checkbox\" checked/><button type=\"button\">Go</button><svg xmlns=\"http://www.w3.org/2000/svg\" width=\"10\" height=\"10\" viewBox=\"0 0 10 10\"><circle cx=\"5\" cy=\"5\" r=\"4\"/></svg></body></html>\n")) "a page with css rules, boolean attributes, a button and an svg drawing")
    (assert (= (ph/asnToHtml "(:p \"x\" (:em \"y\"))") (ok "<p>x<em>y</em></p>\n")) "a fragment has no doctype")
    (assert (= (errorsOf (ph/asnToHtml "(:div (:blink \"x\") (:img :src \"a.png\" \"caption\") (:p :colour \"red\"))")) ["div[0] > blink[0]: unknown element :blink; HTML elements are the HTML5 names, svg nests an asl-html/asnSvg drawing, style takes asl-html/asnCss rules" "div[0] > img[1]: img is a void element and cannot hold text" "div[0] > p[2]: unknown attribute :colour (as colour)"]) "html errors name their place")
    (assert (= (pc/asnToCss (sheet)) (ok "@import url(\"/base.css\");\n@layer reset,site;\na:hover{color:var(--signal);--ring:2px}\n@supports (display: grid){.g{display:grid}}\n@keyframes fade{from{opacity:0}to{opacity:1}}\n@font-face{font-family:\"Mono\";src:url(/m.woff2)}\n")) "every css rule kind from asn")
    (assert (= (errorsOf (pc/asnToCss "(:css (:rul \"a\" :color \"red\"))")) ["css > rul[0]: unknown rule :rul; known: rule media supports layer container keyframes fontFace import layerOrder"]) "an unknown css rule is named")
    (assert (= (errorsOf (pc/asnToCss "(:css (:rule \"a\" :color))")) ["css > rule[0]: property :color needs a single value"]) "a property without a value is an error")
    (assert (= (errorsOf (pc/asnToCss "(:rule \"a\")")) ["a stylesheet must be one (:css ...) form"]) "the root must be css")
    true)
