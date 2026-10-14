(module asl-html/tests/cssTest
  :x [runTests]
  :i [(asl-html/css :a c)])

fn sheet -> (List c/Rule)
  [(c/importUrl "/base.css")
   (c/layerOrder ["reset" "site"])
   (c/ruleFor ["h1" "h2"] [(c/decl "margin" "0") (c/important "color" "red")])
   (c/media "(min-width: 640px)" [(c/rule ".a" [(c/decl "padding" (c/rem 1.5))])])
   (c/supports "(display: grid)" [(c/rule ".g" [(c/decl "display" "grid")])])
   (c/layer "site" [(c/rule "p" [(c/decl "line-height" "1.6")])])
   (c/container "card (min-width: 20rem)" [(c/rule ".c" [(c/decl "gap" (c/px 8))])])
   (c/keyframes "fade" [(pair "from" [(c/decl "opacity" "0")]) (pair "to" [(c/decl "opacity" "1")])])
   (c/fontFace [(c/decl "font-family" (c/cssString "Mono")) (c/decl "src" (c/cssUrl "/m.woff2"))])]

fn runTests -> Bool
  (do
    (assert (= (c/renderSheet (sheet)) (stringJoin ["@import url(\"/base.css\");" "@layer reset,site;" "h1,h2{margin:0;color:red !important}" "@media (min-width: 640px){.a{padding:1.5rem}}" "@supports (display: grid){.g{display:grid}}" "@layer site{p{line-height:1.6}}" "@container card (min-width: 20rem){.c{gap:8px}}" "@keyframes fade{from{opacity:0}to{opacity:1}}" "@font-face{font-family:\"Mono\";src:url(\"/m.woff2\")}"] "\n")) "every rule kind renders minified")
    (assert (= (c/renderSheetPretty [(c/media "print" [(c/rule "a" [(c/decl "color" "black")])])]) "@media print {\n  a {\n    color:black;\n  }\n}\n") "pretty output indents nested blocks")
    (assert (= (c/cssString "a\"b\\c\nd") "\"a\\\"b\\\\c\\a d\"") "css strings escape quotes, backslashes and newlines")
    (assert (= (str (c/pct 50) " " (c/ms 200) " " (c/deg 90) " " (c/em 0.5) " " (c/cssVar "x")) "50% 200ms 90deg 0.5em var(--x)") "value helpers")
    true)
