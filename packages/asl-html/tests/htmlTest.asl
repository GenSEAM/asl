(module asl-html/tests/htmlTest
  :x [runTests]
  :i [(asl-html/html :a h) (asl-html/css :a c)])

fn runTests -> Bool
  (do
    (assert (= (h/render (h/p [(h/cls "a\"b")] [(h/text "x < y & z")])) "<p class=\"a&quot;b\">x &lt; y &amp; z</p>") "text and attribute values are escaped")
    (assert (= (h/render (h/img [(h/src "/a.png") (h/alt "")])) "<img src=\"/a.png\" alt=\"\"/>") "void elements self-close")
    (assert (= (h/render (h/br [])) "<br>") "br stays short")
    (assert (= (h/render (h/input [(h/typeAttr "checkbox") (h/flag "checked")])) "<input type=\"checkbox\" checked/>") "boolean attributes have no value")
    (assert (= (h/render (h/button [] [(h/text "Go")])) "<button type=\"button\">Go</button>") "a button never submits unless asked")
    (assert (= (h/render (h/button [(h/typeAttr "submit")] [])) "<button type=\"submit\"></button>") "an explicit button type is kept")
    (assert (= (h/render (h/frag [(h/b [] [(h/text "1")]) (h/i [] [(h/text "2")])])) "<b>1</b><i>2</i>") "fragments render their children in sequence")
    (assert (= (h/render (h/script [] "if (a</b) x(\"</script>\")")) "<script>if (a<\\/b) x(\"<\\/script>\")</script>") "script text cannot close its element")
    (assert (= (h/render (h/styleSheet [(c/rule "a" [(c/decl "content" (c/cssString "</style>"))])])) "<style>a{content:\"<\\/style>\"}</style>") "style text cannot close its element")
    (assert (= (h/render (h/div [(h/classes ["a" "" "b"]) (h/data "msg" "2") (h/aria "label" "Close")] [])) "<div class=\"a b\" data-msg=\"2\" aria-label=\"Close\"></div>") "class lists, data and aria attributes")
    (assert (= (h/render (h/span [(h/style [(c/decl "color" (c/cssVar "ink")) (c/important "margin" (c/px 0))])] [])) "<span style=\"color:var(--ink);margin:0px !important\"></span>") "inline style from typed declarations")
    (assert (= (h/renderDocument (h/document "en" [(h/title [] [(h/text "T")])] [] [(h/main [] [])])) "<!doctype html><html lang=\"en\"><head><title>T</title></head><body><main></main></body></html>") "documents")
    (assert (= (h/render (h/svg [(h/attr "viewBox" "0 0 1 1")] [(h/path [(h/attr "d" "M0 0")]) (h/svgText [] [(h/text "a<b")])])) "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 1 1\"><path d=\"M0 0\"/><text>a&lt;b</text></svg>") "svg with its namespace")
    (assert (= (h/render (h/mapEl [(h/nameAttr "m")] [(h/area [(h/href "#")])])) "<map name=\"m\"><area href=\"#\"/></map>") "tags whose names clash with the prelude have El names")
    (assert (h/voidTag? "wbr") "every HTML void element is known")
    true)
