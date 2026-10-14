(module asl-syntax/tests/css/rulesTest
  :x [runTests]
  :i [(asl-syntax/core/source :a src)
      (asl-syntax/core/tree :a tr)
      (asl-syntax/core/print :a pr)
      (asl-syntax/core/symbols :a sym)
      (asl-syntax/core/outline :a out)
      (asl-syntax/core/corpus :a crp)
      (asl-syntax/css/lex :a lex)
      (asl-syntax/css/rules :a rules)
      (asl-json/json :a j)])

fn jsonListEqual xs: (List j/Json) ys: (List j/Json) -> Bool
  (if (and (listEmpty? xs) (listEmpty? ys))
    true
    (if (or (listEmpty? xs) (listEmpty? ys))
      false
      (let [(hx (optionOr (listHead xs) (j/jnull)))
            (tx (optionOr (listTail xs) (list)))
            (hy (optionOr (listHead ys) (j/jnull)))
            (ty (optionOr (listTail ys) (list)))]
        (and (jsonEqual? hx hy) (jsonListEqual tx ty)))))

fn jsonEqual? a: j/Json b: j/Json -> Bool
  (mt a
    ((jnull) (mt b ((jnull) true) (_ false)))
    ((jbool b1) (mt b ((jbool b2) (= b1 b2)) (_ false)))
    ((jint i1) (mt b ((jint i2) (= i1 i2)) ((jnum n2) (= (int64ToFloat64 i1) n2)) (_ false)))
    ((jfloat f1) (mt b ((jfloat f2) (= f1 f2)) ((jnum n2) (= f1 n2)) (_ false)))
    ((jnum n1) (mt b ((jnum n2) (= n1 n2)) ((jint i2) (= n1 (int64ToFloat64 i2))) ((jfloat f2) (= n1 f2)) (_ false)))
    ((jstr s1) (mt b ((jstr s2) (= s1 s2)) (_ false)))
    ((jarr xs) (mt b ((jarr ys) (jsonListEqual xs ys)) (_ false)))
    ((jobj _) false))

fn testRuleListCase! items: (List j/Json) caseIdx: Int64 totalCases: Int64 passCount: Int64 -> Bool
  (if (>= caseIdx totalCases)
    (do
      (println (str "CSS upstream rule list: " (stringFromInt64 passCount) "/" (stringFromInt64 totalCases) " passed, 0 excluded"))
      (assert (= passCount totalCases) "all rule list cases passed")
      true)
    (let [(inVal (optionOr (listGet items (* caseIdx 2)) (j/jstr "")))
          (inputStr (mt inVal ((j/jstr s) s) (_ "")))
          (expectedVal (optionOr (listGet items (+ (* caseIdx 2) 1)) (j/jarr (list))))
          (tree (rules/parseRules inputStr))
          (printed (pr/print inputStr tree))
          (actualVal (rules/rulesToJson tree inputStr))
          (match? (jsonEqual? actualVal expectedVal))]
      (do
        (assert (ok? (tr/checkTilingRoot tree)) (str "rule_list tiling case " (stringFromInt64 caseIdx)))
        (assert (= printed inputStr) (str "rule_list round-trip case " (stringFromInt64 caseIdx)))
        (assert match? (str "rule_list json match case " (stringFromInt64 caseIdx)))
        (testRuleListCase! items (+ caseIdx 1) totalCases (+ passCount 1)))))

fn testDeclarationListCase! items: (List j/Json) caseIdx: Int64 totalCases: Int64 passCount: Int64 -> Bool
  (if (>= caseIdx totalCases)
    (do
      (println (str "CSS upstream declaration list: " (stringFromInt64 passCount) "/" (stringFromInt64 totalCases) " passed, 0 excluded"))
      (assert (= passCount totalCases) "all declaration list cases passed")
      true)
    (let [(inVal (optionOr (listGet items (* caseIdx 2)) (j/jstr "")))
          (inputStr (mt inVal ((j/jstr s) s) (_ "")))
          (expectedVal (optionOr (listGet items (+ (* caseIdx 2) 1)) (j/jarr (list))))
          (tree (rules/parseDeclarationList inputStr))
          (printed (pr/print inputStr tree))
          (actualVal (rules/declarationsToJson tree inputStr))
          (match? (jsonEqual? actualVal expectedVal))]
      (do
        (assert (ok? (tr/checkTilingRoot tree)) (str "declaration_list tiling case " (stringFromInt64 caseIdx)))
        (assert (= printed inputStr) (str "declaration_list round-trip case " (stringFromInt64 caseIdx)))
        (assert match? (str "declaration_list json match case " (stringFromInt64 caseIdx)))
        (testDeclarationListCase! items (+ caseIdx 1) totalCases (+ passCount 1)))))

fn testManifestVerifierSha256! -> Bool
  (let [(rlPath "asl/packages/asl-syntax/tests/fixtures/upstream/css/rule_list.json.sample")
        (dlPath "asl/packages/asl-syntax/tests/fixtures/upstream/css/declaration_list.json.sample")
        (rlContent (fileReadBytes rlPath))
        (dlContent (fileReadBytes dlPath))]
    (do
      (assert (ok? rlContent) "rule_list.json read ok")
      (assert (ok? dlContent) "declaration_list.json read ok")
      (let [(rlBs (resultOr rlContent (stringToBytes "")))
            (dlBs (resultOr dlContent (stringToBytes "")))
            (rlSha (bytesSha256 rlBs))
            (dlSha (bytesSha256 dlBs))
            (expectedRlSha "7a0629ff8747c7837211c2f645a71f32ee69a5ee058ccc4e206d835cd128e55f")
            (expectedDlSha "5d9e4680f64e9a92d9e668d1bc0a69168ab9bb8c6d392de8222b90e9dd88f052")]
        (do
          (assert (= rlSha expectedRlSha) "rule_list.json sha256 matches manifest")
          (assert (= dlSha expectedDlSha) "declaration_list.json sha256 matches manifest")
          (let [(rlEntry (crp/makeUpstreamEntry
                           "https://github.com/SimonSapin/css-parsing-tests"
                           "203ce36bffd617db7f118c551e32794561fb273d"
                           expectedRlSha
                           "CC0-1.0"
                           rlPath))
                (dlEntry (crp/makeUpstreamEntry
                           "https://github.com/SimonSapin/css-parsing-tests"
                           "203ce36bffd617db7f118c551e32794561fb273d"
                           expectedDlSha
                           "CC0-1.0"
                           dlPath))]
            (do
              (assert (ok? (crp/verifyUpstreamEntry! rlEntry)) "rule_list.json verifyUpstreamEntry passes")
              (assert (ok? (crp/verifyUpstreamEntry! dlEntry)) "declaration_list.json verifyUpstreamEntry passes")
              true))))))

fn testIndexCss! -> Bool
  (let [(contentRes (fileReadString "asl/packages/asl-syntax/tests/fixtures/css/tailwindIndex.css"))]
    (assert (ok? contentRes) "read index.css")
    (let [(cssText (resultOr contentRes ""))
          (tree (rules/parseStylesheet cssText))
          (printed (pr/print cssText tree))
          (src (src/sourceFromString "asl/packages/asl-syntax/tests/fixtures/css/tailwindIndex.css" cssText))
          (outlineSyms (rules/extractOutlineSymbols tree cssText))
          (count (listLength outlineSyms))
          (allSyms (rules/extractSymbols tree cssText))
          (customProps (filter (fn [(s sym/SymbolDef)] -> Bool (= (sym/symbolKind s) "property")) allSyms))]
      (do
        (assert (ok? (tr/checkTilingRoot tree)) "index.css tiling")
        (assert (= printed cssText) "index.css round-trip")
        (assert (= count 29) "29 outline symbols in index.css")
        (assert (= (listLength customProps) 26) "26 custom properties in index.css")
        (let [(receipt (out/formatOutlineReceipt "asl/packages/asl-syntax/tests/fixtures/css/tailwindIndex.css" "css" outlineSyms src))]
          (do
            (assert (stringStartsWith? receipt "(:outline :status :ok :file ") "receipt starts with outline")
            (assert (stringContains? receipt ":itemsCount 29") "receipt itemsCount 29")
            (assert (stringContains? receipt ":name \"@tailwind base\" :kind \"at-rule\" :start 1 :end 1") "tailwind base item")
            (assert (stringContains? receipt ":name \"base\" :kind \"layer\" :start 5 :end 92") "layer base item")
            (assert (stringContains? receipt ":name \":root\" :kind \"selector\" :start 6 :end 20") "root selector item")
            (assert (stringContains? receipt ":name \".dark\" :kind \"selector\" :start 22 :end 36") "dark selector item")
            (assert (stringContains? receipt ":name \"components\" :kind \"layer\" :start 94 :end 149") "layer components item")
            (assert (stringContains? receipt ":name \".rule-hairline\" :kind \"selector\" :start 95 :end 98") "rule hairline selector item")
            (assert (stringContains? receipt ":name \"(prefers-reduced-motion: reduce)\" :kind \"media\" :start 151 :end 160") "media query item")
            (assert (stringContains? receipt ":name \"*, *::before, *::after\" :kind \"selector\" :start 155 :end 159") "wildcard selector item")
            true)))))

fn testCssNestingAndSymbols -> Bool
  (let [(code "header { font-size: 14px; nav { color: blue; } }")
        (tree (rules/parseStylesheet code))
        (syms (rules/extractSymbols tree code))]
    (do
      (assert (ok? (tr/checkTilingRoot tree)) "nesting tiling")
      (assert (= (pr/print code tree) code) "nesting round-trip")
      (assert (= (listLength syms) 2) "2 nested selector symbols")
      (let [(s1 (optionOr (listHead syms) (sym/makeSymbolDef "" "" 0 0)))
            (r1 (optionOr (listTail syms) (list)))
            (s2 (optionOr (listHead r1) (sym/makeSymbolDef "" "" 0 0)))]
        (do
          (assert (= (sym/symbolName s1) "header") "header name")
          (assert (= (sym/symbolKind s1) "selector") "header kind")
          (assert (= (sym/symbolDepth s1) 0) "header depth 0")
          (assert (= (sym/symbolName s2) "nav") "nav name")
          (assert (= (sym/symbolKind s2) "selector") "nav kind")
          (assert (= (sym/symbolContainer s2) "header") "nav container header")
          (assert (= (sym/symbolDepth s2) 1) "nav depth 1")
          true))))

fn testDeclarationsAndImportant -> Bool
  (let [(code "color: red !important; margin: 10px; --accent: #ff00ff;")
        (tree (rules/parseDeclarationList code))
        (children (tr/nodeChildren tree))
        (decls (filter (fn [(e tr/TreeElement)] -> Bool
                         (mt e
                           ((elemToken _) false)
                           ((elemNode n) (= (tr/nodeKind n) "declaration"))))
                       children))]
    (do
      (assert (ok? (tr/checkTilingRoot tree)) "decls tiling")
      (assert (= (pr/print code tree) code) "decls round-trip")
      (assert (= (listLength decls) 3) "3 declarations parsed")
      (let [(d1Elem (optionOr (listHead decls) (tr/elemToken (tr/makeToken "" 0 0))))
            (r1 (optionOr (listTail decls) (list)))
            (d2Elem (optionOr (listHead r1) (tr/elemToken (tr/makeToken "" 0 0))))
            (r2 (optionOr (listTail r1) (list)))
            (d3Elem (optionOr (listHead r2) (tr/elemToken (tr/makeToken "" 0 0))))]
        (mt d1Elem
          ((elemNode d1)
           (mt d2Elem
             ((elemNode d2)
              (mt d3Elem
                ((elemNode d3)
                 (do
                   (assert (rules/isImportantDeclaration? d1 code) "d1 is important")
                   (assert (not (rules/isImportantDeclaration? d2 code)) "d2 is not important")
                   (assert (not (rules/isImportantDeclaration? d3 code)) "d3 is not important")
                   true))
                ((elemToken _) false)))
             ((elemToken _) false)))
          ((elemToken _) false)))))

fn testAtRulesWithBlocksAndOutline -> Bool
  (let [(code "@supports (display: grid) { .grid-box { display: grid; } }\n@keyframes fadeIn { from { opacity: 0; } to { opacity: 1; } }\n@container (min-width: 600px) { .sidebar { width: 250px; } }")
        (tree (rules/parseStylesheet code))
        (syms (rules/extractOutlineSymbols tree code))]
    (do
      (assert (ok? (tr/checkTilingRoot tree)) "at-rules tiling")
      (assert (= (pr/print code tree) code) "at-rules round-trip")
      (let [(supportsSym (filter (fn [(s sym/SymbolDef)] -> Bool (= (sym/symbolKind s) "supports")) syms))
            (keyframesSym (filter (fn [(s sym/SymbolDef)] -> Bool (= (sym/symbolKind s) "keyframes")) syms))
            (containerSym (filter (fn [(s sym/SymbolDef)] -> Bool (= (sym/symbolKind s) "container")) syms))]
        (do
          (assert (= (listLength supportsSym) 1) "1 supports symbol")
          (assert (= (listLength keyframesSym) 1) "1 keyframes symbol")
          (assert (= (listLength containerSym) 1) "1 container symbol")
          (let [(s1 (optionOr (listHead supportsSym) (sym/makeSymbolDef "" "" 0 0)))
                (k1 (optionOr (listHead keyframesSym) (sym/makeSymbolDef "" "" 0 0)))
                (c1 (optionOr (listHead containerSym) (sym/makeSymbolDef "" "" 0 0)))]
            (do
              (assert (= (sym/symbolName s1) "(display: grid)") "supports name")
              (assert (= (sym/symbolName k1) "fadeIn") "keyframes name")
              (assert (= (sym/symbolName c1) "(min-width: 600px)") "container name")
              true))))))

fn testErrorRecovery -> Bool
  (let [(brokenCode "div { color: ; @bad } p { color: blue")
        (tree (rules/parseStylesheet brokenCode))]
    (do
      (assert (ok? (tr/checkTilingRoot tree)) "broken code tiling")
      (assert (= (pr/print brokenCode tree) brokenCode) "broken code round-trip")
      true))

fn testUpstreamRulesSuite! -> Bool
  (let [(contentRes (fileReadString "asl/packages/asl-syntax/tests/fixtures/upstream/css/rule_list.json.sample"))]
    (assert (ok? contentRes) "read rule_list.json")
    (let [(jsonStr (resultOr contentRes ""))
          (parseRes (j/jsonParse jsonStr))]
      (assert (ok? parseRes) "parse rule_list.json")
      (mt (resultOr parseRes (j/jnull))
        ((j/jarr items)
         (testRuleListCase! items 0 (/ (listLength items) 2) 0))
        (_ (assert false "expected array")))))

fn testUpstreamDeclarationsSuite! -> Bool
  (let [(contentRes2 (fileReadString "asl/packages/asl-syntax/tests/fixtures/upstream/css/declaration_list.json.sample"))]
    (assert (ok? contentRes2) "read declaration_list.json")
    (let [(jsonStr2 (resultOr contentRes2 ""))
          (parseRes2 (j/jsonParse jsonStr2))]
      (assert (ok? parseRes2) "parse declaration_list.json")
      (mt (resultOr parseRes2 (j/jnull))
        ((j/jarr items2)
         (testDeclarationListCase! items2 0 (/ (listLength items2) 2) 0))
        (_ (assert false "expected array")))))

fn ! runTests -> Bool
  (do
    (assert (testManifestVerifierSha256!) "manifest verifier sha256")
    (assert (testUpstreamRulesSuite!) "upstream rules suite")
    (assert (testUpstreamDeclarationsSuite!) "upstream declarations suite")
    (assert (testIndexCss!) "index.css outline and round-trip")
    (assert (testCssNestingAndSymbols) "css nesting and symbols")
    (assert (testDeclarationsAndImportant) "declarations and important")
    (assert (testAtRulesWithBlocksAndOutline) "at-rules with blocks and outline")
    (assert (testErrorRecovery) "error recovery")
    true)
