(module asl-codec/cssCascade
  :d "CSS Computed Cascade Engine, Specificity Resolver, and Custom Property Extractor in Pure ASL"
  :x [CssSpecificity
      CssProperty
      CssRule
      ComputedStyle
      calcSpecificity
      compareSpecificity
      extractCssVariables
      parseCssRules
      resolveComputedStyle
      formatComputedStyle
      formatComputedStyleAsCss]
  :i [(asl-text/string :a s)])

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
  (:f sourceOrder I64 "Declaration order index in stylesheet"))

(dfs ComputedStyle
  (:f selector Str "Target selector or element identifier")
  (:f properties (List (Pair Str Str)) "Final cascaded key-value property map")
  (:f resolvedVariables (List (Pair Str Str)) "Resolved CSS custom properties"))

(df countChar [(text Str) (target Str)] -> I64
  :d "Counts occurrences of a target character/substring in text."
  (let [(parts (string-split text target))]
    (- (list-length parts) 1)))

(df calcSpecificity [(selector Str)] -> CssSpecificity
  :d "Computes CSS specificity tuple (inline, id, class, tag)."
  (let [(clean (string-trim selector))]
    (if (= clean "inline")
        (CssSpecificity :inline 1 :ids 0 :classes 0 :tags 0)
        (let [(ids (countChar clean "#"))
              (classes (countChar clean "."))
              (tokens (filter (fn [(w Str)] -> Bool (and (> (string-length w) 0) (and (not (string-starts-with? w ".")) (not (string-starts-with? w "#")))))
                              (string-split clean " ")))]
          (CssSpecificity :inline 0 :ids ids :classes classes :tags (list-length tokens))))))

(df compareSpecificity [(a CssSpecificity) (b CssSpecificity)] -> I64
  :d "Compares two specificity tuples lexicographically: >0 if a > b, <0 if a < b, 0 if equal."
  (if (!= (.-inline a) (.-inline b))
      (- (.-inline a) (.-inline b))
      (if (!= (.-ids a) (.-ids b))
          (- (.-ids a) (.-ids b))
          (if (!= (.-classes a) (.-classes b))
              (- (.-classes a) (.-classes b))
              (- (.-tags a) (.-tags b))))))

(df extractCssVariables [(cssText Str)] -> (List (Pair Str Str))
  :d "Extracts CSS custom properties (--var: val) from stylesheet content."
  (let [(lines (string-split cssText "\n"))
        (varLines (filter (fn [(l Str)] -> Bool (string-contains? (string-trim l) "--")) lines))]
    (fold (fn [(acc (List (Pair Str Str))) (line Str)] -> (List (Pair Str Str))
            (let [(trimmed (string-trim line))
                  (colonIdx (string-index-of trimmed ":"))]
              (mt colonIdx
                ((none) acc)
                ((some idx)
                 (let [(name (string-trim (option-or (string-slice trimmed 0 idx) "")))
                       (rawVal (option-or (string-slice trimmed (+ idx 1) (string-length trimmed)) ""))
                       (trimmedVal (string-trim rawVal))
                       (val (if (string-ends-with? trimmedVal ";")
                                (string-trim (option-or (string-slice trimmedVal 0 (- (string-length trimmedVal) 1)) trimmedVal))
                                trimmedVal))]
                   (if (string-starts-with? name "--")
                       (list-append acc (list (pair name val)))
                       acc))))))
          (list)
          varLines)))

(df parsePropDeclarations [(block Str)] -> (List CssProperty)
  :d "Parses property declarations within a CSS block."
  (let [(decls (string-split block ";"))]
    (fold (fn [(acc (List CssProperty)) (d Str)] -> (List CssProperty)
            (let [(trimmed (string-trim d))
                  (colonIdx (string-index-of trimmed ":"))]
              (mt colonIdx
                ((none) acc)
                ((some idx)
                 (let [(name (string-trim (option-or (string-slice trimmed 0 idx) "")))
                       (valPart (string-trim (option-or (string-slice trimmed (+ idx 1) (string-length trimmed)) "")))
                       (isImp (string-contains? valPart "!important"))
                       (cleanVal (string-trim (string-replace valPart "!important" "")))]
                   (if (> (string-length name) 0)
                       (list-append acc (list (CssProperty :name name :value cleanVal :important isImp)))
                       acc))))))
          (list)
          decls)))

(df parseCssRules [(cssText Str)] -> (List CssRule)
  :d "Parses CSS text into structured CssRule records with calculated specificity."
  (let [(clean (string-replace (string-replace cssText "\r" "") "\n" " "))
        (blocks (string-split clean "}"))]
    (fold (fn [(acc (List CssRule)) (block Str)] -> (List CssRule)
            (let [(trimmed (string-trim block))
                  (braceIdx (string-index-of trimmed "{"))]
              (mt braceIdx
                ((none) acc)
                ((some idx)
                 (let [(sel (string-trim (option-or (string-slice trimmed 0 idx) "")))
                       (body (option-or (string-slice trimmed (+ idx 1) (string-length trimmed)) ""))
                       (order (list-length acc))
                       (spec (calcSpecificity sel))
                       (props (parsePropDeclarations body))]
                   (if (> (string-length sel) 0)
                       (list-append acc (list (CssRule :selector sel :specificity spec :properties props :sourceOrder order)))
                       acc))))))
          (list)
          blocks)))

(df selectorMatches? [(sel Str) (target Str)] -> Bool
  :d "Determines if selector matches target element or class."
  (or (= sel target)
      (or (= sel "*")
          (or (and (string-starts-with? sel ".") (string-contains? target (option-or (string-slice sel 1 (string-length sel)) "")))
              (and (string-starts-with? sel "#") (string-contains? target (option-or (string-slice sel 1 (string-length sel)) "")))))))

(df resolveComputedStyle [(rules (List CssRule)) (targetSelector Str) (inlineStyle Str)] -> ComputedStyle
  :d "Resolves cascade, specificity, !important, and inline overrides for a target element."
  (let [(matchingRules (filter (fn [(r CssRule)] -> Bool (selectorMatches? (.-selector r) targetSelector)) rules))
        (inlineProps (parsePropDeclarations inlineStyle))
        (allVars (extractCssVariables (s/join "\n" (map (fn [(r CssRule)] -> Str
                                                             (s/join "; " (map (fn [(p CssProperty)] -> Str (str (.-name p) ": " (.-value p))) (.-properties r))))
                                                            rules))))]
    (let [(mergedMap
            (fold (fn [(acc (List (Pair Str Str))) (rule CssRule)] -> (List (Pair Str Str))
                    (fold (fn [(inner (List (Pair Str Str))) (p CssProperty)] -> (List (Pair Str Str))
                            (let [(existing (filter (fn [(pair (Pair Str Str))] -> Bool (!= (pair-first pair) (.-name p))) inner))]
                              (list-append existing (list (pair (.-name p) (.-value p))))))
                          acc
                          (.-properties rule)))
                  (list)
                  matchingRules))
          (finalMap
            (fold (fn [(acc (List (Pair Str Str))) (ip CssProperty)] -> (List (Pair Str Str))
                    (let [(existing (filter (fn [(pair (Pair Str Str))] -> Bool (!= (pair-first pair) (.-name ip))) acc))]
                      (list-append existing (list (pair (.-name ip) (.-value ip))))))
                  mergedMap
                  inlineProps))]
      (ComputedStyle
        :selector targetSelector
        :properties finalMap
        :resolvedVariables allVars))))

(df formatComputedStyle [(style ComputedStyle)] -> Str
  :d "Formats resolved computed style as dense ASN S-expression."
  (let [(propStrs (map (fn [(p (Pair Str Str))] -> Str (str ":" (pair-first p) " \"" (pairSecond p) "\"")) (.-properties style)))
        (varStrs (map (fn [(v (Pair Str Str))] -> Str (str ":" (pair-first v) " \"" (pairSecond v) "\"")) (.-resolvedVariables style)))]
    (str "(:computed-style :selector \"" (.-selector style) "\" "
              ":props [" (s/join " " propStrs) "] "
              ":variables [" (s/join " " varStrs) "])")))

(df formatComputedStyleAsCss [(style ComputedStyle) (minify Bool)] -> Str
  :d "Formats a ComputedStyle record as CSS rule declaration text."
  (let [(sel (.-selector style))
        (props (map (fn [(p (Pair Str Str))] -> CssProperty
                      (CssProperty :name (pair-first p) :value (pairSecond p) :important false))
                    (.-properties style)))
        (spec (calcSpecificity sel))]
    (if minify
      (let [(propStrs (map (fn [(p CssProperty)] -> Str (str (.-name p) ":" (.-value p))) props))]
        (str sel "{" (s/join ";" propStrs) "}"))
      (let [(propStrs (map (fn [(p CssProperty)] -> Str (str "  " (.-name p) ": " (.-value p) ";")) props))]
        (str sel " {\n" (s/join "\n" propStrs) "\n}")))))

