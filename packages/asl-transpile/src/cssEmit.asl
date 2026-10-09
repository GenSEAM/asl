(module asl-transpile/cssEmit :x [asnToCss asnToCssStr renderCssVariables renderCssRule renderMediaBlock formatCssProperty] :i [(asl-parser/reader :a rd) (asl-parser/lexer :a lx) (asl-parser/ast :a ast) (asl-text/text :a txt) (asl-transpile/cssCascade :a cascade)])

fn formatCssProperty prop: cascade/CssProperty minify: Bool -> Str
  (let [(name prop.name) (val prop.value) (imp prop.important)] (if minify (if imp (str name ":" val "!important") (str name ":" val)) (if imp (str "  " name ": " val " !important;") (str "  " name ": " val ";"))))

fn renderCssVariables vars: (List (Pair Str Str)) minify: Bool -> Str
  (if (listEmpty? vars) "" (let [(cleanVars (map (fn [(v (pair Str Str))] -> (Pair Str Str) (let [(rawName (pairFirst v)) (cleanName (if (stringStartsWith? rawName "--") rawName (str "--" (txt/stripColon rawName)))) (rawVal (pairSecond v))] (pair cleanName rawVal))) vars))] (if minify (let [(props (map (fn [(p (pair Str Str))] -> Str (str (pairFirst p) ":" (pairSecond p))) cleanVars))] (str ":root{" (stringJoin props ";") "}")) (let [(lines (map (fn [(p (pair Str Str))] -> Str (str "  " (pairFirst p) ": " (pairSecond p) ";")) cleanVars))] (str ":root {\n" (stringJoin lines "\n") "\n}")))))

fn renderCssRule rule: cascade/CssRule minify: Bool -> Str
  (let [(sel rule.selector) (props rule.properties)] (if minify (if (listEmpty? props) (str sel "{}") (let [(propStrs (map (fn [(p cascade/CssProperty)] -> Str (formatCssProperty p true)) props))] (str sel "{" (stringJoin propStrs ";") "}"))) (if (listEmpty? props) (str sel " {}") (let [(propStrs (map (fn [(p cascade/CssProperty)] -> Str (formatCssProperty p false)) props))] (str sel " {\n" (stringJoin propStrs "\n") "\n}")))))

fn renderMediaBlock query: Str rules: (List cascade/CssRule) minify: Bool -> Str
  (if (listEmpty? rules) (if minify (str "@media " query "{}") (str "@media " query " {}")) (if minify (let [(rendered (map (fn [(r cascade/CssRule)] -> Str (renderCssRule r true)) rules))] (str "@media " query "{" (stringJoin rendered "") "}")) (let [(rendered (map (fn [(r cascade/CssRule)] -> Str (let [(rStr (renderCssRule r false)) (lines (stringSplit rStr "\n")) (indented (map (fn [(l Str)] -> Str (str "  " l)) lines))] (stringJoin indented "\n"))) rules))] (str "@media " query " {\n" (stringJoin rendered "\n\n") "\n}"))))

fn sexprToAtomStr expr: rd/SExpr -> Str
  (mt expr ((rd/sexprAtom v) (txt/stripQuotes v)) ((rd/sexprList _) "") ((rd/sexprVect _) ""))

fn parsePropsList items: (List rd/SExpr) -> (List cascade/CssProperty)
  (fold (fn [(acc (List cascade/CssProperty)) (it rd/SExpr)] -> (List cascade/CssProperty) (mt it ((rd/sexprList sub) (if (>= (listLength sub) 2) (let [(n (txt/stripColon (sexprToAtomStr (optionOr (listHead sub) (rd/makeAtom ""))))) (vRaw (sexprToAtomStr (optionOr (listHead (optionOr (listTail sub) (list))) (rd/makeAtom "")))) (imp (stringContains? vRaw "!important")) (v (stringTrim (stringReplace vRaw "!important" "")))] (if (> (stringLength n) 0) (listAppend acc (list (cascade/CssProperty :name n :value v :important imp))) acc)) acc)) ((rd/sexprVect sub) (if (>= (listLength sub) 2) (let [(n (txt/stripColon (sexprToAtomStr (optionOr (listHead sub) (rd/makeAtom ""))))) (vRaw (sexprToAtomStr (optionOr (listHead (optionOr (listTail sub) (list))) (rd/makeAtom "")))) (imp (stringContains? vRaw "!important")) (v (stringTrim (stringReplace vRaw "!important" "")))] (if (> (stringLength n) 0) (listAppend acc (list (cascade/CssProperty :name n :value v :important imp))) acc)) acc)) ((rd/sexprAtom _) acc))) (list) items)

fn parsePropFromSexpr expr: rd/SExpr -> (List cascade/CssProperty)
  (mt expr ((rd/sexprList items) (parsePropsList items)) ((rd/sexprVect items) (parsePropsList items)) ((rd/sexprAtom _) (list)))

fn findKeywordVal items: (List rd/SExpr) kw: Str -> Str
  (mt (listHead items) ((none) "") ((some it) (let [(tail (optionOr (listTail items) (list)))] (mt it ((rd/sexprAtom v) (if (or (= v kw) (or (= v (txt/stripColon kw)) (= (txt/stripColon v) (txt/stripColon kw)))) (mt (listHead tail) ((some nextIt) (sexprToAtomStr nextIt)) ((none) "")) (findKeywordVal tail kw))) ((rd/sexprList _) (findKeywordVal tail kw)) ((rd/sexprVect _) (findKeywordVal tail kw))))))

fn findKeywordSexpr items: (List rd/SExpr) kw: Str -> rd/SExpr
  (mt (listHead items) ((none) (rd/makeList (list))) ((some it) (let [(tail (optionOr (listTail items) (list)))] (mt it ((rd/sexprAtom v) (if (or (= v kw) (or (= v (txt/stripColon kw)) (= (txt/stripColon v) (txt/stripColon kw)))) (mt (listHead tail) ((some nextIt) nextIt) ((none) (rd/makeList (list)))) (findKeywordSexpr tail kw))) ((rd/sexprList _) (findKeywordSexpr tail kw)) ((rd/sexprVect _) (findKeywordSexpr tail kw))))))

fn parseRuleFromSexpr expr: rd/SExpr order: I64 -> (Option cascade/CssRule)
  (mt expr ((rd/sexprList items) (let [(headTag (rd/sexprHead expr))] (if (or (= headTag ":rule") (= headTag "rule")) (let [(tail (optionOr (listTail items) (list))) (sel (findKeywordVal tail ":selector")) (propsExpr (findKeywordSexpr tail ":props")) (props (parsePropFromSexpr propsExpr)) (spec (cascade/calcSpecificity sel))] (some (cascade/CssRule :selector sel :specificity spec :properties props :sourceOrder order))) (if (>= (listLength items) 2) (let [(firstIt (optionOr (listHead items) (rd/makeAtom ""))) (sel (sexprToAtomStr firstIt)) (secondIt (optionOr (listHead (optionOr (listTail items) (list))) (rd/makeAtom ""))) (props (parsePropFromSexpr secondIt)) (spec (cascade/calcSpecificity sel))] (if (> (stringLength sel) 0) (some (cascade/CssRule :selector sel :specificity spec :properties props :sourceOrder order)) (none))) (none))))) ((rd/sexprVect _) (none)) ((rd/sexprAtom _) (none)))

fn parseVarPairs items: (List rd/SExpr) -> (List (Pair Str Str))
  (fold (fn [(acc (List (pair Str Str))) (it rd/SExpr)] -> (List (Pair Str Str)) (mt it ((rd/sexprList sub) (if (>= (listLength sub) 2) (let [(k (sexprToAtomStr (optionOr (listHead sub) (rd/makeAtom "")))) (v (sexprToAtomStr (optionOr (listHead (optionOr (listTail sub) (list))) (rd/makeAtom ""))))] (listAppend acc (list (pair k v)))) acc)) ((rd/sexprVect sub) (if (>= (listLength sub) 2) (let [(k (sexprToAtomStr (optionOr (listHead sub) (rd/makeAtom "")))) (v (sexprToAtomStr (optionOr (listHead (optionOr (listTail sub) (list))) (rd/makeAtom ""))))] (listAppend acc (list (pair k v)))) acc)) ((rd/sexprAtom _) acc))) (list) items)

fn extractVariables items: (List rd/SExpr) -> (List (Pair Str Str))
  (let [(varsSexpr (findKeywordSexpr items ":vars"))] (mt varsSexpr ((rd/sexprList vItems) (parseVarPairs vItems)) ((rd/sexprVect vItems) (parseVarPairs vItems)) ((rd/sexprAtom _) (list))))

fn parseDirectRules items: (List rd/SExpr) order: I64 -> (List cascade/CssRule)
  (mt (listHead items) ((none) (list)) ((some it) (let [(tail (optionOr (listTail items) (list))) (mRule (parseRuleFromSexpr it order))] (mt mRule ((some r) (cons r (parseDirectRules tail (+ order 1)))) ((none) (parseDirectRules tail order))))))

fn parseRuleList items: (List rd/SExpr) -> (List cascade/CssRule)
  (parseDirectRules items 0)

fn extractRules items: (List rd/SExpr) -> (List cascade/CssRule)
  (let [(rulesSexpr (findKeywordSexpr items ":rules"))] (mt rulesSexpr ((rd/sexprList rItems) (parseRuleList rItems)) ((rd/sexprVect rItems) (parseRuleList rItems)) ((rd/sexprAtom _) (parseDirectRules items 0))))

fn extractMedia items: (List rd/SExpr) -> (List (Pair Str (List cascade/CssRule)))
  (let [(mediaSexpr (findKeywordSexpr items ":media"))] (mt mediaSexpr ((rd/sexprList mItems) (let [(hd (rd/sexprHead mediaSexpr))] (if (or (= hd ":media") (= hd "media")) (let [(tail (optionOr (listTail mItems) (list))) (q (findKeywordVal tail ":query")) (rulesExpr (findKeywordSexpr tail ":rules")) (rules (mt rulesExpr ((rd/sexprList rList) (parseRuleList rList)) ((rd/sexprVect rList) (parseRuleList rList)) ((rd/sexprAtom _) (list))))] (list (pair q rules))) (fold (fn [(acc (List (pair Str (List cascade/CssRule)))) (it rd/SExpr)] -> (List (Pair Str (List cascade/CssRule))) (mt it ((rd/sexprList sub) (let [(q (findKeywordVal sub ":query")) (rulesExpr (findKeywordSexpr sub ":rules")) (rules (mt rulesExpr ((rd/sexprList rList) (parseRuleList rList)) ((rd/sexprVect rList) (parseRuleList rList)) ((rd/sexprAtom _) (list))))] (if (> (stringLength q) 0) (listAppend acc (list (pair q rules))) acc))) (_ acc))) (list) mItems)))) ((rd/sexprVect _) (list)) ((rd/sexprAtom _) (list))))

fn emitFromItems items: (List rd/SExpr) minify: Bool -> Str
  (let [(vars (extractVariables items)) (rules (extractRules items)) (mediaBlocks (extractMedia items)) (varStr (renderCssVariables vars minify)) (ruleStrs (map (fn [(r cascade/CssRule)] -> Str (renderCssRule r minify)) rules)) (mediaStrs (map (fn [(m (pair Str (List cascade/CssRule)))] -> Str (renderMediaBlock (pairFirst m) (pairSecond m) minify)) mediaBlocks)) (parts (listAppend (if (stringEmpty? varStr) (list) (list varStr)) (listAppend ruleStrs mediaStrs))) (allNonEmpty (filter (fn [(s Str)] -> Bool (not (stringEmpty? s))) parts))] (if minify (stringJoin allNonEmpty "") (stringJoin allNonEmpty "\n\n")))

fn asnToCss styleExpr: rd/SExpr minify: Bool -> Str
  (mt styleExpr ((rd/sexprAtom v) (let [(clean (stringTrim (txt/stripQuotes v)))] clean)) ((rd/sexprList items) (emitFromItems items minify)) ((rd/sexprVect items) (emitFromItems items minify)))

fn asnToCssStr styleStr: Str minify: Bool -> Str
  (let [(trimmed (stringTrim styleStr))] (if (stringEmpty? trimmed) "" (let [(toks (lx/tokenize trimmed)) (formsRes (ast/readForms toks))] (mt formsRes ((err _) "") ((ok forms) (if (listEmpty? forms) "" (let [(pf (optionOr (listHead forms) (ast/PosForm :expr (rd/makeAtom "") :line 0 :col 0)))] (asnToCss pf.expr minify))))))))
