(module asl-codec/cssEmit
  :d "Pure AgentScript CSS Emitter and Stylesheet Synthesizer"
  :x [asnToCss
      asnToCssStr
      renderCssVariables
      renderCssRule
      renderMediaBlock
      formatCssProperty]
  :i [(asl-parser/reader :a rd)
      (asl-parser/lexer :a lx)
      (asl-parser/ast :a ast)
      (asl-text/text :a txt)
      (asl-codec/cssCascade :a cascade)])

(df formatCssProperty [(prop cascade/CssProperty) (minify Bool)] -> Str
  :d "Formats a single CSS property declaration."
  (let [(name (.-name prop))
        (val (.-value prop))
        (imp (.-important prop))]
    (if minify
      (if imp
        (str name ":" val "!important")
        (str name ":" val))
      (if imp
        (str "  " name ": " val " !important;")
        (str "  " name ": " val ";")))))

(df renderCssVariables [(vars (List (Pair Str Str))) (minify Bool)] -> Str
  :d "Renders CSS custom property declarations within a :root selector."
  (if (list-empty? vars)
    ""
    (let [(cleanVars (map (fn [(v (Pair Str Str))] -> (Pair Str Str)
                            (let [(rawName (pair-first v))
                                  (cleanName (if (string-starts-with? rawName "--")
                                               rawName
                                               (str "--" (txt/stripColon rawName))))
                                  (rawVal (pairSecond v))]
                              (pair cleanName rawVal)))
                          vars))]
      (if minify
        (let [(props (map (fn [(p (Pair Str Str))] -> Str
                            (str (pair-first p) ":" (pairSecond p)))
                          cleanVars))]
          (str ":root{" (string-join props ";") "}"))
        (let [(lines (map (fn [(p (Pair Str Str))] -> Str
                            (str "  " (pair-first p) ": " (pairSecond p) ";"))
                          cleanVars))]
          (str ":root {\n" (string-join lines "\n") "\n}"))))))

(df renderCssRule [(rule cascade/CssRule) (minify Bool)] -> Str
  :d "Serializes a single CssRule into CSS text."
  (let [(sel (.-selector rule))
        (props (.-properties rule))]
    (if minify
      (if (list-empty? props)
        (str sel "{}")
        (let [(propStrs (map (fn [(p cascade/CssProperty)] -> Str (formatCssProperty p true)) props))]
          (str sel "{" (string-join propStrs ";") "}")))
      (if (list-empty? props)
        (str sel " {}")
        (let [(propStrs (map (fn [(p cascade/CssProperty)] -> Str (formatCssProperty p false)) props))]
          (str sel " {\n" (string-join propStrs "\n") "\n}"))))))

(df renderMediaBlock [(query Str) (rules (List cascade/CssRule)) (minify Bool)] -> Str
  :d "Formats an @media block containing nested CssRules."
  (if (list-empty? rules)
    (if minify (str "@media " query "{}") (str "@media " query " {}"))
    (if minify
      (let [(rendered (map (fn [(r cascade/CssRule)] -> Str (renderCssRule r true)) rules))]
        (str "@media " query "{" (string-join rendered "") "}"))
      (let [(rendered (map (fn [(r cascade/CssRule)] -> Str
                             (let [(rStr (renderCssRule r false))
                                   (lines (string-split rStr "\n"))
                                   (indented (map (fn [(l Str)] -> Str (str "  " l)) lines))]
                               (string-join indented "\n")))
                           rules))]
        (str "@media " query " {\n" (string-join rendered "\n\n") "\n}")))))

(df sexprToAtomStr [(expr rd/SExpr)] -> Str
  :d "Converts an SExpr to a clean string."
  (mt expr
    ((rd/sexprAtom v) (txt/stripQuotes v))
    ((rd/sexprList _) "")
    ((rd/sexprVect _) "")))

(df parsePropsList [(items (List rd/SExpr))] -> (List cascade/CssProperty)
  :d "Parses a list of properties which can be (:name val) or alternating :name val."
  (fold (fn [(acc (List cascade/CssProperty)) (it rd/SExpr)] -> (List cascade/CssProperty)
          (mt it
            ((rd/sexprList sub)
             (if (>= (list-length sub) 2)
               (let [(n (txt/stripColon (sexprToAtomStr (option-or (list-head sub) (rd/makeAtom "")))))
                     (vRaw (sexprToAtomStr (option-or (list-head (option-or (list-tail sub) (list))) (rd/makeAtom ""))))
                     (imp (string-contains? vRaw "!important"))
                     (v (string-trim (string-replace vRaw "!important" "")))]
                 (if (> (string-length n) 0)
                   (list-append acc (list (cascade/CssProperty :name n :value v :important imp)))
                   acc))
               acc))
            ((rd/sexprVect sub)
             (if (>= (list-length sub) 2)
               (let [(n (txt/stripColon (sexprToAtomStr (option-or (list-head sub) (rd/makeAtom "")))))
                     (vRaw (sexprToAtomStr (option-or (list-head (option-or (list-tail sub) (list))) (rd/makeAtom ""))))
                     (imp (string-contains? vRaw "!important"))
                     (v (string-trim (string-replace vRaw "!important" "")))]
                 (if (> (string-length n) 0)
                   (list-append acc (list (cascade/CssProperty :name n :value v :important imp)))
                   acc))
               acc))
            ((rd/sexprAtom _) acc)))
        (list)
        items))

(df parsePropFromSexpr [(expr rd/SExpr)] -> (List cascade/CssProperty)
  :d "Parses property definitions from an SExpr."
  (mt expr
    ((rd/sexprList items) (parsePropsList items))
    ((rd/sexprVect items) (parsePropsList items))
    ((rd/sexprAtom _) (list))))

(df findKeywordVal [(items (List rd/SExpr)) (kw Str)] -> Str
  :d "Finds string value following a keyword atom in items."
  (mt (list-head items)
    ((none) "")
    ((some it)
     (let [(tail (option-or (list-tail items) (list)))]
       (mt it
         ((rd/sexprAtom v)
          (if (or (= v kw) (or (= v (txt/stripColon kw)) (= (txt/stripColon v) (txt/stripColon kw))))
            (mt (list-head tail)
              ((some nextIt) (sexprToAtomStr nextIt))
              ((none) ""))
            (findKeywordVal tail kw)))
         ((rd/sexprList _) (findKeywordVal tail kw))
         ((rd/sexprVect _) (findKeywordVal tail kw)))))))

(df findKeywordSexpr [(items (List rd/SExpr)) (kw Str)] -> rd/SExpr
  :d "Finds SExpr following a keyword atom in items."
  (mt (list-head items)
    ((none) (rd/makeList (list)))
    ((some it)
     (let [(tail (option-or (list-tail items) (list)))]
       (mt it
         ((rd/sexprAtom v)
          (if (or (= v kw) (or (= v (txt/stripColon kw)) (= (txt/stripColon v) (txt/stripColon kw))))
            (mt (list-head tail)
              ((some nextIt) nextIt)
              ((none) (rd/makeList (list))))
            (findKeywordSexpr tail kw)))
         ((rd/sexprList _) (findKeywordSexpr tail kw))
         ((rd/sexprVect _) (findKeywordSexpr tail kw)))))))

(df parseRuleFromSexpr [(expr rd/SExpr) (order I64)] -> (Option cascade/CssRule)
  :d "Parses a single rule SExpr into a CssRule."
  (mt expr
    ((rd/sexprList items)
     (let [(headTag (rd/sexprHead expr))]
       (if (or (= headTag ":rule") (= headTag "rule"))
         (let [(tail (option-or (list-tail items) (list)))
               (sel (findKeywordVal tail ":selector"))
               (propsExpr (findKeywordSexpr tail ":props"))
               (props (parsePropFromSexpr propsExpr))
               (spec (cascade/calcSpecificity sel))]
           (some (cascade/CssRule :selector sel :specificity spec :properties props :sourceOrder order)))
         (if (>= (list-length items) 2)
           (let [(firstIt (option-or (list-head items) (rd/makeAtom "")))
                 (sel (sexprToAtomStr firstIt))
                 (secondIt (option-or (list-head (option-or (list-tail items) (list))) (rd/makeAtom "")))
                 (props (parsePropFromSexpr secondIt))
                 (spec (cascade/calcSpecificity sel))]
             (if (> (string-length sel) 0)
               (some (cascade/CssRule :selector sel :specificity spec :properties props :sourceOrder order))
               (none)))
           (none)))))
    ((rd/sexprVect _) (none))
    ((rd/sexprAtom _) (none))))

(df parseVarPairs [(items (List rd/SExpr))] -> (List (Pair Str Str))
  :d "Parses variable pairs from items list."
  (fold (fn [(acc (List (Pair Str Str))) (it rd/SExpr)] -> (List (Pair Str Str))
          (mt it
            ((rd/sexprList sub)
             (if (>= (list-length sub) 2)
               (let [(k (sexprToAtomStr (option-or (list-head sub) (rd/makeAtom ""))))
                     (v (sexprToAtomStr (option-or (list-head (option-or (list-tail sub) (list))) (rd/makeAtom ""))))]
                 (list-append acc (list (pair k v))))
               acc))
            ((rd/sexprVect sub)
             (if (>= (list-length sub) 2)
               (let [(k (sexprToAtomStr (option-or (list-head sub) (rd/makeAtom ""))))
                     (v (sexprToAtomStr (option-or (list-head (option-or (list-tail sub) (list))) (rd/makeAtom ""))))]
                 (list-append acc (list (pair k v))))
               acc))
            ((rd/sexprAtom _) acc)))
        (list)
        items))

(df extractVariables [(items (List rd/SExpr))] -> (List (Pair Str Str))
  :d "Extracts CSS variables list from SExpr items."
  (let [(varsSexpr (findKeywordSexpr items ":vars"))]
    (mt varsSexpr
      ((rd/sexprList vItems) (parseVarPairs vItems))
      ((rd/sexprVect vItems) (parseVarPairs vItems))
      ((rd/sexprAtom _) (list)))))

(df parseDirectRules [(items (List rd/SExpr)) (order I64)] -> (List cascade/CssRule)
  :d "Parses direct rule items starting at given order."
  (mt (list-head items)
    ((none) (list))
    ((some it)
     (let [(tail (option-or (list-tail items) (list)))
           (mRule (parseRuleFromSexpr it order))]
       (mt mRule
         ((some r) (list-cons r (parseDirectRules tail (+ order 1))))
         ((none) (parseDirectRules tail order)))))))

(df parseRuleList [(items (List rd/SExpr))] -> (List cascade/CssRule)
  :d "Parses a list of rule SExprs."
  (parseDirectRules items 0))

(df extractRules [(items (List rd/SExpr))] -> (List cascade/CssRule)
  :d "Extracts CSS rules list from SExpr items."
  (let [(rulesSexpr (findKeywordSexpr items ":rules"))]
    (mt rulesSexpr
      ((rd/sexprList rItems) (parseRuleList rItems))
      ((rd/sexprVect rItems) (parseRuleList rItems))
      ((rd/sexprAtom _) (parseDirectRules items 0)))))

(df extractMedia [(items (List rd/SExpr))] -> (List (Pair Str (List cascade/CssRule)))
  :d "Extracts @media blocks from SExpr items."
  (let [(mediaSexpr (findKeywordSexpr items ":media"))]
    (mt mediaSexpr
      ((rd/sexprList mItems)
       (let [(hd (rd/sexprHead mediaSexpr))]
         (if (or (= hd ":media") (= hd "media"))
           (let [(tail (option-or (list-tail mItems) (list)))
                 (q (findKeywordVal tail ":query"))
                 (rulesExpr (findKeywordSexpr tail ":rules"))
                 (rules (mt rulesExpr
                          ((rd/sexprList rList) (parseRuleList rList))
                          ((rd/sexprVect rList) (parseRuleList rList))
                          ((rd/sexprAtom _) (list))))]
             (list (pair q rules)))
           (fold (fn [(acc (List (Pair Str (List cascade/CssRule)))) (it rd/SExpr)] -> (List (Pair Str (List cascade/CssRule)))
                   (mt it
                     ((rd/sexprList sub)
                      (let [(q (findKeywordVal sub ":query"))
                            (rulesExpr (findKeywordSexpr sub ":rules"))
                            (rules (mt rulesExpr
                                     ((rd/sexprList rList) (parseRuleList rList))
                                     ((rd/sexprVect rList) (parseRuleList rList))
                                     ((rd/sexprAtom _) (list))))]
                        (if (> (string-length q) 0)
                          (list-append acc (list (pair q rules)))
                          acc)))
                     (_ acc)))
                 (list)
                 mItems))))
      ((rd/sexprVect _) (list))
      ((rd/sexprAtom _) (list)))))

(df emitFromItems [(items (List rd/SExpr)) (minify Bool)] -> Str
  :d "Assembles CSS string from parsed items."
  (let [(vars (extractVariables items))
        (rules (extractRules items))
        (mediaBlocks (extractMedia items))
        (varStr (renderCssVariables vars minify))
        (ruleStrs (map (fn [(r cascade/CssRule)] -> Str (renderCssRule r minify)) rules))
        (mediaStrs (map (fn [(m (Pair Str (List cascade/CssRule)))] -> Str
                          (renderMediaBlock (pair-first m) (pairSecond m) minify))
                        mediaBlocks))
        (parts (list-append (if (string-empty? varStr) (list) (list varStr))
                            (list-append ruleStrs mediaStrs)))
        (allNonEmpty (filter (fn [(s Str)] -> Bool (not (string-empty? s))) parts))]
    (if minify
      (string-join allNonEmpty "")
      (string-join allNonEmpty "\n\n"))))

(df asnToCss [(styleExpr rd/SExpr) (minify Bool)] -> Str
  :d "Serializes stylesheet definitions from S-expressions into CSS text."
  (mt styleExpr
    ((rd/sexprAtom v)
     (let [(clean (string-trim (txt/stripQuotes v)))]
       clean))
    ((rd/sexprList items)
     (emitFromItems items minify))
    ((rd/sexprVect items)
     (emitFromItems items minify))))

(df asnToCssStr [(styleStr Str) (minify Bool)] -> Str
  :d "Parses CSS S-expression string and emits CSS text."
  (let [(trimmed (string-trim styleStr))]
    (if (string-empty? trimmed)
      ""
      (let [(toks (lx/tokenize trimmed))
            (formsRes (ast/readForms toks))]
        (mt formsRes
          ((err _) "")
          ((ok forms)
           (if (list-empty? forms)
             ""
             (let [(pf (option-or (list-head forms) (ast/PosForm :expr (rd/makeAtom "") :line 0 :col 0)))]
               (asnToCss (.-expr pf) minify)))))))))
