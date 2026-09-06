(module asl-codec/css-cascade-test
  :d "Unit verification test suite for CSS Computed Cascade Engine"
  :x [test-calc-specificity
      test-extract-css-variables
      test-parse-css-rules
      test-resolve-computed-style
      test-format-computed-style
      run-css-tests]
  :i [(css-cascade :a css)])

(df test-calc-specificity [] -> Bool
  :d "Tests calculation of CSS specificity tuples"
  (let [(s1 (css/calc-specificity "#header .nav.active a"))
        (s2 (css/calc-specificity ".btn"))
        (s3 (css/calc-specificity "inline"))]
    (and (= (.-ids s1) 1)
         (and (= (.-classes s1) 2)
              (and (= (.-classes s2) 1)
                   (= (.-inline s3) 1))))))

(df test-extract-css-variables [] -> Bool
  :d "Tests extraction of CSS custom properties"
  (let [(css-code ":root {\n  --primary: #38bdf8;\n  --bg-dark: #0f172a;\n  font-size: 16px;\n}")
        (vars (css/extract-css-variables css-code))]
    (and (= (list-length vars) 2)
         (= (pair-first (option-or (list-head vars) (pair "" ""))) "--primary"))))

(df test-parse-css-rules [] -> Bool
  :d "Tests parsing of CSS rules and !important properties"
  (let [(css-code ".card { background: #1e293b; color: #ffffff !important; }")
        (rules (css/parse-css-rules css-code))]
    (and (= (list-length rules) 1)
         (let [(r (option-or (list-head rules) (css/CssRule :selector "" :specificity (css/CssSpecificity :inline 0 :ids 0 :classes 0 :tags 0) :properties (list) :source-order 0)))
               (props (.-properties r))]
           (and (= (.-selector r) ".card")
                (= (list-length props) 2))))))

(df test-resolve-computed-style [] -> Bool
  :d "Tests cascade resolution and inline style override"
  (let [(css-code ".btn { background: #3b82f6; color: #ffffff; }\n.btn-danger { background: #ef4444; }")
        (rules (css/parse-css-rules css-code))
        (computed (css/resolve-computed-style rules ".btn-danger" "color: #000000;"))]
    (and (= (.-selector computed) ".btn-danger")
         (let [(props (.-properties computed))
               (bg-pair (filter (fn [(p (Pair Str Str))] -> Bool (= (pair-first p) "background")) props))
               (color-pair (filter (fn [(p (Pair Str Str))] -> Bool (= (pair-first p) "color")) props))]
           (and (= (pair-second (option-or (list-head bg-pair) (pair "" ""))) "#ef4444")
                (= (pair-second (option-or (list-head color-pair) (pair "" ""))) "#000000"))))))

(df test-format-computed-style [] -> Bool
  :d "Tests serialization of computed style into dense ASN format"
  (let [(computed (css/ComputedStyle
                    :selector "#app .hero"
                    :properties (list (pair "display" "flex") (pair "padding" "24px"))
                    :resolved-variables (list (pair "--hero-h" "400px"))))
        (formatted (css/format-computed-style computed))]
    (and (string-contains? formatted "(:computed-style")
         (and (string-contains? formatted ":selector \"#app .hero\"")
              (string-contains? formatted ":display \"flex\"")))))

(df run-css-tests [] -> Bool
  :d "Runs all CSS cascade unit test cases"
  (and (test-calc-specificity)
       (and (test-extract-css-variables)
            (and (test-parse-css-rules)
                 (and (test-resolve-computed-style)
                      (test-format-computed-style))))))
