(module asl-codec/cssCascadeTest
  :d "Unit verification test suite for CSS Computed Cascade Engine"
  :x [testCalcSpecificity
      testExtractCssVariables
      testParseCssRules
      testResolveComputedStyle
      testFormatComputedStyle
      runCssTests
      runTests]
  :i [(asl-codec/cssCascade :a css)])

(df testCalcSpecificity [] -> Bool
  :d "Tests calculation of CSS specificity tuples"
  (let [(s1 (css/calcSpecificity "#header .nav.active a"))
        (s2 (css/calcSpecificity ".btn"))
        (s3 (css/calcSpecificity "inline"))]
    (assert (= (.-ids s1) 1) "ids count 1")
    (assert (= (.-classes s1) 2) "classes count 2")
    (assert (= (.-classes s2) 1) "classes count 1")
    (assert (= (.-inline s3) 1) "inline count 1")
    true))

(df testExtractCssVariables [] -> Bool
  :d "Tests extraction of CSS custom properties and internal semicolon preservation"
  (let [(cssCode ":root {\n  --primary: #38bdf8;\n  --bg-dark: #0f172a;\n  --bg-svg: url(\"data:image/svg+xml;charset=utf-8,<svg></svg>\");\n  font-size: 16px;\n}")
        (vars (css/extractCssVariables cssCode))
        (svgVar (filter (fn [(p (Pair Str Str))] -> Bool (= (pairFirst p) "--bg-svg")) vars))]
    (assert (= (list-length vars) 3) "vars count 3")
    (assert (= (pairFirst (option-or (list-head vars) (pair "" ""))) "--primary") "first var is --primary")
    (assert (string-contains? (pairSecond (option-or (list-head svgVar) (pair "" ""))) "charset=utf-8") "svg var charset")
    true))

(df testParseCssRules [] -> Bool
  :d "Tests parsing of CSS rules and !important properties"
  (let [(cssCode ".card { background: #1e293b; color: #ffffff !important; }")
        (rules (css/parseCssRules cssCode))]
    (assert (= (list-length rules) 1) "rules count 1")
    (let [(r (option-or (list-head rules) (css/CssRule :selector "" :specificity (css/CssSpecificity :inline 0 :ids 0 :classes 0 :tags 0) :properties (list) :sourceOrder 0)))
          (props (.-properties r))]
      (assert (= (.-selector r) ".card") "selector is .card")
      (assert (= (list-length props) 2) "props count 2")
      true)))

(df testResolveComputedStyle [] -> Bool
  :d "Tests cascade resolution and inline style override"
  (let [(cssCode ".btn { background: #3b82f6; color: #ffffff; }\n.btn-danger { background: #ef4444; }")
        (rules (css/parseCssRules cssCode))
        (computed (css/resolveComputedStyle rules ".btn-danger" "color: #000000;"))]
    (assert (= (.-selector computed) ".btn-danger") "selector is .btn-danger")
    (let [(props (.-properties computed))
          (bgPair (filter (fn [(p (Pair Str Str))] -> Bool (= (pairFirst p) "background")) props))
          (colorPair (filter (fn [(p (Pair Str Str))] -> Bool (= (pairFirst p) "color")) props))]
      (assert (= (pairSecond (option-or (list-head bgPair) (pair "" ""))) "#ef4444") "bg is #ef4444")
      (assert (= (pairSecond (option-or (list-head colorPair) (pair "" ""))) "#000000") "color is #000000")
      true)))

(df testFormatComputedStyle [] -> Bool
  :d "Tests serialization of computed style into dense ASN format"
  (let [(computed (css/ComputedStyle
                    :selector "#app .hero"
                    :properties (list (pair "display" "flex") (pair "padding" "24px"))
                    :resolvedVariables (list (pair "--hero-h" "400px"))))
        (formatted (css/formatComputedStyle computed))]
    (assert (string-contains? formatted "(:computed-style") "has :computed-style")
    (assert (string-contains? formatted ":selector \"#app .hero\"") "has selector")
    (assert (string-contains? formatted ":display \"flex\"") "has display flex")
    true))

(df runCssTests [] -> Bool
  :d "Runs all CSS cascade unit test cases"
  (runTests))

(df runTests [] -> Bool
  :d "Runs all CSS cascade unit test cases"
  (do
    (assert (testCalcSpecificity) "test-calc-specificity must pass")
    (assert (testExtractCssVariables) "test-extract-css-variables must pass")
    (assert (testParseCssRules) "test-parse-css-rules must pass")
    (assert (testResolveComputedStyle) "test-resolve-computed-style must pass")
    (assert (testFormatComputedStyle) "test-format-computed-style must pass")
    true))
