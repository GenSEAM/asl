(module asl-transpile/cssCascade :x [CssSpecificity CssProperty CssRule ComputedStyle calcSpecificity compareSpecificity extractCssVariables parseCssRules resolveComputedStyle formatComputedStyle formatComputedStyleAsCss] :i [(asl-text/string :a s)])

(schema CssSpecificity (:f inline I64) (:f ids I64) (:f classes I64) (:f tags I64))

(schema CssProperty (:f name Str) (:f value Str) (:f important Bool))

(schema CssRule (:f selector Str) (:f specificity CssSpecificity) (:f properties (List CssProperty)) (:f sourceOrder I64))

(schema ComputedStyle (:f selector Str) (:f properties (List (pair Str Str))) (:f resolvedVariables (List (pair Str Str))))

fn isAsciiIdent? c: Str -> Bool
  (or (and (>= c "a") (<= c "z"))
      (or (and (>= c "A") (<= c "Z"))
          (or (and (>= c "0") (<= c "9"))
              (or (= c "-") (= c "_")))))

fn calcSpecificityStep chars: (List Str) idx: Int64 len: Int64 ids: Int64 classes: Int64 tags: Int64 inBracket: Bool inParen: Bool -> CssSpecificity
  (if (>= idx len)
    (CssSpecificity :inline 0 :ids ids :classes classes :tags tags)
    (let [(c (optionOr (listGet chars idx) ""))
          (cNext (if (< (+ idx 1) len) (optionOr (listGet chars (+ idx 1)) "") ""))]
      (cond
        ((= c "[")
          (calcSpecificityStep chars (+ idx 1) len ids (+ classes 1) tags true inParen))
        ((= c "]")
          (calcSpecificityStep chars (+ idx 1) len ids classes tags false inParen))
        ((= c "(")
          (calcSpecificityStep chars (+ idx 1) len ids classes tags inBracket true))
        ((= c ")")
          (calcSpecificityStep chars (+ idx 1) len ids classes tags inBracket false))
        ((or inBracket inParen)
          (calcSpecificityStep chars (+ idx 1) len ids classes tags inBracket inParen))
        ((= c "#")
          (calcSpecificityStep chars (+ idx 1) len (+ ids 1) classes tags inBracket inParen))
        ((and (= c ":") (= cNext ":"))
          (calcSpecificityStep chars (+ idx 2) len ids classes (+ tags 1) inBracket inParen))
        ((= c ":")
          (calcSpecificityStep chars (+ idx 1) len ids (+ classes 1) tags inBracket inParen))
        ((= c ".")
          (calcSpecificityStep chars (+ idx 1) len ids (+ classes 1) tags inBracket inParen))
        ((isAsciiIdent? c)
          (let [(prev (if (> idx 0) (optionOr (listGet chars (- idx 1)) "") ""))
                (isPrefix (or (= prev "#") (or (= prev ".") (or (= prev ":") (or (= prev "-") (= prev "_"))))))]
            (if (or (isAsciiIdent? prev) isPrefix)
              (calcSpecificityStep chars (+ idx 1) len ids classes tags inBracket inParen)
              (calcSpecificityStep chars (+ idx 1) len ids classes (+ tags 1) inBracket inParen))))
        (else
          (calcSpecificityStep chars (+ idx 1) len ids classes tags inBracket inParen)))))

fn calcSpecificity selector: Str -> CssSpecificity
  (let [(clean (stringTrim selector))]
    (if (= clean "inline")
      (CssSpecificity :inline 1 :ids 0 :classes 0 :tags 0)
      (let [(chars (stringChars clean))]
        (calcSpecificityStep chars 0 (listLength chars) 0 0 0 false false))))

fn compareSpecificity a: CssSpecificity b: CssSpecificity -> I64
  (if (!= a.inline b.inline) (- a.inline b.inline) (if (!= a.ids b.ids) (- a.ids b.ids) (if (!= a.classes b.classes) (- a.classes b.classes) (- a.tags b.tags))))

fn extractCssVariables cssText: Str -> (List (Pair Str Str))
  (let [(lines (stringSplit cssText "\n")) (varLines (filter (fn [(l Str)] -> Bool (stringContains? (stringTrim l) "--")) lines))] (fold (fn [(acc (List (pair Str Str))) (line Str)] -> (List (Pair Str Str)) (let [(trimmed (stringTrim line)) (colonIdx (stringIndexOf trimmed ":"))] (mt colonIdx ((none) acc) ((some idx) (let [(name (stringTrim (optionOr (stringSlice trimmed 0 idx) ""))) (rawVal (optionOr (stringSlice trimmed (+ idx 1) (stringLength trimmed)) "")) (trimmedVal (stringTrim rawVal)) (val (if (stringEndsWith? trimmedVal ";") (stringTrim (optionOr (stringSlice trimmedVal 0 (- (stringLength trimmedVal) 1)) trimmedVal)) trimmedVal))] (if (stringStartsWith? name "--") (listAppend acc (list (pair name val))) acc)))))) (list) varLines))

fn parsePropDeclarations block: Str -> (List CssProperty)
  (let [(decls (stringSplit block ";"))] (fold (fn [(acc (List CssProperty)) (d Str)] -> (List CssProperty) (let [(trimmed (stringTrim d)) (colonIdx (stringIndexOf trimmed ":"))] (mt colonIdx ((none) acc) ((some idx) (let [(name (stringTrim (optionOr (stringSlice trimmed 0 idx) ""))) (valPart (stringTrim (optionOr (stringSlice trimmed (+ idx 1) (stringLength trimmed)) ""))) (isImp (stringContains? valPart "!important")) (cleanVal (stringTrim (stringReplace valPart "!important" "")))] (if (> (stringLength name) 0) (listAppend acc (list (CssProperty :name name :value cleanVal :important isImp))) acc)))))) (list) decls))

fn parseCssRules cssText: Str -> (List CssRule)
  (let [(clean (stringReplace (stringReplace cssText "\r" "") "\n" " ")) (blocks (stringSplit clean "}"))] (fold (fn [(acc (List CssRule)) (block Str)] -> (List CssRule) (let [(trimmed (stringTrim block)) (braceIdx (stringIndexOf trimmed "{"))] (mt braceIdx ((none) acc) ((some idx) (let [(sel (stringTrim (optionOr (stringSlice trimmed 0 idx) ""))) (body (optionOr (stringSlice trimmed (+ idx 1) (stringLength trimmed)) "")) (order (listLength acc)) (spec (calcSpecificity sel)) (props (parsePropDeclarations body))] (if (> (stringLength sel) 0) (listAppend acc (list (CssRule :selector sel :specificity spec :properties props :sourceOrder order))) acc)))))) (list) blocks))

fn selectorMatches? sel: Str target: Str -> Bool
  (or (= sel target) (or (= sel "*") (or (and (stringStartsWith? sel ".") (stringContains? target (optionOr (stringSlice sel 1 (stringLength sel)) ""))) (and (stringStartsWith? sel "#") (stringContains? target (optionOr (stringSlice sel 1 (stringLength sel)) ""))))))

fn resolveComputedStyle rules: (List CssRule) targetSelector: Str inlineStyle: Str -> ComputedStyle
  (let [(matchingRules (filter (fn [(r CssRule)] -> Bool (selectorMatches? r.selector targetSelector)) rules)) (inlineProps (parsePropDeclarations inlineStyle)) (allVars (extractCssVariables (stringJoin (map (fn [(r CssRule)] -> Str (stringJoin (map (fn [(p CssProperty)] -> Str (str p.name ": " p.value)) r.properties) "; ")) rules) "\n")))] (let [(mergedMap (fold (fn [(acc (List (pair Str Str))) (rule CssRule)] -> (List (Pair Str Str)) (fold (fn [(inner (List (pair Str Str))) (p CssProperty)] -> (List (Pair Str Str)) (let [(existing (filter (fn [(pair (pair Str Str))] -> Bool (!= (pairFirst pair) p.name)) inner))] (listAppend existing (list (pair p.name p.value))))) acc rule.properties)) (list) matchingRules)) (finalMap (fold (fn [(acc (List (pair Str Str))) (ip CssProperty)] -> (List (Pair Str Str)) (let [(existing (filter (fn [(pair (pair Str Str))] -> Bool (!= (pairFirst pair) ip.name)) acc))] (listAppend existing (list (pair ip.name ip.value))))) mergedMap inlineProps))] (ComputedStyle :selector targetSelector :properties finalMap :resolvedVariables allVars)))

fn formatComputedStyle style: ComputedStyle -> Str
  (let [(propStrs (map (fn [(p (pair Str Str))] -> Str (str ":" (pairFirst p) " \"" (pairSecond p) "\"")) style.properties)) (varStrs (map (fn [(v (pair Str Str))] -> Str (str ":" (pairFirst v) " \"" (pairSecond v) "\"")) style.resolvedVariables))] (str "(:computed-style :selector \"" style.selector "\" " ":props [" (stringJoin propStrs " ") "] " ":variables [" (stringJoin varStrs " ") "])"))

fn formatComputedStyleAsCss style: ComputedStyle minify: Bool -> Str
  (let [(sel style.selector) (props (map (fn [(p (pair Str Str))] -> CssProperty (CssProperty :name (pairFirst p) :value (pairSecond p) :important false)) style.properties)) (spec (calcSpecificity sel))] (if minify (let [(propStrs (map (fn [(p CssProperty)] -> Str (str p.name ":" p.value)) props))] (str sel "{" (stringJoin propStrs ";") "}")) (let [(propStrs (map (fn [(p CssProperty)] -> Str (str "  " p.name ": " p.value ";")) props))] (str sel " {\n" (stringJoin propStrs "\n") "\n}"))))
