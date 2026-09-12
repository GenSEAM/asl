(module asl-codec/css-cascade-test
  :d "Unit verification test suite for CSS Computed Cascade Engine"
  :x [test-calc-specificity
      test-extract-css-variables
      test-parse-css-rules
      test-resolve-computed-style
      test-format-computed-style
      run-css-tests
      run-tests]
  :i [(asl-codec/css-cascade :a css)])

(df test-calc-specificity [] -> Bool
  :d "Tests calculation of CSS specificity tuples"
  (let [(s1 (css/calc-specificity "#header .nav.active a"))
        (s2 (css/calc-specificity ".btn"))
        (s3 (css/calc-specificity "inline"))]
    (assert (= (.-ids s1) 1) "ids count 1")
    (assert (= (.-classes s1) 2) "classes count 2")
    (assert (= (.-classes s2) 1) "classes count 1")
    (assert (= (.-inline s3) 1) "inline count 1")
    true))

(df test-extract-css-variables [] -> Bool
  :d "Tests extraction of CSS custom properties and internal semicolon preservation"
  (let [(css-code ":root {\n  --primary: #38bdf8;\n  --bg-dark: #0f172a;\n  --bg-svg: url(\"data:image/svg+xml;charset=utf-8,<svg></svg>\");\n  font-size: 16px;\n}")
        (vars (css/extract-css-variables css-code))
        (svg-var (filter (fn [(p (Pair Str Str))] -> Bool (= (pair-first p) "--bg-svg")) vars))]
    (assert (= (list-length vars) 3) "vars count 3")
    (assert (= (pair-first (option-or (list-head vars) (pair "" ""))) "--primary") "first var is --primary")
    (assert (string-contains? (pair-second (option-or (list-head svg-var) (pair "" ""))) "charset=utf-8") "svg var charset")
    true))

(df test-parse-css-rules [] -> Bool
  :d "Tests parsing of CSS rules and !important properties"
  (let [(css-code ".card { background: #1e293b; color: #ffffff !important; }")
        (rules (css/parse-css-rules css-code))]
    (assert (= (list-length rules) 1) "rules count 1")
    (let [(r (option-or (list-head rules) (css/CssRule :selector "" :specificity (css/CssSpecificity :inline 0 :ids 0 :classes 0 :tags 0) :properties (list) :source-order 0)))
          (props (.-properties r))]
      (assert (= (.-selector r) ".card") "selector is .card")
      (assert (= (list-length props) 2) "props count 2")
      true)))

(df test-resolve-computed-style [] -> Bool
  :d "Tests cascade resolution and inline style override"
  (let [(css-code ".btn { background: #3b82f6; color: #ffffff; }\n.btn-danger { background: #ef4444; }")
        (rules (css/parse-css-rules css-code))
        (computed (css/resolve-computed-style rules ".btn-danger" "color: #000000;"))]
    (assert (= (.-selector computed) ".btn-danger") "selector is .btn-danger")
    (let [(props (.-properties computed))
          (bg-pair (filter (fn [(p (Pair Str Str))] -> Bool (= (pair-first p) "background")) props))
          (color-pair (filter (fn [(p (Pair Str Str))] -> Bool (= (pair-first p) "color")) props))]
      (assert (= (pair-second (option-or (list-head bg-pair) (pair "" ""))) "#ef4444") "bg is #ef4444")
      (assert (= (pair-second (option-or (list-head color-pair) (pair "" ""))) "#000000") "color is #000000")
      true)))

(df test-format-computed-style [] -> Bool
  :d "Tests serialization of computed style into dense ASN format"
  (let [(computed (css/ComputedStyle
                    :selector "#app .hero"
                    :properties (list (pair "display" "flex") (pair "padding" "24px"))
                    :resolved-variables (list (pair "--hero-h" "400px"))))
        (formatted (css/format-computed-style computed))]
    (assert (string-contains? formatted "(:computed-style") "has :computed-style")
    (assert (string-contains? formatted ":selector \"#app .hero\"") "has selector")
    (assert (string-contains? formatted ":display \"flex\"") "has display flex")
    true))

(df run-css-tests [] -> Bool
  :d "Runs all CSS cascade unit test cases"
  (run-tests))

(df run-tests [] -> Bool
  :d "Runs all CSS cascade unit test cases"
  (do
    (assert (test-calc-specificity) "test-calc-specificity must pass")
    (assert (test-extract-css-variables) "test-extract-css-variables must pass")
    (assert (test-parse-css-rules) "test-parse-css-rules must pass")
    (assert (test-resolve-computed-style) "test-resolve-computed-style must pass")
    (assert (test-format-computed-style) "test-format-computed-style must pass")
    true))
