(module asl-codec/css-cascade
  :d "CSS Computed Cascade Engine, Specificity Resolver, and Custom Property Extractor in Pure ASL"
  :x [CssSpecificity
      CssProperty
      CssRule
      ComputedStyle
      calc-specificity
      compare-specificity
      extract-css-variables
      parse-css-rules
      resolve-computed-style
      format-computed-style]
  :i [(core/strings :a s)])

(dfs CssSpecificity
  (:f inline I64 "1 if style is declared inline, else 0")
  (:f ids I64 "Count of ID selectors (#id)")
  (:f classes I64 "Count of class (.class), attribute, or pseudo-class selectors")
  (:f tags I64 "Count of element tag names or pseudo-elements"))

(dfs CssProperty
  (:f name Str "CSS property name e.g. color, background, font-size")
  (:f value Str "Raw CSS property value string")
  (:f important Bool "True if property value carries !important declaration"))

(dfs CssRule
  (:f selector Str "Raw CSS selector string e.g. #main .btn")
  (:f specificity CssSpecificity "Calculated selector specificity tuple")
  (:f properties (List CssProperty) "Declared CSS properties")
  (:f source-order I64 "Declaration order index in stylesheet"))

(dfs ComputedStyle
  (:f selector Str "Target selector or element identifier")
  (:f properties (List (Pair Str Str)) "Final cascaded key-value property map")
  (:f resolved-variables (List (Pair Str Str)) "Resolved CSS custom properties"))

(df count-char [(text Str) (target Str)] -> I64
  :d "Counts occurrences of a target character/substring in text."
  (let [(parts (string-split text target))]
    (- (list-length parts) 1)))

(df calc-specificity [(selector Str)] -> CssSpecificity
  :d "Computes CSS specificity tuple (inline, id, class, tag)."
  (let [(clean (string-trim selector))]
    (if (= clean "inline")
        (CssSpecificity :inline 1 :ids 0 :classes 0 :tags 0)
        (let [(ids (count-char clean "#"))
              (classes (count-char clean "."))
              (tokens (filter (fn [(w Str)] -> Bool (and (> (string-length w) 0) (and (not (string-starts-with? w ".")) (not (string-starts-with? w "#")))))
                              (string-split clean " ")))]
          (CssSpecificity :inline 0 :ids ids :classes classes :tags (list-length tokens))))))

(df compare-specificity [(a CssSpecificity) (b CssSpecificity)] -> I64
  :d "Compares two specificity tuples lexicographically: >0 if a > b, <0 if a < b, 0 if equal."
  (if (!= (.-inline a) (.-inline b))
      (- (.-inline a) (.-inline b))
      (if (!= (.-ids a) (.-ids b))
          (- (.-ids a) (.-ids b))
          (if (!= (.-classes a) (.-classes b))
              (- (.-classes a) (.-classes b))
              (- (.-tags a) (.-tags b))))))

(df extract-css-variables [(css-text Str)] -> (List (Pair Str Str))
  :d "Extracts CSS custom properties (--var: val) from stylesheet content."
  (let [(lines (string-split css-text "\n"))
        (var-lines (filter (fn [(l Str)] -> Bool (string-contains? (string-trim l) "--")) lines))]
    (fold (fn [(acc (List (Pair Str Str))) (line Str)] -> (List (Pair Str Str))
            (let [(trimmed (string-trim line))
                  (colon-idx (string-index-of trimmed ":"))]
              (mt colon-idx
                ((none) acc)
                ((some idx)
                 (let [(name (string-trim (option-or (string-slice trimmed 0 idx) "")))
                       (raw-val (option-or (string-slice trimmed (+ idx 1) (string-length trimmed)) ""))
                       (trimmed-val (string-trim raw-val))
                       (val (if (string-ends-with? trimmed-val ";")
                                (string-trim (option-or (string-slice trimmed-val 0 (- (string-length trimmed-val) 1)) trimmed-val))
                                trimmed-val))]
                   (if (string-starts-with? name "--")
                       (list-append acc (list (pair name val)))
                       acc))))))
          (list)
          var-lines)))

(df parse-prop-declarations [(block Str)] -> (List CssProperty)
  :d "Parses property declarations within a CSS block."
  (let [(decls (string-split block ";"))]
    (fold (fn [(acc (List CssProperty)) (d Str)] -> (List CssProperty)
            (let [(trimmed (string-trim d))
                  (colon-idx (string-index-of trimmed ":"))]
              (mt colon-idx
                ((none) acc)
                ((some idx)
                 (let [(name (string-trim (option-or (string-slice trimmed 0 idx) "")))
                       (val-part (string-trim (option-or (string-slice trimmed (+ idx 1) (string-length trimmed)) "")))
                       (is-imp (string-contains? val-part "!important"))
                       (clean-val (string-trim (string-replace val-part "!important" "")))]
                   (if (> (string-length name) 0)
                       (list-append acc (list (CssProperty :name name :value clean-val :important is-imp)))
                       acc))))))
          (list)
          decls)))

(df parse-css-rules [(css-text Str)] -> (List CssRule)
  :d "Parses CSS text into structured CssRule records with calculated specificity."
  (let [(clean (string-replace (string-replace css-text "\r" "") "\n" " "))
        (blocks (string-split clean "}"))]
    (fold (fn [(acc (List CssRule)) (block Str)] -> (List CssRule)
            (let [(trimmed (string-trim block))
                  (brace-idx (string-index-of trimmed "{"))]
              (mt brace-idx
                ((none) acc)
                ((some idx)
                 (let [(sel (string-trim (option-or (string-slice trimmed 0 idx) "")))
                       (body (option-or (string-slice trimmed (+ idx 1) (string-length trimmed)) ""))
                       (order (list-length acc))
                       (spec (calc-specificity sel))
                       (props (parse-prop-declarations body))]
                   (if (> (string-length sel) 0)
                       (list-append acc (list (CssRule :selector sel :specificity spec :properties props :source-order order)))
                       acc))))))
          (list)
          blocks)))

(df selector-matches? [(sel Str) (target Str)] -> Bool
  :d "Determines if selector matches target element or class."
  (or (= sel target)
      (or (= sel "*")
          (or (and (string-starts-with? sel ".") (string-contains? target (option-or (string-slice sel 1 (string-length sel)) "")))
              (and (string-starts-with? sel "#") (string-contains? target (option-or (string-slice sel 1 (string-length sel)) "")))))))

(df resolve-computed-style [(rules (List CssRule)) (target-selector Str) (inline-style Str)] -> ComputedStyle
  :d "Resolves cascade, specificity, !important, and inline overrides for a target element."
  (let [(matching-rules (filter (fn [(r CssRule)] -> Bool (selector-matches? (.-selector r) target-selector)) rules))
        (inline-props (parse-prop-declarations inline-style))
        (all-vars (extract-css-variables (s/join "\n" (map (fn [(r CssRule)] -> Str
                                                             (s/join "; " (map (fn [(p CssProperty)] -> Str (s/concat (.-name p) ": " (.-value p))) (.-properties r))))
                                                            rules))))]
    (let [(merged-map
            (fold (fn [(acc (List (Pair Str Str))) (rule CssRule)] -> (List (Pair Str Str))
                    (fold (fn [(inner (List (Pair Str Str))) (p CssProperty)] -> (List (Pair Str Str))
                            (let [(existing (filter (fn [(pair (Pair Str Str))] -> Bool (!= (pair-first pair) (.-name p))) inner))]
                              (list-append existing (list (pair (.-name p) (.-value p))))))
                          acc
                          (.-properties rule)))
                  (list)
                  matching-rules))
          (final-map
            (fold (fn [(acc (List (Pair Str Str))) (ip CssProperty)] -> (List (Pair Str Str))
                    (let [(existing (filter (fn [(pair (Pair Str Str))] -> Bool (!= (pair-first pair) (.-name ip))) acc))]
                      (list-append existing (list (pair (.-name ip) (.-value ip))))))
                  merged-map
                  inline-props))]
      (ComputedStyle
        :selector target-selector
        :properties final-map
        :resolved-variables all-vars))))

(df format-computed-style [(style ComputedStyle)] -> Str
  :d "Formats resolved computed style as dense ASN S-expression."
  (let [(prop-strs (map (fn [(p (Pair Str Str))] -> Str (s/concat ":" (pair-first p) " \"" (pair-second p) "\"")) (.-properties style)))
        (var-strs (map (fn [(v (Pair Str Str))] -> Str (s/concat ":" (pair-first v) " \"" (pair-second v) "\"")) (.-resolved-variables style)))]
    (s/concat "(:computed-style :selector \"" (.-selector style) "\" "
              ":props [" (s/join " " prop-strs) "] "
              ":variables [" (s/join " " var-strs) "])")))
