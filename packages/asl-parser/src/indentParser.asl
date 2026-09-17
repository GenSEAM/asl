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

(df escapeStringContent [(s String)] -> String
  :d "Escapes special characters in string content for SExpr atom literal."
  (let [(chars (string-chars s))]
    (fold (fn [(acc String) (ch String)] -> String
            (cond
              ((= ch "\n") (str acc "\\n"))
              ((= ch "\r") (str acc "\\r"))
              ((= ch "\t") (str acc "\\t"))
              ((= ch "\"") (str acc "\\\""))
              (:else (str acc ch))))
          ""
          chars)))

(df parseSingleTokenExpr [(tok lx/IndentToken)] -> rd/SExpr
  :d "Converts single token to SExpr with dot and string desugaring."
  (mt (.-kind tok)
    ((tokSymbol s)       (desugarDot s))
    ((tokKeyword k)      (rd/makeAtom k))
    ((tokString s)       (rd/makeAtom (str "\"" (escapeStringContent s) "\"")))
    ((tokInterp pts exs) (desugarInterpolation pts exs))
    ((tokInt n)          (rd/makeAtom (string-from-int64 n)))
    ((tokFloat f)        (rd/makeAtom (.-rawText tok)))
    ((tokQuestion)       (rd/makeAtom "?"))
    ((tokCoalesce)       (rd/makeAtom "??"))
    ((tokOptChain)       (rd/makeAtom "?."))
    ((tokPipe)           (rd/makeAtom "|>"))
    ((tokArrow)          (rd/makeAtom "->"))
    (_                   (rd/makeAtom (.-rawText tok)))))

(df skipNewlines [(toks (List lx/IndentToken))] -> (List lx/IndentToken)
  :d "Skips leading newline and dedent tokens."
  (mt (list-head toks)
    ((some t)
     (mt (.-kind t)
       ((tokNewline)  (skipNewlines (option-or (list-tail toks) (list))))
       ((tokDedent _) (skipNewlines (option-or (list-tail toks) (list))))
       (_             toks)))
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

(df stripOuterDelims [(toks (List lx/IndentToken))] -> (List lx/IndentToken)
  :d "Strips first and last token from a delimited token sequence."
  (let [(cnt (list-length toks))]
    (if (<= cnt 2)
      (list)
      (let [(afterHead (option-or (list-tail toks) (list)))]
        (option-or (list-slice afterHead 0 (- cnt 2)) (list))))))

(df parseParenGroup [(toks (List lx/IndentToken))] -> (Pair (List lx/IndentToken) (List rd/SExpr))
  :d "Collects tokens inside ( ... ) into a list of SExpr, preserving nested groups."
  (let [(inner (stripOuterDelims toks))]
    (pair (list) (parseTokensToExprList inner))))

(df parseBracketGroup [(toks (List lx/IndentToken))] -> (Pair (List lx/IndentToken) (List rd/SExpr))
  :d "Collects tokens inside [ ... ] into a list of SExpr, preserving nested groups."
  (let [(inner (stripOuterDelims toks))]
    (pair (list) (parseTokensToExprList inner))))

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

(df desugarLetBinding [(varName String) (expr rd/SExpr) (bodyForms (List rd/SExpr))] -> rd/SExpr
  :d "Lowers single-variable bracket-free let binding into canonical let SExpr."
  (let [(finalBody (if (list-empty? bodyForms)
                     (list (rd/makeAtom "<body>"))
                     bodyForms))
        (binding (rd/makeList (list (rd/makeAtom varName) expr)))
        (bVect (rd/makeVect (list binding)))]
    (rd/makeList (cons (rd/makeAtom "let") (cons bVect finalBody)))))

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

(df isPredicateName? [(name String)] -> Bool
  :d "Checks if identifier represents a predicate convention."
  (let [(prefixes (list "is-" "is_" "has-" "has_" "can-" "should-" "string-" "list-" "vector-" "map-"))
        (exacts (list "empty" "null" "nil" "zero" "true" "false"))
        (hasPrefix (fold (fn [(acc Bool) (p String)] -> Bool
                           (or acc (string-starts-with? name p)))
                         false
                         prefixes))
        (isExact (list-contains? exacts name))]
    (or hasPrefix
        (or isExact
            (or (string-contains? name "valid")
                (or (string-starts-with? name "is")
                    (or (string-ends-with? name "-p")
                        (string-ends-with? name "?"))))))))

(df preprocessTokens [(toks (List lx/IndentToken))] -> (List lx/IndentToken)
  :d "Merges adjacent tokens for symbols ending in ? or ! to prevent token fragmentation."
  (let [(step (fold (fn [(acc (Pair (List lx/IndentToken) (Pair (Option lx/IndentToken) (Pair (Option lx/IndentToken) Int64)))) (t lx/IndentToken)]
                      -> (Pair (List lx/IndentToken) (Pair (Option lx/IndentToken) (Pair (Option lx/IndentToken) Int64)))
                      (let [(emitted (.-first acc))
                            (pending (.-first (.-second acc)))
                            (prevEmitted (.-first (.-second (.-second acc))))
                            (inBrk (.-second (.-second (.-second acc))))]
                        (mt pending
                          ((none)
                           (mt (.-kind t)
                             ((tokLbracket)
                              (pair (cons t emitted) (pair (none) (pair (some t) (+ inBrk 1)))))
                             ((tokRbracket)
                              (let [(nxtB (if (> inBrk 0) (- inBrk 1) 0))]
                                (pair (cons t emitted) (pair (none) (pair (some t) nxtB)))))
                             ((tokSymbol _)
                              (pair emitted (pair (some t) (pair prevEmitted inBrk))))
                             (_
                              (pair (cons t emitted) (pair (none) (pair (some t) inBrk))))))
                          ((some p)
                           (let [(pRaw (.-rawText p))
                                 (isAdj (and (= (.-line p) (.-line t))
                                             (= (+ (.-col p) (string-length pRaw)) (.-col t))))]
                             (cond
                               ((and isAdj (= (.-rawText t) "!"))
                                (let [(mergedSym (str pRaw "!"))
                                      (mergedTok (lx/makeIndentToken (lx/tokSymbol mergedSym) mergedSym (.-line p) (.-col p)))]
                                  (pair emitted (pair (some mergedTok) (pair prevEmitted inBrk)))))
                               ((and isAdj (or (= (.-rawText t) "?")
                                               (mt (.-kind t) ((tokQuestion) true) (_ false))))
                                (let [(isAfterFn (mt prevEmitted
                                                   ((some pt) (or (= (.-rawText pt) "fn") (or (= (.-rawText pt) "defun") (= (.-rawText pt) "df"))))
                                                   ((none) false)))
                                      (isPred (isPredicateName? pRaw))
                                      (inB (> inBrk 0))]
                                  (if (or isAfterFn (or isPred inB))
                                    (let [(mergedSym (str pRaw "?"))
                                          (mergedTok (lx/makeIndentToken (lx/tokSymbol mergedSym) mergedSym (.-line p) (.-col p)))]
                                      (pair emitted (pair (some mergedTok) (pair prevEmitted inBrk))))
                                    (mt (.-kind t)
                                      ((tokLbracket)
                                       (pair (cons t (cons p emitted)) (pair (none) (pair (some t) (+ inBrk 1)))))
                                      ((tokRbracket)
                                       (let [(nxtB (if (> inBrk 0) (- inBrk 1) 0))]
                                         (pair (cons t (cons p emitted)) (pair (none) (pair (some t) nxtB)))))
                                      ((tokSymbol _)
                                       (pair (cons p emitted) (pair (some t) (pair (some p) inBrk))))
                                      (_
                                       (pair (cons t (cons p emitted)) (pair (none) (pair (some t) inBrk))))))))
                               (:else
                                (mt (.-kind t)
                                  ((tokLbracket)
                                   (pair (cons t (cons p emitted)) (pair (none) (pair (some t) (+ inBrk 1)))))
                                  ((tokRbracket)
                                   (let [(nxtB (if (> inBrk 0) (- inBrk 1) 0))]
                                     (pair (cons t (cons p emitted)) (pair (none) (pair (some t) nxtB)))))
                                  ((tokSymbol _)
                                   (pair (cons p emitted) (pair (some t) (pair (some p) inBrk))))
                                  (_
                                   (pair (cons t (cons p emitted)) (pair (none) (pair (some t) inBrk))))))))))))
                    (pair (list) (pair (none) (pair (none) 0)))
                    toks))]
    (let [(emitted (.-first step))
          (pending (.-first (.-second step)))]
      (mt pending
        ((some p) (list-reverse (cons p emitted)))
        ((none)   (list-reverse emitted))))))

(df parseTokensToExprList [(toks (List lx/IndentToken))] -> (List rd/SExpr)
  :d "Converts a sequence of tokens on one line into a list of SExpr items."
  (let [(items (fold (fn [(acc (Pair (List rd/SExpr) (Pair (List lx/IndentToken) (Pair Int64 (Pair Int64 (Pair Bool (Option lx/IndentToken))))))) (t lx/IndentToken)]
                       -> (Pair (List rd/SExpr) (Pair (List lx/IndentToken) (Pair Int64 (Pair Int64 (Pair Bool (Option lx/IndentToken))))))
                       (let [(collected (.-first acc))
                             (subToks (.-first (.-second acc)))
                             (parenDepth (.-first (.-second (.-second acc))))
                             (bracketDepth (.-first (.-second (.-second (.-second acc)))))
                             (isCall (.-first (.-second (.-second (.-second (.-second acc))))))
                             (lastTok (.-second (.-second (.-second (.-second (.-second acc))))))]
                         (mt (.-kind t)
                           ((tokLparen)
                            (let [(nxtP (+ parenDepth 1))
                                  (callFlag (if (= parenDepth 0)
                                              (mt lastTok
                                                ((some lt)
                                                 (and (= (.-line lt) (.-line t))
                                                      (= (+ (.-col lt) (string-length (.-rawText lt))) (.-col t))))
                                                ((none) false))
                                              isCall))]
                              (pair collected (pair (cons t subToks) (pair nxtP (pair bracketDepth (pair callFlag lastTok)))))))
                           ((tokRparen)
                            (let [(nxtP (- parenDepth 1))]
                              (if (and (<= nxtP 0) (= bracketDepth 0))
                                (let [(allParenToks (list-reverse (cons t subToks)))
                                      (parenItems (.-second (parseParenGroup allParenToks)))
                                      (subSexpr (rd/makeList parenItems))]
                                  (if isCall
                                    (mt (list-head collected)
                                      ((some headExpr)
                                       (if (and (rd/isAtom? headExpr)
                                                (not (string-starts-with? (rd/sexprHead headExpr) ":"))
                                                (not (string-starts-with? (rd/sexprHead headExpr) "\""))
                                                (!= (rd/sexprHead headExpr) "let")
                                                (!= (rd/sexprHead headExpr) "fn")
                                                (!= (rd/sexprHead headExpr) "if")
                                                (!= (rd/sexprHead headExpr) "match")
                                                (!= (rd/sexprHead headExpr) "try")
                                                (!= (rd/sexprHead headExpr) "|>")
                                                (!= (rd/sexprHead headExpr) "->")
                                                (!= (rd/sexprHead headExpr) "?")
                                                (!= (rd/sexprHead headExpr) "??")
                                                (!= (rd/sexprHead headExpr) "="))
                                         (let [(callSexpr (rd/makeList (cons headExpr parenItems)))
                                               (remCollected (option-or (list-tail collected) (list)))]
                                           (pair (cons callSexpr remCollected) (pair (list) (pair 0 (pair 0 (pair false (none)))))))
                                         (pair (cons subSexpr collected) (pair (list) (pair 0 (pair 0 (pair false (none))))))))
                                      ((none)
                                       (pair (cons subSexpr collected) (pair (list) (pair 0 (pair 0 (pair false (none))))))))
                                    (pair (cons subSexpr collected) (pair (list) (pair 0 (pair 0 (pair false (none))))))))
                                (pair collected (pair (cons t subToks) (pair nxtP (pair bracketDepth (pair isCall lastTok))))))))
                           ((tokLbracket)
                            (let [(nxtB (+ bracketDepth 1))]
                              (pair collected (pair (cons t subToks) (pair parenDepth (pair nxtB (pair isCall lastTok)))))))
                           ((tokRbracket)
                            (let [(nxtB (- bracketDepth 1))]
                              (if (and (<= nxtB 0) (= parenDepth 0))
                                (let [(allBrkToks (list-reverse (cons t subToks)))
                                      (brkItems (.-second (parseBracketGroup allBrkToks)))
                                      (subSexpr (rd/makeList (cons (rd/makeAtom "list") brkItems)))]
                                  (pair (cons subSexpr collected) (pair (list) (pair 0 (pair 0 (pair false (none)))))))
                                (pair collected (pair (cons t subToks) (pair parenDepth (pair nxtB (pair isCall lastTok))))))))
                           ((tokQuestion)
                            (if (or (> parenDepth 0) (> bracketDepth 0))
                              (pair collected (pair (cons t subToks) (pair parenDepth (pair bracketDepth (pair isCall lastTok)))))
                              (mt (list-head collected)
                                ((some prevExpr)
                                 (let [(rem (option-or (list-tail collected) (list)))
                                       (isAdjacent (mt lastTok
                                                     ((some lt)
                                                      (and (= (.-line lt) (.-line t))
                                                           (= (+ (.-col lt) (string-length (.-rawText lt))) (.-col t))))
                                                     ((none) false)))
                                       (isSym (rd/isAtom? prevExpr))
                                       (prevName (if isSym (rd/sexprHead prevExpr) ""))
                                       (shouldBeSymbol (and isAdjacent
                                                            isSym
                                                            (isPredicateName? prevName)))]
                                   (if shouldBeSymbol
                                     (let [(mergedAtom (rd/makeAtom (str prevName "?")))
                                           (newTok (lx/makeIndentToken (lx/tokSymbol (str prevName "?")) (str prevName "?") (.-line t) (.-col t)))]
                                       (pair (cons mergedAtom rem) (pair (list) (pair 0 (pair 0 (pair false (some newTok)))))))
                                     (let [(desugared (desugarTry prevExpr))]
                                       (pair (cons desugared rem) (pair (list) (pair 0 (pair 0 (pair false (none))))))))))
                                ((none)
                                 (pair (cons (parseSingleTokenExpr t) collected) (pair (list) (pair 0 (pair 0 (pair false (some t))))))))))
                           (_
                            (if (or (> parenDepth 0) (> bracketDepth 0))
                              (pair collected (pair (cons t subToks) (pair parenDepth (pair bracketDepth (pair isCall lastTok)))))
                              (pair (cons (parseSingleTokenExpr t) collected) (pair (list) (pair 0 (pair 0 (pair false (some t)))))))))))
                     (pair (list) (pair (list) (pair 0 (pair 0 (pair false (none))))))
                     toks))]
    (list-reverse (.-first items))))

(df isLetDestructureLine? [(toks (List lx/IndentToken))] -> Bool
  :d "Checks if tokens start a let line with assignment =."
  (mt (list-head toks)
    ((none) false)
    ((some t0)
     (if (= (.-rawText t0) "let")
       (fold (fn [(acc Bool) (t lx/IndentToken)] -> Bool
               (or acc (or (= (.-rawText t) "=") (mt (.-kind t) ((tokEqual) true) (_ false)))))
             false
             toks)
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
        (isBracket (or (= (.-rawText openTok) "[") (mt (.-kind openTok) ((tokLbracket) true) (_ false))))]
    (if (not (or isRecord isBracket))
      (let [(varName (.-rawText openTok))
            (vars (list varName))
            (afterVar (option-or (list-tail toksAfterLet) (list)))
            (afterEq (mt (list-head afterVar)
                       ((some eqTok)
                        (if (or (= (.-rawText eqTok) "=")
                                (mt (.-kind eqTok) ((tokEqual) true) (_ false)))
                          (option-or (list-tail afterVar) (list))
                          afterVar))
                       ((none) (list))))]
        (let [(inSplit (splitTokensAtWord afterEq "in"))
              (hasIn (.-second (.-second inSplit)))]
          (if hasIn
            (let [(exprToks (.-first inSplit))
                  (bodyToks (.-first (.-second inSplit)))
                  (expr (parseLineTokensToSexpr exprToks))
                  (body (if (list-empty? bodyToks) (list) (list (parseLineTokensToSexpr bodyToks))))]
              (LetLineInfo :isRecord false :vars vars :expr expr :inlineBody body :hasInlineBody (not (list-empty? body))))
            (let [(colonSplit (splitTokensAtColon afterEq))
                  (hasColon (.-second (.-second colonSplit)))]
              (if hasColon
                (let [(exprToks (.-first colonSplit))
                      (bodyToks (.-first (.-second colonSplit)))
                      (expr (parseLineTokensToSexpr exprToks))
                      (body (if (list-empty? bodyToks) (list) (list (parseLineTokensToSexpr bodyToks))))]
                  (LetLineInfo :isRecord false :vars vars :expr expr :inlineBody body :hasInlineBody (not (list-empty? body))))
                (let [(expr (parseLineTokensToSexpr afterEq))]
                  (LetLineInfo :isRecord false :vars vars :expr expr :inlineBody (list) :hasInlineBody false)))))))
      (let [(patternToks (option-or (list-tail toksAfterLet) (list)))
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
                       (LetLineInfo :isRecord isRecord :vars vars :expr (rd/makeList exprList) :inlineBody (list) :hasInlineBody false)))))))))))))

(df applyLetDesugar [(info LetLineInfo) (body (List rd/SExpr))] -> rd/SExpr
  :d "Applies single-variable let desugar or pattern destructuring desugar."
  (if (and (not (.-isRecord info)) (= (list-length (.-vars info)) 1))
    (desugarLetBinding (option-or (list-head (.-vars info)) "") (.-expr info) body)
    (desugarDestructuring (.-isRecord info) (.-vars info) (.-expr info) body)))

(df hasPipeSymbol? [(items (List rd/SExpr))] -> Bool
  :d "True if SExpr list contains top-level pipeline operator |>."
  (fold (fn [(acc Bool) (it rd/SExpr)] -> Bool
          (or acc (and (rd/isAtom? it) (= (rd/sexprHead it) "|>"))))
        false
        items))

(df desugarPipeList [(items (List rd/SExpr))] -> rd/SExpr
  :d "Desugars a |> b |> c sequence into canonical (|> a b c) SExpr."
  (let [(parts (fold (fn [(acc (Pair (List rd/SExpr) (List rd/SExpr))) (it rd/SExpr)]
                       -> (Pair (List rd/SExpr) (List rd/SExpr))
                       (let [(currentSegment (.-first acc))
                             (allSegments (.-second acc))]
                         (if (and (rd/isAtom? it) (= (rd/sexprHead it) "|>"))
                           (let [(segExpr (if (= (list-length currentSegment) 1)
                                            (option-or (list-head currentSegment) (rd/makeAtom ""))
                                            (rd/makeList (list-reverse currentSegment))))]
                             (pair (list) (cons segExpr allSegments)))
                           (pair (cons it currentSegment) allSegments))))
                     (pair (list) (list))
                     items))]
    (let [(lastSeg (.-first parts))
          (priorSegments (.-second parts))
          (lastExpr (if (= (list-length lastSeg) 1)
                      (option-or (list-head lastSeg) (rd/makeAtom ""))
                      (rd/makeList (list-reverse lastSeg))))
          (allExprs (list-reverse (cons lastExpr priorSegments)))]
      (rd/makeList (cons (rd/makeAtom "|>") allExprs)))))


(df desugarTryPrefix [(items (List rd/SExpr))] -> (List rd/SExpr)
  :d "Desugars prefix 'try expr' in expression list into early-return match form."
  (mt (list-head items)
    ((none) (list))
    ((some hd)
     (let [(tl (option-or (list-tail items) (list)))]
       (if (and (rd/isAtom? hd) (= (rd/sexprHead hd) "try"))
         (mt (list-head tl)
           ((none) (list hd))
           ((some nextExpr)
            (let [(rem (option-or (list-tail tl) (list)))
                  (desugared (desugarTry nextExpr))]
              (cons desugared (desugarTryPrefix rem)))))
         (cons hd (desugarTryPrefix tl)))))))

(df hasCoalesceSymbol? [(items (List rd/SExpr))] -> Bool
  :d "True if SExpr list contains null coalescing operator ??."
  (fold (fn [(acc Bool) (it rd/SExpr)] -> Bool
          (or acc (and (rd/isAtom? it) (= (rd/sexprHead it) "??"))))
        false
        items))

(df desugarCoalesce [(items (List rd/SExpr))] -> rd/SExpr
  :d "Desugars primary ?? fallback into canonical (?? primary fallback) SExpr."
  (let [(split (fold (fn [(acc (Pair (List rd/SExpr) (Pair (List rd/SExpr) Bool))) (it rd/SExpr)]
                       -> (Pair (List rd/SExpr) (Pair (List rd/SExpr) Bool))
                       (let [(left (.-first acc))
                             (right (.-first (.-second acc)))
                             (seen (.-second (.-second acc)))]
                         (if seen
                           (pair left (pair (cons it right) true))
                           (if (and (rd/isAtom? it) (= (rd/sexprHead it) "??"))
                             (pair left (pair (list) true))
                             (pair (cons it left) (pair (list) false))))))
                     (pair (list) (pair (list) false))
                     items))]
    (let [(leftItems (list-reverse (.-first split)))
          (rightItems (list-reverse (.-first (.-second split))))
          (leftExpr (if (= (list-length leftItems) 1)
                      (option-or (list-head leftItems) (rd/makeAtom ""))
                      (rd/makeList leftItems)))
          (rightExpr (if (hasCoalesceSymbol? rightItems)
                       (desugarCoalesce rightItems)
                       (if (= (list-length rightItems) 1)
                         (option-or (list-head rightItems) (rd/makeAtom ""))
                         (rd/makeList rightItems))))]
      (rd/makeList (list (rd/makeAtom "??") leftExpr rightExpr)))))

(df parseLineTokensToSexpr [(toks (List lx/IndentToken))] -> rd/SExpr
  :d "Converts a sequence of tokens on one line into a call form, single atom, let form, or pipeline form."
  (if (isLetDestructureLine? toks)
    (let [(info (parseLetLineInfo toks))]
      (applyLetDesugar info (.-inlineBody info)))
    (let [(rawList (parseTokensToExprList toks))
          (resList (desugarTryPrefix rawList))]
      (cond
        ((hasPipeSymbol? resList)
         (desugarPipeList resList))
        ((hasCoalesceSymbol? resList)
         (desugarCoalesce resList))
        ((= (list-length resList) 1)
         (option-or (list-head resList) (rd/makeAtom "")))
        (:else
         (rd/makeList resList))))))

(dfs BlockResult
  (:f rest (List lx/IndentToken) "Tokens remaining after block")
  (:f forms (List rd/SExpr) "Parsed block expressions"))

(df isIfLine? [(toks (List lx/IndentToken))] -> Bool
  :d "True if line starts with keyword if."
  (mt (list-head toks)
    ((some t) (= (.-rawText t) "if"))
    ((none) false)))

(df parseBlockLine [(remToks (List lx/IndentToken)) (forms (List rd/SExpr)) (curLevel Int64) (targetLevel Int64)]
  -> (Pair (List rd/SExpr) (Pair (List lx/IndentToken) (Pair Int64 Bool)))
  :d "Parses one non-indent line in an indented block."
  (let [(lineSplit (takeUntilLineEnd remToks))
        (lineToks (.-first lineSplit))
        (afterLine (.-second lineSplit))]
    (if (isLetDestructureLine? lineToks)
      (let [(info (parseLetLineInfo lineToks))]
        (if (.-hasInlineBody info)
          (let [(letSexpr (applyLetDesugar info (.-inlineBody info)))]
            (pair (cons letSexpr forms) (pair afterLine (pair curLevel false))))
          (mt (list-head afterLine)
            ((some nextT)
             (mt (.-kind nextT)
               ((tokIndent lvl)
                (let [(blockRes (parseIndentedBlock (option-or (list-tail afterLine) (list)) lvl))
                      (bodyForms (.-forms blockRes))
                      (remAfter (.-rest blockRes))
                      (letSexpr (applyLetDesugar info bodyForms))]
                  (pair (cons letSexpr forms) (pair remAfter (pair curLevel false)))))
               (_
                (let [(restBlock (parseIndentedBlock afterLine targetLevel))
                      (bodyForms (.-forms restBlock))
                      (remAfter (.-rest restBlock))
                      (letSexpr (applyLetDesugar info bodyForms))]
                  (pair (cons letSexpr forms) (pair remAfter (pair curLevel true)))))))
            ((none)
             (let [(letSexpr (applyLetDesugar info (list)))]
               (pair (cons letSexpr forms) (pair afterLine (pair curLevel true))))))))
      (if (isIfLine? lineToks)
        (let [(condToks (filter (fn [(t lx/IndentToken)] -> Bool
                                  (and (!= (.-rawText t) "if")
                                       (!= (.-rawText t) ":")))
                                lineToks))
              (condExpr (parseLineTokensToSexpr condToks))]
          (mt (list-head afterLine)
            ((some nextT)
             (mt (.-kind nextT)
               ((tokIndent lvl)
                (let [(thenBlockRes (parseIndentedBlock (option-or (list-tail afterLine) (list)) lvl))
                      (thenForms (.-forms thenBlockRes))
                      (afterThen (.-rest thenBlockRes))
                      (thenExpr (if (= (list-length thenForms) 1)
                                  (option-or (list-head thenForms) (rd/makeAtom ""))
                                  (rd/makeList (cons (rd/makeAtom "do") thenForms))))
                      (afterThenClean (skipNewlines afterThen))]
                  (mt (list-head afterThenClean)
                    ((some elseTok)
                     (if (= (.-rawText elseTok) "else")
                       (let [(elseSplit (takeUntilLineEnd afterThenClean))
                             (elseLineToks (.-first elseSplit))
                             (afterElseLine (.-second elseSplit))
                             (elseInline (filter (fn [(t lx/IndentToken)] -> Bool
                                                   (and (!= (.-rawText t) "else")
                                                        (!= (.-rawText t) ":")))
                                                 elseLineToks))]
                         (if (not (list-empty? elseInline))
                           (let [(elseExpr (parseLineTokensToSexpr elseInline))
                                 (ifSexpr (rd/makeList (list (rd/makeAtom "if") condExpr thenExpr elseExpr)))]
                             (pair (cons ifSexpr forms) (pair afterElseLine (pair curLevel false))))
                           (mt (list-head afterElseLine)
                             ((some nextElseT)
                              (mt (.-kind nextElseT)
                                ((tokIndent elseLvl)
                                 (let [(elseBlockRes (parseIndentedBlock (option-or (list-tail afterElseLine) (list)) elseLvl))
                                       (elseForms (.-forms elseBlockRes))
                                       (remAfterElse (.-rest elseBlockRes))
                                       (elseExpr (if (= (list-length elseForms) 1)
                                                   (option-or (list-head elseForms) (rd/makeAtom ""))
                                                   (rd/makeList (cons (rd/makeAtom "do") elseForms))))
                                       (ifSexpr (rd/makeList (list (rd/makeAtom "if") condExpr thenExpr elseExpr)))]
                                   (pair (cons ifSexpr forms) (pair remAfterElse (pair curLevel false)))))
                                (_
                                 (let [(ifSexpr (rd/makeList (list (rd/makeAtom "if") condExpr thenExpr (rd/makeAtom "nil"))))]
                                   (pair (cons ifSexpr forms) (pair afterElseLine (pair curLevel false)))))))
                             ((none)
                              (let [(ifSexpr (rd/makeList (list (rd/makeAtom "if") condExpr thenExpr (rd/makeAtom "nil"))))]
                                (pair (cons ifSexpr forms) (pair (list) (pair curLevel false))))))))
                       (let [(ifSexpr (rd/makeList (list (rd/makeAtom "if") condExpr thenExpr (rd/makeAtom "nil"))))]
                         (pair (cons ifSexpr forms) (pair afterThen (pair curLevel false))))))
                    ((none)
                     (let [(ifSexpr (rd/makeList (list (rd/makeAtom "if") condExpr thenExpr (rd/makeAtom "nil"))))]
                       (pair (cons ifSexpr forms) (pair (list) (pair curLevel false))))))))
               (_
                (let [(lineForm (parseLineTokensToSexpr lineToks))]
                  (pair (cons lineForm forms) (pair afterLine (pair curLevel false)))))))
            ((none)
             (let [(lineForm (parseLineTokensToSexpr lineToks))]
               (pair (cons lineForm forms) (pair afterLine (pair curLevel false)))))))
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
            (pair (cons lineForm forms) (pair afterLine (pair curLevel false)))))))))


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
                        (if (list-empty? bodToks)
                          (rd/makeAtom "")
                          (parseLineTokensToSexpr bodToks))
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
                                      (isBodyEmpty (or (and (rd/isAtom? (.-body arm)) (= (rd/sexprHead (.-body arm)) ""))
                                                       (and (rd/isList? (.-body arm)) (list-empty? (rd/sexprToList (.-body arm))))))]
                                  (if isBodyEmpty
                                    (mt (list-head afterLine)
                                      ((some nextT)
                                       (mt (.-kind nextT)
                                         ((tokIndent armLvl)
                                          (let [(armBlockRes (parseIndentedBlock (option-or (list-tail afterLine) (list)) armLvl))
                                                (armBodyForms (.-forms armBlockRes))
                                                (remAfterArm (.-rest armBlockRes))
                                                (armBody (if (= (list-length armBodyForms) 1)
                                                           (option-or (list-head armBodyForms) (rd/makeAtom ""))
                                                           (rd/makeList (cons (rd/makeAtom "do") armBodyForms))))
                                                 (armSexpr (rd/makeList (list (.-pattern arm) armBody)))]
                                             (pair (cons armSexpr arms) (pair remAfterArm false))))
                                          (_
                                           (let [(armSexpr (rd/makeList (list (.-pattern arm) (.-body arm))))]
                                             (pair (cons armSexpr arms) (pair afterLine false))))))
                                       ((none)
                                        (let [(armSexpr (rd/makeList (list (.-pattern arm) (.-body arm))))]
                                          (pair (cons armSexpr arms) (pair (list) false)))))
                                    (let [(armSexpr (rd/makeList (list (.-pattern arm) (.-body arm))))]
                                      (pair (cons armSexpr arms) (pair afterLine false))))))))))))
                    (pair (list) (pair toks false))
                    (string-chars (string-repeat " " (list-length toks)))))]
    (MatchBlockResult :rest (.-first (.-second step))
                      :arms (list-reverse (.-first step)))))

(dfs FnSignature
  (:f name String "Function name")
  (:f effect Bool "True if effect marker ! is present")
  (:f params rd/SExpr "Parameters vector [(param Type) ...]")
  (:f retType rd/SExpr "Return type SExpr")
  (:f docstring (Option String) "Optional inline docstring"))

(df parseParamsVector [(pToks (List lx/IndentToken))] -> rd/SExpr
  :d "Parses parameter tokens into canonical [(p1 T1) (p2 T2)] vector."
  (let [(cleanToks (fold (fn [(acc (List lx/IndentToken)) (t lx/IndentToken)] -> (List lx/IndentToken)
                           (let [(txt (.-rawText t))]
                             (if (or (= txt "[")
                                     (or (= txt "]")
                                         (or (= txt "(")
                                             (or (= txt ")")
                                                 (= txt ":")))))
                               acc
                               (cons t acc))))
                         (list)
                         pToks))]
    (let [(flatToks (list-reverse cleanToks))]
      (let [(pairs (fold (fn [(acc (Pair (List rd/SExpr) (Option String))) (t lx/IndentToken)]
                           -> (Pair (List rd/SExpr) (Option String))
                           (let [(collected (.-first acc))
                                 (pending (.-second acc))]
                             (mt pending
                               ((some pName)
                                (let [(pType (desugarDot (.-rawText t)))
                                      (pPair (rd/makeList (list (rd/makeAtom pName) pType)))]
                                  (pair (cons pPair collected) (none))))
                               ((none)
                                (pair collected (some (.-rawText t)))))))
                         (pair (list) (none))
                         flatToks))]
        (rd/makeVect (list-reverse (.-first pairs)))))))

(df parseFnParamsAndReturn [(toks (List lx/IndentToken))] -> FnSignature
  :d "Parses function name, optional effect marker, parameters, return type, and optional docstring."
  (let [(t0 (list-head toks))
        (fnName (mt t0 ((some t) (.-rawText t)) ((none) "anonymous")))
        (restToks (option-or (list-tail toks) (list)))
        (firstRest (list-head restToks))
        (hasEffect (mt firstRest
                     ((some fr) (= (.-rawText fr) "!"))
                     ((none) (string-ends-with? fnName "!"))))
        (paramAndRetToks (if (and hasEffect (is-some? firstRest) (= (.-rawText (option-or firstRest (lx/makeIndentToken (lx/tokSymbol "") "" 1 1))) "!"))
                           (option-or (list-tail restToks) (list))
                           restToks))
        (arrowSplit (splitTokensAtWord paramAndRetToks "->"))
        (pToks (.-first arrowSplit))
        (afterArrow (.-first (.-second arrowSplit)))
        (paramsVect (parseParamsVector pToks))
        (docSplit (splitTokensAtWord afterArrow ":d"))
        (hasDoc (.-second (.-second docSplit)))
        (retToks (if hasDoc (.-first docSplit) afterArrow))
        (docToks (if hasDoc (.-first (.-second docSplit)) (list)))
        (docstring (mt (list-head docToks)
                     ((some dt) (some (.-rawText dt)))
                     ((none) (none))))
        (retTypeSexpr (if (list-empty? retToks)
                        (rd/makeAtom "Unit")
                        (parseLineTokensToSexpr retToks)))]
    (FnSignature :name fnName
                 :effect hasEffect
                 :params paramsVect
                 :retType retTypeSexpr
                 :docstring docstring)))

(df hasLbrace? [(toks (List lx/IndentToken))] -> Bool
  :d "Checks if tokens contain a left brace '{'."
  (fold (fn [(acc Bool) (t lx/IndentToken)] -> Bool
          (or acc (mt (.-kind t) ((tokLbrace) true) (_ false))))
        false
        toks))

(df takeTokensInsideBraces [(toks (List lx/IndentToken))] -> (Pair (List lx/IndentToken) (List lx/IndentToken))
  :d "Extracts tokens between { and } including nested braces."
  (let [(step (fold (fn [(acc (Pair (List lx/IndentToken) (Pair (List lx/IndentToken) (Pair Int64 (Pair Bool Bool))))) (t lx/IndentToken)]
                      -> (Pair (List lx/IndentToken) (Pair (List lx/IndentToken) (Pair Int64 (Pair Bool Bool))))
                      (let [(inner (.-first acc))
                            (rem (.-first (.-second acc)))
                            (depth (.-first (.-second (.-second acc))))
                            (started (.-first (.-second (.-second (.-second acc)))))
                            (done (.-second (.-second (.-second (.-second acc)))))]
                        (if done
                          (pair inner (pair (cons t rem) (pair depth (pair started true))))
                          (mt (.-kind t)
                            ((tokLbrace)
                             (if (not started)
                               (pair inner (pair rem (pair 1 (pair true false))))
                               (pair (cons t inner) (pair rem (pair (+ depth 1) (pair true false))))))
                            ((tokRbrace)
                             (if (<= depth 1)
                               (pair inner (pair rem (pair 0 (pair true true))))
                               (pair (cons t inner) (pair rem (pair (- depth 1) (pair true false))))))
                            (_
                             (if started
                               (pair (cons t inner) (pair rem (pair depth (pair true false))))
                               (pair inner (pair rem (pair depth (pair false false))))))))))
                    (pair (list) (pair (list) (pair 0 (pair false false))))
                    toks))]
    (pair (list-reverse (.-first step)) (list-reverse (.-first (.-second step))))))

(df collectBlockTokens [(toks (List lx/IndentToken)) (targetLevel Int64)] -> (Pair (List lx/IndentToken) (List lx/IndentToken))
  :d "Collects tokens inside an indented block until dedent at or below targetLevel."
  (let [(step (fold (fn [(acc (Pair (List lx/IndentToken) (Pair (List lx/IndentToken) Bool))) (t lx/IndentToken)]
                      -> (Pair (List lx/IndentToken) (Pair (List lx/IndentToken) Bool))
                      (let [(inner (.-first acc))
                            (rem (.-first (.-second acc)))
                            (done (.-second (.-second acc)))]
                        (if done
                          (pair inner (pair (cons t rem) true))
                          (mt (.-kind t)
                            ((tokDedent l)
                             (if (<= l targetLevel)
                               (pair inner (pair (cons t rem) true))
                               (pair (cons t inner) (pair rem false))))
                            ((tokEof)
                             (pair inner (pair rem true)))
                            (_
                             (pair (cons t inner) (pair rem false)))))))
                    (pair (list) (pair (list) false))
                    toks))]
    (pair (list-reverse (.-first step)) (list-reverse (.-first (.-second step))))))

(df splitTokensByLines [(toks (List lx/IndentToken))] -> (List (List lx/IndentToken))
  :d "Groups tokens into lines separated by tokNewline."
  (let [(step (fold (fn [(acc (Pair (List (List lx/IndentToken)) (List lx/IndentToken))) (t lx/IndentToken)]
                      -> (Pair (List (List lx/IndentToken)) (List lx/IndentToken))
                      (let [(lines (.-first acc))
                            (curLine (.-second acc))]
                        (mt (.-kind t)
                          ((tokNewline)
                           (if (list-empty? curLine)
                             acc
                             (pair (cons (list-reverse curLine) lines) (list))))
                          ((tokIndent _) acc)
                          ((tokDedent _) acc)
                          ((tokEof)
                           (if (list-empty? curLine)
                             acc
                             (pair (cons (list-reverse curLine) lines) (list))))
                          (_
                           (pair lines (cons t curLine))))))
                    (pair (list) (list))
                    toks))]
    (let [(lines (.-first step))
          (curLine (.-second step))]
      (if (list-empty? curLine)
        (list-reverse lines)
        (list-reverse (cons (list-reverse curLine) lines))))))

(df parseSchemaFieldTokens [(toks (List lx/IndentToken))] -> (List rd/SExpr)
  :d "Parses field declarations from tokens into canonical (:field name type doc) forms."
  (let [(step (fold (fn [(acc (Pair (List rd/SExpr) (Option String))) (t lx/IndentToken)]
                      -> (Pair (List rd/SExpr) (Option String))
                      (let [(fields (.-first acc))
                            (pendingName (.-second acc))]
                        (mt (.-kind t)
                          ((tokSymbol s)
                           (mt pendingName
                             ((none)
                              (pair fields (some s)))
                             ((some fName)
                              (let [(fieldForm (rd/makeList (list (rd/makeAtom ":field")
                                                                  (rd/makeAtom fName)
                                                                  (desugarDot s)
                                                                  (rd/makeAtom "\"\""))))]
                                (pair (cons fieldForm fields) (none))))))
                          ((tokString s)
                           (mt (list-head fields)
                             ((some lastF)
                              (let [(fItems (rd/sexprToList lastF))]
                                (if (>= (list-length fItems) 3)
                                  (let [(fName (option-or (list-get fItems 1) (rd/makeAtom "")))
                                        (fType (option-or (list-get fItems 2) (rd/makeAtom "")))
                                        (updated (rd/makeList (list (rd/makeAtom ":field")
                                                                    fName
                                                                    fType
                                                                    (rd/makeAtom (str "\"" s "\"")))))]
                                    (pair (cons updated (option-or (list-tail fields) (list))) (none)))
                                  acc)))
                             ((none) acc)))
                          (_ acc))))
                    (pair (list) (none))
                    toks))]
    (list-reverse (.-first step))))

(df parseSchemaTopForm [(cleanToks (List lx/IndentToken))] -> TopFormResult
  :d "Parses a schema declaration with braces or indented fields into canonical defschema SExpr."
  (let [(afterKw (option-or (list-tail cleanToks) (list)))
        (nameTok (list-head afterKw))]
    (mt nameTok
      ((none) (TopFormResult :rest (list) :form (none)))
      ((some nt)
       (let [(rawName (.-rawText nt))
             (schemaName (if (string-ends-with? rawName ":")
                           (option-or (string-slice rawName 0 (- (string-length rawName) 1)) rawName)
                           rawName))
             (afterName (option-or (list-tail afterKw) (list)))]
         (if (hasLbrace? afterName)
           (let [(braceRes (takeTokensInsideBraces afterName))
                 (innerToks (.-first braceRes))
                 (remToks (.-second braceRes))
                 (fields (parseSchemaFieldTokens innerToks))
                 (schemaSexpr (rd/makeList (list-append (list (rd/makeAtom "defschema") (rd/makeAtom schemaName)) fields)))]
             (TopFormResult :rest remToks :form (some schemaSexpr)))
           (let [(lineSplit (takeUntilLineEnd afterName))
                 (afterLine (.-second lineSplit))]
             (mt (list-head afterLine)
               ((some indTok)
                (mt (.-kind indTok)
                  ((tokIndent lvl)
                   (let [(blockRes (collectBlockTokens (option-or (list-tail afterLine) (list)) lvl))
                         (blockToks (.-first blockRes))
                         (remToks (.-second blockRes))
                         (fields (parseSchemaFieldTokens blockToks))
                         (schemaSexpr (rd/makeList (list-append (list (rd/makeAtom "defschema") (rd/makeAtom schemaName)) fields)))]
                     (TopFormResult :rest remToks :form (some schemaSexpr))))
                  (_
                   (let [(schemaSexpr (rd/makeList (list (rd/makeAtom "defschema") (rd/makeAtom schemaName))))]
                     (TopFormResult :rest afterLine :form (some schemaSexpr))))))
               ((none)
                (let [(schemaSexpr (rd/makeList (list (rd/makeAtom "defschema") (rd/makeAtom schemaName))))]
                  (TopFormResult :rest (list) :form (some schemaSexpr))))))))))))

(df parseEnumTopForm [(cleanToks (List lx/IndentToken))] -> TopFormResult
  :d "Parses an enum declaration with braces or indented variants into canonical defenum SExpr."
  (let [(afterKw (option-or (list-tail cleanToks) (list)))
        (nameTok (list-head afterKw))]
    (mt nameTok
      ((none) (TopFormResult :rest (list) :form (none)))
      ((some nt)
       (let [(rawName (.-rawText nt))
             (enumName (if (string-ends-with? rawName ":")
                         (option-or (string-slice rawName 0 (- (string-length rawName) 1)) rawName)
                         rawName))
             (afterName (option-or (list-tail afterKw) (list)))]
         (if (hasLbrace? afterName)
           (let [(braceRes (takeTokensInsideBraces afterName))
                 (innerToks (.-first braceRes))
                 (remToks (.-second braceRes))
                 (symbols (filter (fn [(t lx/IndentToken)] -> Bool
                                    (mt (.-kind t) ((tokSymbol _) true) (_ false)))
                                  innerToks))
                 (cases (map (fn [(t lx/IndentToken)] -> rd/SExpr
                               (rd/makeList (list (rd/makeAtom ":case")
                                                  (rd/makeAtom (.-rawText t))
                                                  (rd/makeVect (list))
                                                  (rd/makeAtom "\"\""))))
                             symbols))
                 (enumSexpr (rd/makeList (list-append (list (rd/makeAtom "defenum") (rd/makeAtom enumName)) cases)))]
             (TopFormResult :rest remToks :form (some enumSexpr)))
           (let [(lineSplit (takeUntilLineEnd afterName))
                 (afterLine (.-second lineSplit))]
             (mt (list-head afterLine)
               ((some indTok)
                (mt (.-kind indTok)
                  ((tokIndent lvl)
                   (let [(blockRes (collectBlockTokens (option-or (list-tail afterLine) (list)) lvl))
                         (blockToks (.-first blockRes))
                         (remToks (.-second blockRes))
                         (lines (splitTokensByLines blockToks))
                         (cases (map (fn [(lt (List lx/IndentToken))] -> rd/SExpr
                                       (let [(vNameTok (list-head lt))]
                                         (mt vNameTok
                                           ((some vt)
                                            (let [(vName (.-rawText vt))
                                                  (restLt (option-or (list-tail lt) (list)))]
                                              (if (list-empty? restLt)
                                                (rd/makeList (list (rd/makeAtom ":case")
                                                                   (rd/makeAtom vName)
                                                                   (rd/makeVect (list))
                                                                   (rd/makeAtom "\"\"")))
                                                (let [(fForms (parseSchemaFieldTokens restLt))
                                                      (params (map (fn [(f rd/SExpr)] -> rd/SExpr
                                                                     (let [(fItems (rd/sexprToList f))]
                                                                       (rd/makeList (list (option-or (list-get fItems 1) (rd/makeAtom ""))
                                                                                          (option-or (list-get fItems 2) (rd/makeAtom ""))))))
                                                                   fForms))]
                                                  (rd/makeList (list (rd/makeAtom ":case")
                                                                     (rd/makeAtom vName)
                                                                     (rd/makeVect params)
                                                                     (rd/makeAtom "\"\"")))))))
                                           ((none)
                                            (rd/makeList (list (rd/makeAtom ":case")
                                                               (rd/makeAtom "Unknown")
                                                               (rd/makeVect (list))
                                                               (rd/makeAtom "\"\"")))))))
                                     lines))
                         (enumSexpr (rd/makeList (list-append (list (rd/makeAtom "defenum") (rd/makeAtom enumName)) cases)))]
                     (TopFormResult :rest remToks :form (some enumSexpr))))
                  (_
                   (let [(enumSexpr (rd/makeList (list (rd/makeAtom "defenum") (rd/makeAtom enumName))))]
                     (TopFormResult :rest afterLine :form (some enumSexpr))))))
               ((none)
                (let [(enumSexpr (rd/makeList (list (rd/makeAtom "defenum") (rd/makeAtom enumName))))]
                  (TopFormResult :rest (list) :form (some enumSexpr))))))))))))

(dfs TopFormResult
  (:f rest (List lx/IndentToken) "Tokens remaining")
  (:f form (Option rd/SExpr) "Parsed top form"))

(df parseIfTopForm [(toks (List lx/IndentToken))] -> TopFormResult
  :d "Parses top-level if/else form with indented blocks."
  (let [(lineSplit (takeUntilLineEnd toks))
        (lineToks (.-first lineSplit))
        (afterLine (.-second lineSplit))
        (condToks (filter (fn [(t lx/IndentToken)] -> Bool
                            (and (!= (.-rawText t) "if")
                                 (!= (.-rawText t) ":")))
                          lineToks))
        (condExpr (parseLineTokensToSexpr condToks))]
    (mt (list-head afterLine)
      ((some indTok)
       (mt (.-kind indTok)
         ((tokIndent lvl)
          (let [(thenBlockRes (parseIndentedBlock (option-or (list-tail afterLine) (list)) lvl))
                (thenForms (.-forms thenBlockRes))
                (afterThen (.-rest thenBlockRes))
                (thenExpr (if (= (list-length thenForms) 1)
                            (option-or (list-head thenForms) (rd/makeAtom ""))
                            (rd/makeList (cons (rd/makeAtom "do") thenForms))))
                (cleanAfterThen (skipNewlines afterThen))]
            (mt (list-head cleanAfterThen)
              ((some elseTok)
               (if (= (.-rawText elseTok) "else")
                 (let [(elseSplit (takeUntilLineEnd cleanAfterThen))
                       (elseLineToks (.-first elseSplit))
                       (afterElseLine (.-second elseSplit))
                       (elseInline (filter (fn [(t lx/IndentToken)] -> Bool
                                             (and (!= (.-rawText t) "else")
                                                  (!= (.-rawText t) ":")))
                                           elseLineToks))]
                   (if (not (list-empty? elseInline))
                     (let [(elseExpr (parseLineTokensToSexpr elseInline))
                           (ifSexpr (rd/makeList (list (rd/makeAtom "if") condExpr thenExpr elseExpr)))]
                       (TopFormResult :rest afterElseLine :form (some ifSexpr)))
                     (mt (list-head afterElseLine)
                       ((some nextElseT)
                        (mt (.-kind nextElseT)
                          ((tokIndent elseLvl)
                           (let [(elseBlockRes (parseIndentedBlock (option-or (list-tail afterElseLine) (list)) elseLvl))
                                 (elseForms (.-forms elseBlockRes))
                                 (remAfterElse (.-rest elseBlockRes))
                                 (elseExpr (if (= (list-length elseForms) 1)
                                             (option-or (list-head elseForms) (rd/makeAtom ""))
                                             (rd/makeList (cons (rd/makeAtom "do") elseForms))))
                                 (ifSexpr (rd/makeList (list (rd/makeAtom "if") condExpr thenExpr elseExpr)))]
                             (TopFormResult :rest remAfterElse :form (some ifSexpr))))
                          (_
                           (let [(ifSexpr (rd/makeList (list (rd/makeAtom "if") condExpr thenExpr (rd/makeAtom "nil"))))]
                             (TopFormResult :rest afterElseLine :form (some ifSexpr))))))
                       ((none)
                        (let [(ifSexpr (rd/makeList (list (rd/makeAtom "if") condExpr thenExpr (rd/makeAtom "nil"))))]
                          (TopFormResult :rest (list) :form (some ifSexpr)))))))
                 (let [(ifSexpr (rd/makeList (list (rd/makeAtom "if") condExpr thenExpr (rd/makeAtom "nil"))))]
                   (TopFormResult :rest afterThen :form (some ifSexpr)))))
              ((none)
               (let [(ifSexpr (rd/makeList (list (rd/makeAtom "if") condExpr thenExpr (rd/makeAtom "nil"))))]
                 (TopFormResult :rest (list) :form (some ifSexpr)))))))
         (_
          (let [(ifSexpr (rd/makeList (list (rd/makeAtom "if") condExpr (rd/makeAtom "nil") (rd/makeAtom "nil"))))]
            (TopFormResult :rest afterLine :form (some ifSexpr))))))
      ((none)
       (let [(ifSexpr (rd/makeList (list (rd/makeAtom "if") condExpr (rd/makeAtom "nil") (rd/makeAtom "nil"))))]
         (TopFormResult :rest (list) :form (some ifSexpr)))))))

(df extractBodyDoc [(headerDoc (Option String)) (bodyForms (List rd/SExpr))] -> (Pair (List rd/SExpr) (List rd/SExpr))
  :d "Normalizes header docstring or first body form docstring into (:d doc) SExpr atoms."
  (mt headerDoc
    ((some d)
     (let [(dAtom (if (string-starts-with? d "\"") (rd/makeAtom d) (rd/makeAtom (str "\"" d "\""))))]
       (pair (list (rd/makeAtom ":d") dAtom) bodyForms)))
    ((none)
     (mt (list-head bodyForms)
       ((some firstForm)
        (mt firstForm
          ((sexprList fItems)
           (mt (list-head fItems)
             ((some hAtom)
              (let [(hName (rd/sexprHead hAtom))]
                (if (or (= hName ":d") (= hName ":doc"))
                  (let [(docVal (option-or (list-get fItems 1) (rd/makeAtom "\"\"")))
                        (remForms (option-or (list-tail bodyForms) (list)))]
                    (pair (list (rd/makeAtom ":d") docVal) remForms))
                  (pair (list) bodyForms))))
             ((none) (pair (list) bodyForms))))
          ((sexprAtom aName)
           (if (or (= aName ":d") (= aName ":doc"))
             (let [(tailForms (option-or (list-tail bodyForms) (list)))
                   (docVal (option-or (list-head tailForms) (rd/makeAtom "\"\"")))
                   (remForms (option-or (list-tail tailForms) (list)))]
               (pair (list (rd/makeAtom ":d") docVal) remForms))
             (pair (list) bodyForms)))
          (_ (pair (list) bodyForms))))
       ((none) (pair (list) (list)))))))

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
                           (rawBodyForms (.-forms blockRes))
                           (remToks (.-rest blockRes))
                           (docRes (extractBodyDoc (.-docstring sig) rawBodyForms))
                           (finalDocList (.-first docRes))
                           (finalBodyForms (.-second docRes))
                           (effList (if (.-effect sig) (list (rd/makeAtom "!")) (list)))
                           (fnParts (list-append (list-append (list (rd/makeAtom "df") (rd/makeAtom (.-name sig))) effList)
                                                 (list-append (list (.-params sig) (rd/makeAtom "->") (.-retType sig))
                                                              (list-append finalDocList finalBodyForms))))
                           (fnSexpr (rd/makeList fnParts))]
                       (TopFormResult :rest remToks :form (some fnSexpr))))
                    (_
                     (let [(effList (if (.-effect sig) (list (rd/makeAtom "!")) (list)))
                           (docList (mt (.-docstring sig)
                                      ((some d) (list (rd/makeAtom ":d") (rd/makeAtom (if (string-starts-with? d "\"") d (str "\"" d "\"")))))
                                      ((none) (list))))
                           (fnParts (list-append (list-append (list (rd/makeAtom "df") (rd/makeAtom (.-name sig))) effList)
                                                 (list-append (list (.-params sig) (rd/makeAtom "->") (.-retType sig))
                                                              docList)))
                           (fnSexpr (rd/makeList fnParts))]
                       (TopFormResult :rest afterHeader :form (some fnSexpr))))))
                 ((none)
                  (let [(effList (if (.-effect sig) (list (rd/makeAtom "!")) (list)))
                        (docList (mt (.-docstring sig)
                                   ((some d) (list (rd/makeAtom ":d") (rd/makeAtom (if (string-starts-with? d "\"") d (str "\"" d "\"")))))
                                   ((none) (list))))
                        (fnParts (list-append (list-append (list (rd/makeAtom "df") (rd/makeAtom (.-name sig))) effList)
                                              (list-append (list (.-params sig) (rd/makeAtom "->") (.-retType sig))
                                                           docList)))
                        (fnSexpr (rd/makeList fnParts))]
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
            ((or (= s "schema") (= s "defschema"))
             (parseSchemaTopForm cleanToks))
            ((or (= s "enum") (= s "defenum"))
             (parseEnumTopForm cleanToks))
            ((= s "if")
             (parseIfTopForm cleanToks))
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
        (rawToks (.-first lexRes))
        (diags (.-second lexRes))
        (hasLexErr (fold (fn [(acc Bool) (d lx/LexerDiagnostic)] -> Bool
                           (or acc (string-starts-with? (.-code d) "E")))
                         false
                         diags))]
    (if hasLexErr
      (err "Lexical error during indentation tokenization")
      (let [(toks (preprocessTokens rawToks))
            (formsRes (fold (fn [(acc (Pair (List rd/SExpr) (List lx/IndentToken))) (_ String)]
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
        (ok (list-reverse (.-first formsRes)))))))

(df parseIndented [(src String)] -> (Result rd/SExpr String)
  :d "Parses single v0.4 indented form into canonical SExpr AST."
  (let [(formsRes (parseIndentedForms src))]
    (mt formsRes
      ((ok forms)
       (mt (list-head forms)
         ((some f) (ok f))
         ((none)   (err "No valid indented form parsed from source"))))
      ((err msg) (err msg)))))


