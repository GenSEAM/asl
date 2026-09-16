(module asl-parser/indentParser
  :d "Pure ASL v0.4 Indented Reader and SExpr Desugaring Engine."
  :x [parseIndented parseIndentedForms desugarDot desugarInterpolation desugarTry desugarDestructuring]
  :i [(indentLexer :a lx) (reader :a rd)])

(df desugarDot [(name String)] -> rd/SExpr
  :d "Lowers compound dot identifier x.f.g to canonical (.-g (.-f x))."
  (if (or (string-starts-with? name ".") (not (string-contains? name ".")))
    (rd/makeAtom name)
    (let [(parts (string-split name "."))]
      (if (< (list-length parts) 2)
        (rd/makeAtom name)
        (let [(headPart (option-or (list-head parts) ""))
              (tailParts (option-or (list-tail parts) (list)))]
          (fold (fn [(acc rd/SExpr) (field String)] -> rd/SExpr
                  (rd/makeList (list (rd/makeAtom (str ".-" field)) acc)))
                (rd/makeAtom headPart)
                tailParts))))))

(df desugarInterpolation [(parts (List String)) (exprs (List String))] -> rd/SExpr
  :d "Lowers interpolated string \"{a}: {b}\" to (str a \": \" b)."
  (let [(pairs (fold (fn [(acc (Pair (List rd/SExpr) (List String))) (part String)]
                       -> (Pair (List rd/SExpr) (List String))
                       (let [(accum (.-first acc))
                             (remExprs (.-second acc))]
                         (let [(partSexpr (if (= part "") (list) (list (rd/makeAtom (str "\"" part "\"")))))]
                           (mt (list-head remExprs)
                             ((some ex)
                              (let [(exSexpr (desugarDot ex))
                                    (nxtRem (option-or (list-tail remExprs) (list)))]
                                (pair (list-append accum (list-append partSexpr (list exSexpr))) nxtRem)))
                             ((none)
                              (pair (list-append accum partSexpr) remExprs))))))
                     (pair (list) exprs)
                     parts))]
    (rd/makeList (cons (rd/makeAtom "str") (.-first pairs)))))

(df desugarTry [(expr rd/SExpr)] -> rd/SExpr
  :d "Lowers try expression expr? into early-return match form."
  (let [(okArm (rd/makeList (list (rd/makeAtom "ok") (rd/makeAtom "__v") (rd/makeAtom "__v"))))
        (errRet (rd/makeList (list (rd/makeAtom "return") (rd/makeList (list (rd/makeAtom "err") (rd/makeAtom "__e"))))))
        (errArm (rd/makeList (list (rd/makeAtom "err") (rd/makeAtom "__e") errRet)))]
    (rd/makeList (list (rd/makeAtom "match") expr okArm errArm))))

(dfs ParseExprResult
  (:f rest (List lx/IndentToken) "Remaining tokens")
  (:f expr rd/SExpr "Parsed SExpr"))

(df parseSingleTokenExpr [(tok lx/IndentToken)] -> rd/SExpr
  :d "Converts single token to SExpr with dot and string desugaring."
  (mt (.-kind tok)
    ((tokSymbol s)       (desugarDot s))
    ((tokKeyword k)      (rd/makeAtom k))
    ((tokString s)       (rd/makeAtom (str "\"" s "\"")))
    ((tokInterp pts exs) (desugarInterpolation pts exs))
    ((tokInt n)          (rd/makeAtom (string-from-int64 n)))
    ((tokFloat f)        (rd/makeAtom (.-rawText tok)))
    ((tokQuestion)       (rd/makeAtom "?"))
    (_                   (rd/makeAtom (.-rawText tok)))))

(df skipNewlines [(toks (List lx/IndentToken))] -> (List lx/IndentToken)
  :d "Skips leading newline tokens."
  (mt (list-head toks)
    ((some t)
     (mt (.-kind t)
       ((tokNewline) (skipNewlines (option-or (list-tail toks) (list))))
       (_            toks)))
    ((none) (list))))

(df takeUntilLineEnd [(toks (List lx/IndentToken))] -> (Pair (List lx/IndentToken) (List lx/IndentToken))
  :d "Splits tokens on current line until newline, indent, dedent or eof."
  (let [(step (fold (fn [(acc (Pair (List lx/IndentToken) (Pair (List lx/IndentToken) Bool))) (t lx/IndentToken)]
                      -> (Pair (List lx/IndentToken) (Pair (List lx/IndentToken) Bool))
                      (let [(cur (.-first acc))
                            (rem (.-first (.-second acc)))
                            (stopped (.-second (.-second acc)))]
                        (if stopped
                          (pair cur (pair (cons t rem) true))
                          (mt (.-kind t)
                            ((tokNewline) (pair cur (pair rem true)))
                            ((tokIndent _) (pair cur (pair (cons t rem) true)))
                            ((tokDedent _) (pair cur (pair (cons t rem) true)))
                            ((tokEof)     (pair cur (pair (cons t rem) true)))
                            (_            (pair (cons t cur) (pair rem false)))))))
                    (pair (list) (pair (list) false))
                    toks))]
    (pair (list-reverse (.-first step)) (list-reverse (.-first (.-second step))))))

(df parseParenGroup [(toks (List lx/IndentToken))] -> (Pair (List lx/IndentToken) (List rd/SExpr))
  :d "Collects tokens inside ( ... ) into a list of SExpr."
  (let [(step (fold (fn [(acc (Pair (Pair Int64 (List rd/SExpr)) (Pair (List lx/IndentToken) Bool))) (t lx/IndentToken)]
                      -> (Pair (Pair Int64 (List rd/SExpr)) (Pair (List lx/IndentToken) Bool))
                      (let [(depth (.-first (.-first acc)))
                            (items (.-second (.-first acc)))
                            (rem (.-first (.-second acc)))
                            (done (.-second (.-second acc)))]
                        (if done
                          (pair (pair depth items) (pair (cons t rem) true))
                          (mt (.-kind t)
                            ((tokLparen)
                             (if (= depth 0)
                               (pair (pair 1 items) (pair rem false))
                               (pair (pair (+ depth 1) items) (pair rem false))))
                            ((tokRparen)
                             (if (<= depth 1)
                               (pair (pair 0 items) (pair rem true))
                               (pair (pair (- depth 1) items) (pair rem false))))
                            ((tokQuestion)
                             (if (= depth 1)
                               (mt (list-head items)
                                 ((some prevExpr)
                                  (let [(remItems (option-or (list-tail items) (list)))
                                        (desugared (desugarTry prevExpr))]
                                    (pair (pair depth (cons desugared remItems)) (pair rem false))))
                                 ((none)
                                  (pair (pair depth (cons (parseSingleTokenExpr t) items)) (pair rem false))))
                               (pair (pair depth (cons (parseSingleTokenExpr t) items)) (pair rem false))))
                            (_
                             (pair (pair depth (cons (parseSingleTokenExpr t) items)) (pair rem false)))))))
                    (pair (pair 0 (list)) (pair (list) false))
                    toks))]
    (pair (list-reverse (.-first (.-second step)))
          (list-reverse (.-second (.-first step))))))

(df parseBracketGroup [(toks (List lx/IndentToken))] -> (Pair (List lx/IndentToken) (List rd/SExpr))
  :d "Collects tokens inside [ ... ] into a list of SExpr."
  (let [(step (fold (fn [(acc (Pair (Pair Int64 (List rd/SExpr)) (Pair (List lx/IndentToken) Bool))) (t lx/IndentToken)]
                      -> (Pair (Pair Int64 (List rd/SExpr)) (Pair (List lx/IndentToken) Bool))
                      (let [(depth (.-first (.-first acc)))
                            (items (.-second (.-first acc)))
                            (rem (.-first (.-second acc)))
                            (done (.-second (.-second acc)))]
                        (if done
                          (pair (pair depth items) (pair (cons t rem) true))
                          (mt (.-kind t)
                            ((tokLbracket)
                             (if (= depth 0)
                               (pair (pair 1 items) (pair rem false))
                               (pair (pair (+ depth 1) items) (pair rem false))))
                            ((tokRbracket)
                             (if (<= depth 1)
                               (pair (pair 0 items) (pair rem true))
                               (pair (pair (- depth 1) items) (pair rem false))))
                            ((tokQuestion)
                             (if (= depth 1)
                               (mt (list-head items)
                                 ((some prevExpr)
                                  (let [(remItems (option-or (list-tail items) (list)))
                                        (desugared (desugarTry prevExpr))]
                                    (pair (pair depth (cons desugared remItems)) (pair rem false))))
                                 ((none)
                                  (pair (pair depth (cons (parseSingleTokenExpr t) items)) (pair rem false))))
                               (pair (pair depth (cons (parseSingleTokenExpr t) items)) (pair rem false))))
                            (_
                             (pair (pair depth (cons (parseSingleTokenExpr t) items)) (pair rem false)))))))
                    (pair (pair 0 (list)) (pair (list) false))
                    toks))]
    (pair (list-reverse (.-first (.-second step)))
          (list-reverse (.-second (.-first step))))))

(df desugarDestructuring [(isRecord Bool) (vars (List String)) (expr rd/SExpr) (bodyForms (List rd/SExpr))] -> rd/SExpr
  :d "Lowers list or record pattern destructuring into canonical let SExpr."
  (let [(finalBody (if (list-empty? bodyForms)
                     (list (rd/makeAtom "<body>"))
                     bodyForms))]
    (if isRecord
      (let [(bindings (map (fn [(v String)] -> rd/SExpr
                             (let [(fieldSym (rd/makeAtom (str ".-" v)))
                                   (getter (rd/makeList (list fieldSym expr)))]
                               (rd/makeList (list (rd/makeAtom v) getter))))
                           vars))
            (bVect (rd/makeVect bindings))]
        (rd/makeList (cons (rd/makeAtom "let") (cons bVect finalBody))))
      (let [(bindingsFold (fold (fn [(acc (Pair (List rd/SExpr) Int64)) (v String)] -> (Pair (List rd/SExpr) Int64)
                                  (let [(curList (.-first acc))
                                        (idx (.-second acc))
                                        (idxAtom (rd/makeAtom (string-from-int64 idx)))
                                        (getter (rd/makeList (list (rd/makeAtom "list-get") expr idxAtom)))
                                        (binding (rd/makeList (list (rd/makeAtom v) getter)))]
                                    (pair (list-append curList (list binding)) (+ idx 1))))
                                (pair (list) 0)
                                vars))
            (bVect (rd/makeVect (.-first bindingsFold)))]
        (rd/makeList (cons (rd/makeAtom "let") (cons bVect finalBody)))))))

(df stripTrailingComma [(s String)] -> String
  :d "Strips trailing comma from identifier string if present."
  (if (string-ends-with? s ",")
    (option-or (string-slice s 0 (- (string-length s) 1)) s)
    s))

(dfs PatternExtractResult
  (:f vars (List String) "Extracted variable names")
  (:f rest (List lx/IndentToken) "Tokens after pattern delimiter"))

(df extractPatternVars [(toks (List lx/IndentToken)) (isRecord Bool)] -> PatternExtractResult
  :d "Extracts variable names from [a b ...] or {x y ...} pattern."
  (let [(step (fold (fn [(acc (Pair (List String) (Pair (List lx/IndentToken) Bool))) (t lx/IndentToken)]
                      -> (Pair (List String) (Pair (List lx/IndentToken) Bool))
                      (let [(vars (.-first acc))
                            (rem (.-first (.-second acc)))
                            (done (.-second (.-second acc)))]
                        (if done
                          (pair vars (pair (cons t rem) true))
                          (let [(isClosing (if isRecord
                                             (or (= (.-rawText t) "}") (mt (.-kind t) ((tokRbrace) true) (_ false)))
                                             (or (= (.-rawText t) "]") (mt (.-kind t) ((tokRbracket) true) (_ false)))))]
                            (if isClosing
                              (pair vars (pair rem true))
                              (let [(cleaned (stripTrailingComma (.-rawText t)))]
                                (if (or (string-empty? cleaned) (= cleaned ","))
                                  acc
                                  (pair (cons cleaned vars) (pair rem false)))))))))
                    (pair (list) (pair (list) false))
                    toks))]
    (PatternExtractResult :vars (list-reverse (.-first step))
                          :rest (list-reverse (.-first (.-second step))))))

(df splitTokensAtWord [(toks (List lx/IndentToken)) (word String)] -> (Pair (List lx/IndentToken) (Pair (List lx/IndentToken) Bool))
  :d "Splits token list before and after a specific keyword or symbol."
  (let [(step (fold (fn [(acc (Pair (List lx/IndentToken) (Pair (List lx/IndentToken) Bool))) (t lx/IndentToken)]
                      -> (Pair (List lx/IndentToken) (Pair (List lx/IndentToken) Bool))
                      (let [(before (.-first acc))
                            (after (.-first (.-second acc)))
                            (found (.-second (.-second acc)))]
                        (if found
                          (pair before (pair (cons t after) true))
                          (if (= (.-rawText t) word)
                            (pair before (pair after true))
                            (pair (cons t before) (pair after false))))))
                    (pair (list) (pair (list) false))
                    toks))]
    (pair (list-reverse (.-first step))
          (pair (list-reverse (.-first (.-second step)))
                (.-second (.-second step))))))

(df splitTokensAtColon [(toks (List lx/IndentToken))] -> (Pair (List lx/IndentToken) (Pair (List lx/IndentToken) Bool))
  :d "Splits token list before and after a colon token."
  (let [(step (fold (fn [(acc (Pair (List lx/IndentToken) (Pair (List lx/IndentToken) Bool))) (t lx/IndentToken)]
                      -> (Pair (List lx/IndentToken) (Pair (List lx/IndentToken) Bool))
                      (let [(before (.-first acc))
                            (after (.-first (.-second acc)))
                            (found (.-second (.-second acc)))]
                        (if found
                          (pair before (pair (cons t after) true))
                          (if (or (= (.-rawText t) ":") (mt (.-kind t) ((tokColon) true) (_ false)))
                            (pair before (pair after true))
                            (pair (cons t before) (pair after false))))))
                    (pair (list) (pair (list) false))
                    toks))]
    (pair (list-reverse (.-first step))
          (pair (list-reverse (.-first (.-second step)))
                (.-second (.-second step))))))

(df parseTokensToExprList [(toks (List lx/IndentToken))] -> (List rd/SExpr)
  :d "Converts a sequence of tokens on one line into a list of SExpr items."
  (let [(items (fold (fn [(acc (Pair (List rd/SExpr) (Pair (List lx/IndentToken) (Pair Int64 Int64)))) (t lx/IndentToken)]
                       -> (Pair (List rd/SExpr) (Pair (List lx/IndentToken) (Pair Int64 Int64)))
                       (let [(collected (.-first acc))
                             (subToks (.-first (.-second acc)))
                             (parenDepth (.-first (.-second (.-second acc))))
                             (bracketDepth (.-second (.-second (.-second acc))))]
                         (mt (.-kind t)
                           ((tokLparen)
                            (let [(nxtP (+ parenDepth 1))]
                              (pair collected (pair (cons t subToks) (pair nxtP bracketDepth)))))
                           ((tokRparen)
                            (let [(nxtP (- parenDepth 1))]
                              (if (and (<= nxtP 0) (= bracketDepth 0))
                                (let [(allParenToks (list-reverse (cons t subToks)))
                                      (parenItems (.-second (parseParenGroup allParenToks)))
                                      (subSexpr (rd/makeList parenItems))]
                                  (pair (cons subSexpr collected) (pair (list) (pair 0 0))))
                                (pair collected (pair (cons t subToks) (pair nxtP bracketDepth))))))
                           ((tokLbracket)
                            (let [(nxtB (+ bracketDepth 1))]
                              (pair collected (pair (cons t subToks) (pair parenDepth nxtB)))))
                           ((tokRbracket)
                            (let [(nxtB (- bracketDepth 1))]
                              (if (and (<= nxtB 0) (= parenDepth 0))
                                (let [(allBrkToks (list-reverse (cons t subToks)))
                                      (brkItems (.-second (parseBracketGroup allBrkToks)))
                                      (subSexpr (rd/makeList (cons (rd/makeAtom "list") brkItems)))]
                                  (pair (cons subSexpr collected) (pair (list) (pair 0 0))))
                                (pair collected (pair (cons t subToks) (pair parenDepth nxtB))))))
                           ((tokQuestion)
                            (if (or (> parenDepth 0) (> bracketDepth 0))
                              (pair collected (pair (cons t subToks) (pair parenDepth bracketDepth)))
                              (mt (list-head collected)
                                ((some prevExpr)
                                 (let [(rem (option-or (list-tail collected) (list)))
                                       (desugared (desugarTry prevExpr))]
                                   (pair (cons desugared rem) (pair (list) (pair 0 0)))))
                                ((none)
                                 (pair (cons (parseSingleTokenExpr t) collected) (pair (list) (pair 0 0)))))))
                           (_
                            (if (or (> parenDepth 0) (> bracketDepth 0))
                              (pair collected (pair (cons t subToks) (pair parenDepth bracketDepth)))
                              (pair (cons (parseSingleTokenExpr t) collected) (pair (list) (pair 0 0))))))))
                     (pair (list) (pair (list) (pair 0 0)))
                     toks))]
    (list-reverse (.-first items))))

(df isLetDestructureLine? [(toks (List lx/IndentToken))] -> Bool
  :d "Checks if tokens start a let list/record destructuring line."
  (mt (list-head toks)
    ((none) false)
    ((some t0)
     (if (and (= (.-rawText t0) "let") (> (list-length toks) 1))
       (let [(t1 (option-or (list-get toks 1) t0))]
         (or (= (.-rawText t1) "[")
             (or (= (.-rawText t1) "{")
                 (mt (.-kind t1)
                   ((tokLbracket) true)
                   ((tokLbrace)   true)
                   (_             false)))))
       false))))

(dfs LetLineInfo
  (:f isRecord Bool "True for brace pattern, false for bracket pattern")
  (:f vars (List String) "Pattern variables")
  (:f expr rd/SExpr "Desugared value expression")
  (:f inlineBody (List rd/SExpr) "Inline body expressions if any")
  (:f hasInlineBody Bool "True if inline body was present on same line"))

(df parseLetLineInfo [(toks (List lx/IndentToken))] -> LetLineInfo
  :d "Extracts pattern, value expression, and optional inline body from let line tokens."
  (let [(toksAfterLet (option-or (list-tail toks) (list)))
        (openTok (option-or (list-head toksAfterLet) (lx/makeIndentToken (lx/tokLbracket) "[" 1 1)))
        (isRecord (or (= (.-rawText openTok) "{") (mt (.-kind openTok) ((tokLbrace) true) (_ false))))
        (patternToks (option-or (list-tail toksAfterLet) (list)))
        (patRes (extractPatternVars patternToks isRecord))
        (vars (.-vars patRes))
        (afterPat (.-rest patRes))]
    (let [(afterEq (mt (list-head afterPat)
                     ((some eqTok)
                      (if (or (= (.-rawText eqTok) "=")
                              (mt (.-kind eqTok) ((tokEqual) true) (_ false)))
                        (option-or (list-tail afterPat) (list))
                        afterPat))
                     ((none) (list))))]
      (let [(inSplit (splitTokensAtWord afterEq "in"))
            (hasIn (.-second (.-second inSplit)))]
        (if hasIn
          (let [(exprToks (.-first inSplit))
                (bodyToks (.-first (.-second inSplit)))
                (expr (parseLineTokensToSexpr exprToks))
                (body (if (list-empty? bodyToks) (list) (list (parseLineTokensToSexpr bodyToks))))]
            (LetLineInfo :isRecord isRecord :vars vars :expr expr :inlineBody body :hasInlineBody (not (list-empty? body))))
          (let [(colonSplit (splitTokensAtColon afterEq))
                (hasColon (.-second (.-second colonSplit)))]
            (if hasColon
              (let [(exprToks (.-first colonSplit))
                    (bodyToks (.-first (.-second colonSplit)))
                    (expr (parseLineTokensToSexpr exprToks))
                    (body (if (list-empty? bodyToks) (list) (list (parseLineTokensToSexpr bodyToks))))]
                (LetLineInfo :isRecord isRecord :vars vars :expr expr :inlineBody body :hasInlineBody (not (list-empty? body))))
              (let [(exprList (parseTokensToExprList afterEq))
                    (cnt (list-length exprList))]
                (cond
                  ((= cnt 0)
                   (LetLineInfo :isRecord isRecord :vars vars :expr (rd/makeAtom "") :inlineBody (list) :hasInlineBody false))
                  ((= cnt 1)
                   (LetLineInfo :isRecord isRecord :vars vars :expr (option-or (list-head exprList) (rd/makeAtom "")) :inlineBody (list) :hasInlineBody false))
                  ((and (> cnt 1) (rd/isList? (option-or (list-get exprList (- cnt 1)) (rd/makeAtom ""))))
                   (let [(lastItem (option-or (list-get exprList (- cnt 1)) (rd/makeAtom "")))
                         (initItems (option-or (list-slice exprList 0 (- cnt 1)) (list)))
                         (expr (if (= (list-length initItems) 1)
                                 (option-or (list-head initItems) (rd/makeAtom ""))
                                 (rd/makeList initItems)))]
                     (LetLineInfo :isRecord isRecord :vars vars :expr expr :inlineBody (list lastItem) :hasInlineBody true)))
                  (:else
                   (LetLineInfo :isRecord isRecord :vars vars :expr (rd/makeList exprList) :inlineBody (list) :hasInlineBody false)))))))))))

(df parseLineTokensToSexpr [(toks (List lx/IndentToken))] -> rd/SExpr
  :d "Converts a sequence of tokens on one line into a call form, single atom, or let destructuring form."
  (if (isLetDestructureLine? toks)
    (let [(info (parseLetLineInfo toks))]
      (desugarDestructuring (.-isRecord info) (.-vars info) (.-expr info) (.-inlineBody info)))
    (let [(resList (parseTokensToExprList toks))]
      (if (= (list-length resList) 1)
        (option-or (list-head resList) (rd/makeAtom ""))
        (rd/makeList resList)))))

(dfs BlockResult
  (:f rest (List lx/IndentToken) "Tokens remaining after block")
  (:f forms (List rd/SExpr) "Parsed block expressions"))

(df parseBlockLine [(remToks (List lx/IndentToken)) (forms (List rd/SExpr)) (curLevel Int64) (targetLevel Int64)]
  -> (Pair (List rd/SExpr) (Pair (List lx/IndentToken) (Pair Int64 Bool)))
  :d "Parses one non-indent line in an indented block."
  (let [(lineSplit (takeUntilLineEnd remToks))
        (lineToks (.-first lineSplit))
        (afterLine (.-second lineSplit))]
    (if (isLetDestructureLine? lineToks)
      (let [(info (parseLetLineInfo lineToks))]
        (if (.-hasInlineBody info)
          (let [(letSexpr (desugarDestructuring (.-isRecord info) (.-vars info) (.-expr info) (.-inlineBody info)))]
            (pair (cons letSexpr forms) (pair afterLine (pair curLevel false))))
          (mt (list-head afterLine)
            ((some nextT)
             (mt (.-kind nextT)
               ((tokIndent lvl)
                (let [(blockRes (parseIndentedBlock (option-or (list-tail afterLine) (list)) lvl))
                      (bodyForms (.-forms blockRes))
                      (remAfter (.-rest blockRes))
                      (letSexpr (desugarDestructuring (.-isRecord info) (.-vars info) (.-expr info) bodyForms))]
                  (pair (cons letSexpr forms) (pair remAfter (pair curLevel false)))))
               (_
                (let [(restBlock (parseIndentedBlock afterLine targetLevel))
                      (bodyForms (.-forms restBlock))
                      (remAfter (.-rest restBlock))
                      (letSexpr (desugarDestructuring (.-isRecord info) (.-vars info) (.-expr info) bodyForms))]
                  (pair (cons letSexpr forms) (pair remAfter (pair curLevel true)))))))
            ((none)
             (let [(letSexpr (desugarDestructuring (.-isRecord info) (.-vars info) (.-expr info) (list)))]
               (pair (cons letSexpr forms) (pair afterLine (pair curLevel true))))))))
      (let [(lineForm (parseLineTokensToSexpr lineToks))]
        (if (= (rd/sexprHead lineForm) "match")
          (mt (list-head afterLine)
            ((some nextT)
             (mt (.-kind nextT)
               ((tokIndent lvl)
                (let [(matchRes (parseMatchArms (option-or (list-tail afterLine) (list)) lvl))
                      (arms (.-arms matchRes))
                      (remAfterMatch (.-rest matchRes))
                      (targetSexpr (option-or (list-get (rd/sexprToList lineForm) 1) (rd/makeAtom "_")))
                      (fullMatchSexpr (rd/makeList (list (rd/makeAtom "match") targetSexpr (rd/makeList arms))))]
                  (pair (cons fullMatchSexpr forms) (pair remAfterMatch (pair curLevel false)))))
               (_
                (pair (cons lineForm forms) (pair afterLine (pair curLevel false))))))
            ((none)
             (pair (cons lineForm forms) (pair afterLine (pair curLevel false)))))
          (pair (cons lineForm forms) (pair afterLine (pair curLevel false))))))))

(df parseIndentedBlock [(toks (List lx/IndentToken)) (targetLevel Int64)] -> BlockResult
  :d "Parses all expressions inside an indented block at targetLevel."
  (let [(step (fold (fn [(acc (Pair (List rd/SExpr) (Pair (List lx/IndentToken) (Pair Int64 Bool)))) (_ String)]
                      -> (Pair (List rd/SExpr) (Pair (List lx/IndentToken) (Pair Int64 Bool)))
                      (let [(forms (.-first acc))
                            (remToks (.-first (.-second acc)))
                            (curLevel (.-first (.-second (.-second acc))))
                            (done (.-second (.-second (.-second acc))))]
                        (if done
                          acc
                          (mt (list-head remToks)
                            ((none) (pair forms (pair (list) (pair curLevel true))))
                            ((some t)
                             (mt (.-kind t)
                               ((tokDedent l)
                                (if (<= l targetLevel)
                                  (pair forms (pair (option-or (list-tail remToks) (list)) (pair l true)))
                                  (pair forms (pair (option-or (list-tail remToks) (list)) (pair l false)))))
                               ((tokNewline)
                                (pair forms (pair (option-or (list-tail remToks) (list)) (pair curLevel false))))
                               ((tokIndent l)
                                (pair forms (pair (option-or (list-tail remToks) (list)) (pair l false))))
                               ((tokEof)
                                (pair forms (pair remToks (pair curLevel true))))
                               (_
                                (parseBlockLine remToks forms curLevel targetLevel))))))))
                    (pair (list) (pair toks (pair targetLevel false)))
                    (string-chars (string-repeat " " (list-length toks)))))]
    (BlockResult :rest (.-first (.-second step))
                 :forms (list-reverse (.-first step)))))

(dfs MatchArm
  (:f pattern rd/SExpr "Pattern SExpr")
  (:f body rd/SExpr "Arm body SExpr"))

(df parseMatchArmLine [(lineToks (List lx/IndentToken))] -> MatchArm
  :d "Parses a single match arm Pattern -> Body or Pattern Body."
  (let [(split (fold (fn [(acc (Pair (List lx/IndentToken) (Pair (List lx/IndentToken) Bool))) (t lx/IndentToken)]
                       -> (Pair (List lx/IndentToken) (Pair (List lx/IndentToken) Bool))
                       (let [(pat (.-first acc))
                             (bod (.-first (.-second acc)))
                             (seenArrow (.-second (.-second acc)))]
                         (if seenArrow
                           (pair pat (pair (cons t bod) true))
                           (mt (.-kind t)
                             ((tokArrow) (pair pat (pair (list) true)))
                             (_          (pair (cons t pat) (pair (list) false)))))))
                     (pair (list) (pair (list) false))
                     lineToks))]
    (let [(patToks (list-reverse (.-first split)))
          (bodToks (list-reverse (.-first (.-second split))))
          (seenArrow (.-second (.-second split)))]
      (let [(patSexpr (parseLineTokensToSexpr patToks))
            (bodSexpr (if seenArrow
                        (parseLineTokensToSexpr bodToks)
                        (rd/makeAtom "")))]
        (MatchArm :pattern patSexpr :body bodSexpr)))))

(dfs MatchBlockResult
  (:f rest (List lx/IndentToken) "Tokens remaining after match")
  (:f arms (List rd/SExpr) "List of ((pat) body) arm SExprs"))

(df parseMatchArms [(toks (List lx/IndentToken)) (matchLevel Int64)] -> MatchBlockResult
  :d "Parses match arms block indented under match statement."
  (let [(step (fold (fn [(acc (Pair (List rd/SExpr) (Pair (List lx/IndentToken) Bool))) (_ String)]
                      -> (Pair (List rd/SExpr) (Pair (List lx/IndentToken) Bool))
                      (let [(arms (.-first acc))
                            (remToks (.-first (.-second acc)))
                            (done (.-second (.-second acc)))]
                        (if done
                          acc
                          (mt (list-head remToks)
                            ((none) (pair arms (pair (list) true)))
                            ((some t)
                             (mt (.-kind t)
                               ((tokDedent l)
                                (if (<= l matchLevel)
                                  (pair arms (pair (option-or (list-tail remToks) (list)) true))
                                  (pair arms (pair (option-or (list-tail remToks) (list)) false))))
                               ((tokNewline)
                                (pair arms (pair (option-or (list-tail remToks) (list)) false)))
                               ((tokIndent _)
                                (pair arms (pair (option-or (list-tail remToks) (list)) false)))
                               ((tokEof)
                                (pair arms (pair remToks true)))
                               (_
                                (let [(lineSplit (takeUntilLineEnd remToks))
                                      (lineToks (.-first lineSplit))
                                      (afterLine (.-second lineSplit))
                                      (arm (parseMatchArmLine lineToks))
                                      (armSexpr (rd/makeList (list (.-pattern arm) (.-body arm))))]
                                  (pair (cons armSexpr arms) (pair afterLine false))))))))))
                    (pair (list) (pair toks false))
                    (string-chars (string-repeat " " (list-length toks)))))]
    (MatchBlockResult :rest (.-first (.-second step))
                      :arms (list-reverse (.-first step)))))

(dfs FnSignature
  (:f name String "Function name")
  (:f params rd/SExpr "Parameters vector [(param Type) ...]")
  (:f retType rd/SExpr "Return type SExpr"))

(df parseFnParamsAndReturn [(toks (List lx/IndentToken))] -> FnSignature
  :d "Parses function name, parameters, and return type from header line tokens."
  (let [(fnName (mt (list-head toks) ((some t) (.-rawText t)) ((none) "anonymous")))
        (restToks (option-or (list-tail toks) (list)))]
    (let [(scanRes (fold (fn [(acc (Pair (List rd/SExpr) (Pair (Option String) (Pair Bool rd/SExpr)))) (t lx/IndentToken)]
                           -> (Pair (List rd/SExpr) (Pair (Option String) (Pair Bool rd/SExpr)))
                           (let [(pList (.-first acc))
                                 (pendingParam (.-first (.-second acc)))
                                 (afterArrow (.-first (.-second (.-second acc))))
                                 (retSexpr (.-second (.-second (.-second acc))))]
                             (if afterArrow
                               (pair pList (pair (none) (pair true (desugarDot (.-rawText t)))))
                               (mt (.-kind t)
                                 ((tokArrow)
                                  (pair pList (pair (none) (pair true retSexpr))))
                                 ((tokColon)
                                  acc)
                                 ((tokSymbol s)
                                  (mt pendingParam
                                    ((some pName)
                                     (let [(pairExpr (rd/makeList (list (rd/makeAtom pName) (desugarDot s))))]
                                       (pair (cons pairExpr pList) (pair (none) (pair false retSexpr)))))
                                    ((none)
                                     (pair pList (pair (some s) (pair false retSexpr))))))
                                 (_ acc)))))
                         (pair (list) (pair (none) (pair false (rd/makeAtom "Unit"))))
                         restToks))]
      (let [(paramsRev (.-first scanRes))
            (retSexpr (.-second (.-second (.-second scanRes))))]
        (FnSignature :name fnName
                     :params (rd/makeVect (list-reverse paramsRev))
                     :retType retSexpr)))))

(dfs TopFormResult
  (:f rest (List lx/IndentToken) "Tokens remaining")
  (:f form (Option rd/SExpr) "Parsed top form"))

(df parseTopForm [(toks (List lx/IndentToken))] -> TopFormResult
  :d "Parses single top form (fn, match, type, or expression) from tokens."
  (let [(cleanToks (skipNewlines toks))]
    (mt (list-head cleanToks)
      ((none) (TopFormResult :rest (list) :form (none)))
      ((some t)
       (mt (.-kind t)
         ((tokEof)
          (TopFormResult :rest (list) :form (none)))
         ((tokSymbol s)
          (cond
            ((= s "fn")
             (let [(lineSplit (takeUntilLineEnd (option-or (list-tail cleanToks) (list))))
                   (headerToks (.-first lineSplit))
                   (afterHeader (.-second lineSplit))
                   (sig (parseFnParamsAndReturn headerToks))]
               (mt (list-head afterHeader)
                 ((some indTok)
                  (mt (.-kind indTok)
                    ((tokIndent lvl)
                     (let [(blockRes (parseIndentedBlock (option-or (list-tail afterHeader) (list)) lvl))
                           (bodyForms (.-forms blockRes))
                           (remToks (.-rest blockRes))]
                       (let [(fnSexpr (rd/makeList (list-append
                                                     (list (rd/makeAtom "df")
                                                           (rd/makeAtom (.-name sig))
                                                           (.-params sig)
                                                           (rd/makeAtom "->")
                                                           (.-retType sig))
                                                     bodyForms)))]
                         (TopFormResult :rest remToks :form (some fnSexpr)))))
                    (_
                     (let [(fnSexpr (rd/makeList (list (rd/makeAtom "df")
                                                       (rd/makeAtom (.-name sig))
                                                       (.-params sig)
                                                       (rd/makeAtom "->")
                                                       (.-retType sig))))]
                       (TopFormResult :rest afterHeader :form (some fnSexpr))))))
                 ((none)
                  (let [(fnSexpr (rd/makeList (list (rd/makeAtom "df")
                                                    (rd/makeAtom (.-name sig))
                                                    (.-params sig)
                                                    (rd/makeAtom "->")
                                                    (.-retType sig))))]
                    (TopFormResult :rest (list) :form (some fnSexpr)))))))
            ((= s "match")
             (let [(lineSplit (takeUntilLineEnd (option-or (list-tail cleanToks) (list))))
                   (targetToks (.-first lineSplit))
                   (afterHeader (.-second lineSplit))
                   (targetSexpr (parseLineTokensToSexpr targetToks))]
               (mt (list-head afterHeader)
                 ((some indTok)
                  (mt (.-kind indTok)
                    ((tokIndent lvl)
                     (let [(matchRes (parseMatchArms (option-or (list-tail afterHeader) (list)) lvl))
                           (arms (.-arms matchRes))
                           (remToks (.-rest matchRes))]
                       (let [(matchSexpr (rd/makeList (list (rd/makeAtom "match") targetSexpr (rd/makeList arms))))]
                         (TopFormResult :rest remToks :form (some matchSexpr)))))
                    (_
                     (let [(matchSexpr (rd/makeList (list (rd/makeAtom "match") targetSexpr)))]
                       (TopFormResult :rest afterHeader :form (some matchSexpr))))))
                 ((none)
                  (let [(matchSexpr (rd/makeList (list (rd/makeAtom "match") targetSexpr)))]
                    (TopFormResult :rest (list) :form (some matchSexpr)))))))
            ((and (= s "let") (isLetDestructureLine? cleanToks))
             (let [(lineSplit (takeUntilLineEnd cleanToks))
                   (lineToks (.-first lineSplit))
                   (afterLine (.-second lineSplit))
                   (info (parseLetLineInfo lineToks))]
               (if (.-hasInlineBody info)
                 (let [(letSexpr (desugarDestructuring (.-isRecord info) (.-vars info) (.-expr info) (.-inlineBody info)))]
                   (TopFormResult :rest afterLine :form (some letSexpr)))
                 (mt (list-head afterLine)
                   ((some nextT)
                    (mt (.-kind nextT)
                      ((tokIndent lvl)
                       (let [(blockRes (parseIndentedBlock (option-or (list-tail afterLine) (list)) lvl))
                             (bodyForms (.-forms blockRes))
                             (remToks (.-rest blockRes))
                             (letSexpr (desugarDestructuring (.-isRecord info) (.-vars info) (.-expr info) bodyForms))]
                         (TopFormResult :rest remToks :form (some letSexpr))))
                      (_
                       (let [(letSexpr (desugarDestructuring (.-isRecord info) (.-vars info) (.-expr info) (list)))]
                         (TopFormResult :rest afterLine :form (some letSexpr))))))
                   ((none)
                    (let [(letSexpr (desugarDestructuring (.-isRecord info) (.-vars info) (.-expr info) (list)))]
                      (TopFormResult :rest afterLine :form (some letSexpr))))))))
            (:else
             (let [(lineSplit (takeUntilLineEnd cleanToks))
                   (lineToks (.-first lineSplit))
                   (afterLine (.-second lineSplit))
                   (lineSexpr (parseLineTokensToSexpr lineToks))]
               (TopFormResult :rest afterLine :form (some lineSexpr))))))
         (_
          (let [(lineSplit (takeUntilLineEnd cleanToks))
                (lineToks (.-first lineSplit))
                (afterLine (.-second lineSplit))
                (lineSexpr (parseLineTokensToSexpr lineToks))]
            (TopFormResult :rest afterLine :form (some lineSexpr)))))))))

(df parseIndentedForms [(src String)] -> (Result (List rd/SExpr) String)
  :d "Parses v0.4 indented source into a list of top-level SExpr forms."
  (let [(lexRes (lx/tokenizeIndented src))
        (toks (.-first lexRes))
        (diags (.-second lexRes))]
    (let [(formsRes (fold (fn [(acc (Pair (List rd/SExpr) (List lx/IndentToken))) (_ String)]
                            -> (Pair (List rd/SExpr) (List lx/IndentToken))
                            (let [(collected (.-first acc))
                                  (remToks (.-second acc))]
                              (if (list-empty? remToks)
                                acc
                                (let [(topRes (parseTopForm remToks))]
                                  (mt (.-form topRes)
                                    ((some f) (pair (cons f collected) (.-rest topRes)))
                                    ((none)   (pair collected (.-rest topRes))))))))
                          (pair (list) toks)
                          (string-chars (string-repeat " " (list-length toks)))))]
      (ok (list-reverse (.-first formsRes))))))

(df parseIndented [(src String)] -> (Result rd/SExpr String)
  :d "Parses single v0.4 indented form into canonical SExpr AST."
  (let [(formsRes (parseIndentedForms src))]
    (mt formsRes
      ((ok forms)
       (mt (list-head forms)
         ((some f) (ok f))
         ((none)   (err "No valid indented form parsed from source"))))
      ((err msg) (err msg)))))
