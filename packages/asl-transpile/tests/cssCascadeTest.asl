(module asl-transpile/cssCascadeTest :x [testCalcSpecificity testExtractCssVariables testParseCssRules testResolveComputedStyle testFormatComputedStyle runCssTests runTests] :i [(asl-transpile/cssCascade :a css)])

fn testCalcSpecificity -> Bool
  (let [(s1 (css/calcSpecificity "#header .nav.active a")) (s2 (css/calcSpecificity ".btn")) (s3 (css/calcSpecificity "inline")) (sHover (css/calcSpecificity "a:hover")) (sPseudo (css/calcSpecificity "p::before")) (sAttr (css/calcSpecificity "input[type=text]")) (sComb (css/calcSpecificity "div > p"))] (assert (= s1.ids 1) "ids count 1") (assert (= s1.classes 2) "classes count 2") (assert (= s2.classes 1) "classes count 1") (assert (= s3.inline 1) "inline count 1") (assert (= sHover.classes 1) "a:hover class/pseudo-class count 1") (assert (= sHover.tags 1) "a:hover tag count 1") (assert (= sPseudo.tags 2) "p::before tag/pseudo-element count 2") (assert (= sAttr.classes 1) "input[type=text] attribute count 1") (assert (= sAttr.tags 1) "input[type=text] tag count 1") (assert (= sComb.tags 2) "div > p tags count 2") (assert (= sComb.classes 0) "div > p classes count 0") true)

fn testExtractCssVariables -> Bool
  (let [(cssCode ":root {\n  --primary: #38bdf8;\n  --bg-dark: #0f172a;\n  --bg-svg: url(\"data:image/svg+xml;charset=utf-8,<svg></svg>\");\n  font-size: 16px;\n}") (vars (css/extractCssVariables cssCode)) (svgVar (filter (fn [(p (pair Str Str))] -> Bool (= (pairFirst p) "--bg-svg")) vars))] (assert (= (listLength vars) 3) "vars count 3") (assert (= (pairFirst (optionOr (listHead vars) (pair "" ""))) "--primary") "first var is --primary") (assert (stringContains? (pairSecond (optionOr (listHead svgVar) (pair "" ""))) "charset=utf-8") "svg var charset") true)

fn testParseCssRules -> Bool
  (let [(cssCode ".card { background: #1e293b; color: #ffffff !important; }") (rules (css/parseCssRules cssCode))] (assert (= (listLength rules) 1) "rules count 1") (let [(r (optionOr (listHead rules) (css/CssRule :selector "" :specificity (css/CssSpecificity :inline 0 :ids 0 :classes 0 :tags 0) :properties (list) :sourceOrder 0))) (props r.properties)] (assert (= r.selector ".card") "selector is .card") (assert (= (listLength props) 2) "props count 2") true))

fn testResolveComputedStyle -> Bool
  (let [(cssCode ".btn { background: #3b82f6; color: #ffffff; }\n.btn-danger { background: #ef4444; }") (rules (css/parseCssRules cssCode)) (computed (css/resolveComputedStyle rules ".btn-danger" "color: #000000;"))] (assert (= computed.selector ".btn-danger") "selector is .btn-danger") (let [(props computed.properties) (bgPair (filter (fn [(p (pair Str Str))] -> Bool (= (pairFirst p) "background")) props)) (colorPair (filter (fn [(p (pair Str Str))] -> Bool (= (pairFirst p) "color")) props))] (assert (= (pairSecond (optionOr (listHead bgPair) (pair "" ""))) "#ef4444") "bg is #ef4444") (assert (= (pairSecond (optionOr (listHead colorPair) (pair "" ""))) "#000000") "color is #000000") true))

fn testFormatComputedStyle -> Bool
  (let [(computed (css/ComputedStyle :selector "#app .hero" :properties (list (pair "display" "flex") (pair "padding" "24px")) :resolvedVariables (list (pair "--hero-h" "400px")))) (formatted (css/formatComputedStyle computed))] (assert (stringContains? formatted "(:computed-style") "has :computed-style") (assert (stringContains? formatted ":selector \"#app .hero\"") "has selector") (assert (stringContains? formatted ":display \"flex\"") "has display flex") true)

fn runCssTests -> Bool
  (runTests)

fn runTests -> Bool
  (do (assert (testCalcSpecificity) "test-calc-specificity must pass") (assert (testExtractCssVariables) "test-extract-css-variables must pass") (assert (testParseCssRules) "test-parse-css-rules must pass") (assert (testResolveComputedStyle) "test-resolve-computed-style must pass") (assert (testFormatComputedStyle) "test-format-computed-style must pass") true)
