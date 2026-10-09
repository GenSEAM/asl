(module asl-parser/indentParser :x [IndentForm IndentError parseIndented parseIndentedForms parseIndentedFormsPos desugarDot desugarInterpolation desugarTry desugarDestructuring stripInferredUnit] :i [(indentLexer :a ilx) (reader :a rd) (fnHeader :a fh)])

fn desugarDot name: String -> rd/SExpr
  (if (or (stringStartsWith? name ".") (not (stringContains? name "."))) (rd/makeAtom name) (let [(parts (stringSplit name "."))] (if (< (listLength parts) 2) (rd/makeAtom name) (let [(headPart (optionOr (listHead parts) "")) (tailParts (optionOr (listTail parts) (list)))] (fold (fn [(acc rd/SExpr) (field String)] -> rd/SExpr (rd/makeList (list (rd/makeAtom (str ".-" field)) acc))) (rd/makeAtom headPart) tailParts)))))

fn desugarInterpolation parts: (List String) exprs: (List String) -> rd/SExpr
  (let [(pairs (fold (fn [(acc (Pair (List rd/SExpr) (List String))) (part String)] -> (Pair (List rd/SExpr) (List String)) (let [(accum (pairFirst acc)) (remExprs (pairSecond acc))] (let [(partSexpr (if (= part "") (list) (list (rd/makeAtom (str "\"" (escapeStringContent part) "\"")))))] (mt (listHead remExprs) ((some ex) (let [(exSexpr (desugarDot ex)) (nxtRem (optionOr (listTail remExprs) (list)))] (pair (listAppend accum (listAppend partSexpr (list exSexpr))) nxtRem))) ((none) (pair (listAppend accum partSexpr) remExprs)))))) (pair (list) exprs) parts))] (rd/makeList (cons (rd/makeAtom "str") (pairFirst pairs))))

fn desugarTry expr: rd/SExpr -> rd/SExpr
  (let [(okArm (rd/makeList (list (rd/makeList (list (rd/makeAtom "ok") (rd/makeAtom "__v"))) (rd/makeAtom "__v")))) (errArm (rd/makeList (list (rd/makeList (list (rd/makeAtom "err") (rd/makeAtom "__e"))) (rd/makeList (list (rd/makeAtom "err") (rd/makeAtom "__e"))))))] (rd/makeList (list (rd/makeAtom "mt") expr okArm errArm)))

(schema ParseExprResult (:f rest (List ilx/IndentToken)) (:f expr rd/SExpr))

fn controlBytes -> String
  "\x00\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0a\x0b\x0c\x0d\x0e\x0f\x10\x11\x12\x13\x14\x15\x16\x17\x18\x19\x1a\x1b\x1c\x1d\x1e\x1f\x7f"

fn controlEscape n: Int64 -> String
  (let [(code (if (= n 32) 127 n)) (hex "0123456789abcdef")] (str "\\x" (optionOr (stringSlice hex (/ code 16) (+ (/ code 16) 1)) "") (optionOr (stringSlice hex (mod code 16) (+ (mod code 16) 1)) "")))

fn escapeStringContent s: String -> String
  (let [(chars (stringChars s))] (fold (fn [(acc String) (ch String)] -> String (cond ((= ch "\n") (str acc "\\n")) ((= ch "\r") (str acc "\\r")) ((= ch "\t") (str acc "\\t")) ((= ch "\"") (str acc "\\\"")) ((= ch "\\") (str acc "\\\\")) (else (mt (stringIndexOf (controlBytes) ch) ((some n) (str acc (controlEscape n))) ((none) (str acc ch)))))) "" chars))

fn parseSingleTokenExpr tok: ilx/IndentToken -> rd/SExpr
  (mt tok.kind ((tokSymbol s) (desugarDot s)) ((tokKeyword k) (rd/makeAtom k)) ((tokString s) (rd/makeAtom (str "\"" (escapeStringContent s) "\""))) ((tokInt n) (rd/makeAtom (stringFromInt64 n))) ((tokFloat f) (rd/makeAtom tok.rawText)) ((tokQuestion) (rd/makeAtom "?")) ((tokCoalesce) (rd/makeAtom "??")) ((tokOptChain) (rd/makeAtom "?.")) ((tokPipe) (rd/makeAtom "|>")) ((tokArrow) (rd/makeAtom "->")) (_ (rd/makeAtom tok.rawText)))

fn skipNewlines toks: (List ilx/IndentToken) -> (List ilx/IndentToken)
  (mt (listHead toks) ((some t) (mt t.kind ((tokNewline) (skipNewlines (optionOr (listTail toks) (list)))) ((tokDedent _) (skipNewlines (optionOr (listTail toks) (list)))) (_ toks))) ((none) (list)))

fn takeUntilLineEnd toks: (List ilx/IndentToken) -> (Pair (List ilx/IndentToken) (List ilx/IndentToken))
  (let [(step (fold (fn [(acc (Pair (List ilx/IndentToken) (Pair (List ilx/IndentToken) Bool))) (t ilx/IndentToken)] -> (Pair (List ilx/IndentToken) (Pair (List ilx/IndentToken) Bool)) (let [(cur (pairFirst acc)) (rem (pairFirst (pairSecond acc))) (stopped (pairSecond (pairSecond acc)))] (if stopped (pair cur (pair (cons t rem) true)) (mt t.kind ((tokNewline) (pair cur (pair rem true))) ((tokIndent _) (pair cur (pair (cons t rem) true))) ((tokDedent _) (pair cur (pair (cons t rem) true))) ((tokEof) (pair cur (pair (cons t rem) true))) (_ (pair (cons t cur) (pair rem false))))))) (pair (list) (pair (list) false)) toks))] (pair (listReverse (pairFirst step)) (listReverse (pairFirst (pairSecond step)))))

fn stripOuterDelims toks: (List ilx/IndentToken) -> (List ilx/IndentToken)
  (let [(cnt (listLength toks))] (if (<= cnt 2) (list) (let [(afterHead (optionOr (listTail toks) (list)))] (optionOr (listSlice afterHead 0 (- cnt 2)) (list)))))

fn parseParenGroup toks: (List ilx/IndentToken) -> (Pair (List ilx/IndentToken) (List rd/SExpr))
  (let [(inner (stripOuterDelims toks))] (pair (list) (parseTokensToExprList inner)))

fn parseBracketGroup toks: (List ilx/IndentToken) -> (Pair (List ilx/IndentToken) (List rd/SExpr))
  (let [(inner (stripOuterDelims toks))] (pair (list) (parseTokensToExprList inner)))

fn desugarDestructuring isRecord: Bool vars: (List String) expr: rd/SExpr bodyForms: (List rd/SExpr) -> rd/SExpr
  (let [(finalBody (if (listEmpty? bodyForms) (list (rd/makeAtom "<body>")) bodyForms))] (if isRecord (let [(bindings (map (fn [(v String)] -> rd/SExpr (let [(fieldSym (rd/makeAtom (str ".-" v))) (getter (rd/makeList (list fieldSym expr)))] (rd/makeList (list (rd/makeAtom v) getter)))) vars)) (bVect (rd/makeVect bindings))] (rd/makeList (cons (rd/makeAtom "let") (cons bVect finalBody)))) (let [(bindingsFold (fold (fn [(acc (Pair (List rd/SExpr) Int64)) (v String)] -> (Pair (List rd/SExpr) Int64) (let [(curList (pairFirst acc)) (idx (pairSecond acc)) (idxAtom (rd/makeAtom (stringFromInt64 idx))) (getter (rd/makeList (list (rd/makeAtom "mt") (rd/makeList (list (rd/makeAtom "listGet") expr idxAtom)) (rd/makeList (list (rd/makeList (list (rd/makeAtom "some") (rd/makeAtom v))) (rd/makeAtom v)))))) (binding (rd/makeList (list (rd/makeAtom v) getter)))] (pair (listAppend curList (list binding)) (+ idx 1)))) (pair (list) 0) vars)) (bVect (rd/makeVect (pairFirst bindingsFold)))] (rd/makeList (cons (rd/makeAtom "let") (cons bVect finalBody))))))

fn desugarLetBinding varName: String expr: rd/SExpr bodyForms: (List rd/SExpr) -> rd/SExpr
  (let [(finalBody (if (listEmpty? bodyForms) (list (rd/makeAtom "<body>")) bodyForms)) (binding (rd/makeList (list (rd/makeAtom varName) expr))) (bVect (rd/makeVect (list binding)))] (rd/makeList (cons (rd/makeAtom "let") (cons bVect finalBody))))

fn stripTrailingComma s: String -> String
  (if (stringEndsWith? s ",") (optionOr (stringSlice s 0 (- (stringLength s) 1)) s) s)

(schema PatternExtractResult (:f vars (List String)) (:f rest (List ilx/IndentToken)))

fn extractPatternVars toks: (List ilx/IndentToken) isRecord: Bool -> PatternExtractResult
  (let [(step (fold (fn [(acc (Pair (List String) (Pair (List ilx/IndentToken) Bool))) (t ilx/IndentToken)] -> (Pair (List String) (Pair (List ilx/IndentToken) Bool)) (let [(vars (pairFirst acc)) (rem (pairFirst (pairSecond acc))) (done (pairSecond (pairSecond acc)))] (if done (pair vars (pair (cons t rem) true)) (let [(isClosing (if isRecord (or (= t.rawText "}") (mt t.kind ((tokRbrace) true) (_ false))) (or (= t.rawText "]") (mt t.kind ((tokRbracket) true) (_ false)))))] (if isClosing (pair vars (pair rem true)) (let [(cleaned (stripTrailingComma t.rawText))] (if (or (stringEmpty? cleaned) (= cleaned ",")) acc (pair (cons cleaned vars) (pair rem false))))))))) (pair (list) (pair (list) false)) toks))] (PatternExtractResult :vars (listReverse (pairFirst step)) :rest (listReverse (pairFirst (pairSecond step)))))

fn splitTokensAtWord toks: (List ilx/IndentToken) word: String -> (Pair (List ilx/IndentToken) (Pair (List ilx/IndentToken) Bool))
  (let [(step (fold (fn [(acc (Pair (List ilx/IndentToken) (Pair (List ilx/IndentToken) (Pair Int64 Bool)))) (t ilx/IndentToken)] -> (Pair (List ilx/IndentToken) (Pair (List ilx/IndentToken) (Pair Int64 Bool))) (let [(before (pairFirst acc)) (after (pairFirst (pairSecond acc))) (depth (pairFirst (pairSecond (pairSecond acc)))) (found (pairSecond (pairSecond (pairSecond acc))))] (if found (pair before (pair (cons t after) (pair depth true))) (if (and (= depth 0) (= t.rawText word)) (pair before (pair after (pair depth true))) (let [(nextDepth (mt t.kind ((tokLparen) (+ depth 1)) ((tokLbracket) (+ depth 1)) ((tokLbrace) (+ depth 1)) ((tokRparen) (- depth 1)) ((tokRbracket) (- depth 1)) ((tokRbrace) (- depth 1)) (_ depth)))] (pair (cons t before) (pair after (pair nextDepth false)))))))) (pair (list) (pair (list) (pair 0 false))) toks))] (pair (listReverse (pairFirst step)) (pair (listReverse (pairFirst (pairSecond step))) (pairSecond (pairSecond (pairSecond step))))))

fn splitTokensAtColon toks: (List ilx/IndentToken) -> (Pair (List ilx/IndentToken) (Pair (List ilx/IndentToken) Bool))
  (let [(step (fold (fn [(acc (Pair (List ilx/IndentToken) (Pair (List ilx/IndentToken) Bool))) (t ilx/IndentToken)] -> (Pair (List ilx/IndentToken) (Pair (List ilx/IndentToken) Bool)) (let [(before (pairFirst acc)) (after (pairFirst (pairSecond acc))) (found (pairSecond (pairSecond acc)))] (if found (pair before (pair (cons t after) true)) (if (or (= t.rawText ":") (mt t.kind ((tokColon) true) (_ false))) (pair before (pair after true)) (pair (cons t before) (pair after false)))))) (pair (list) (pair (list) false)) toks))] (pair (listReverse (pairFirst step)) (pair (listReverse (pairFirst (pairSecond step))) (pairSecond (pairSecond step)))))

(schema PreprocessState (:f emitted (List ilx/IndentToken)) (:f pending (Option ilx/IndentToken)) (:f prevEmitted (Option ilx/IndentToken)) (:f inBrk Int64) (:f delimDepth Int64))

fn preprocessTokens toks: (List ilx/IndentToken) -> (List ilx/IndentToken)
  (let [(finalState (fold (fn [(st PreprocessState) (t ilx/IndentToken)] -> PreprocessState (let [(k t.kind) (dDepth st.delimDepth)] (if (and (> dDepth 0) (or (mt k ((tokNewline) true) (_ false)) (or (mt k ((tokIndent _) true) (_ false)) (mt k ((tokDedent _) true) (_ false))))) (mt st.pending ((some p) (PreprocessState :emitted (cons p st.emitted) :pending (none) :prevEmitted (some p) :inBrk st.inBrk :delimDepth dDepth)) ((none) st)) (let [(dInc (mt k ((tokLparen) 1) ((tokLbracket) 1) ((tokLbrace) 1) (_ 0))) (dDec (mt k ((tokRparen) 1) ((tokRbracket) 1) ((tokRbrace) 1) (_ 0))) (nxtDelim (let [(cur (+ dDepth dInc))] (if (> dDec 0) (if (> cur 0) (- cur 1) 0) cur)))] (mt st.pending ((none) (mt k ((tokLbracket) (PreprocessState :emitted (cons t st.emitted) :pending (none) :prevEmitted (some t) :inBrk (+ st.inBrk 1) :delimDepth nxtDelim)) ((tokRbracket) (let [(nxtB (if (> st.inBrk 0) (- st.inBrk 1) 0))] (PreprocessState :emitted (cons t st.emitted) :pending (none) :prevEmitted (some t) :inBrk nxtB :delimDepth nxtDelim))) ((tokSymbol _) (PreprocessState :emitted st.emitted :pending (some t) :prevEmitted st.prevEmitted :inBrk st.inBrk :delimDepth nxtDelim)) (_ (PreprocessState :emitted (cons t st.emitted) :pending (none) :prevEmitted (some t) :inBrk st.inBrk :delimDepth nxtDelim)))) ((some p) (let [(pRaw p.rawText) (isAdj (and (= p.line t.line) (= (+ p.col (stringLength pRaw)) t.col)))] (cond ((and isAdj (= t.rawText "!")) (let [(mergedSym (str pRaw "!")) (mergedTok (ilx/makeIndentToken (ilx/tokSymbol mergedSym) mergedSym p.line p.col))] (PreprocessState :emitted st.emitted :pending (some mergedTok) :prevEmitted st.prevEmitted :inBrk st.inBrk :delimDepth nxtDelim))) ((and isAdj (or (= t.rawText "?") (mt k ((tokQuestion) true) (_ false)))) (let [(mergedSym (str pRaw "?")) (mergedTok (ilx/makeIndentToken (ilx/tokSymbol mergedSym) mergedSym p.line p.col))] (PreprocessState :emitted st.emitted :pending (some mergedTok) :prevEmitted st.prevEmitted :inBrk st.inBrk :delimDepth nxtDelim))) (else (mt k ((tokLbracket) (PreprocessState :emitted (cons t (cons p st.emitted)) :pending (none) :prevEmitted (some t) :inBrk (+ st.inBrk 1) :delimDepth nxtDelim)) ((tokRbracket) (let [(nxtB (if (> st.inBrk 0) (- st.inBrk 1) 0))] (PreprocessState :emitted (cons t (cons p st.emitted)) :pending (none) :prevEmitted (some t) :inBrk nxtB :delimDepth nxtDelim))) ((tokSymbol _) (PreprocessState :emitted (cons p st.emitted) :pending (some t) :prevEmitted (some p) :inBrk st.inBrk :delimDepth nxtDelim)) (_ (PreprocessState :emitted (cons t (cons p st.emitted)) :pending (none) :prevEmitted (some t) :inBrk st.inBrk :delimDepth nxtDelim)))))))))))) (PreprocessState :emitted (list) :pending (none) :prevEmitted (none) :inBrk 0 :delimDepth 0) toks))] (mt finalState.pending ((some p) (listReverse (cons p finalState.emitted))) ((none) (listReverse finalState.emitted))))

fn parseTokensToExprList toks: (List ilx/IndentToken) -> (List rd/SExpr)
  (let [(items (fold (fn [(acc (Pair (List rd/SExpr) (Pair (List ilx/IndentToken) (Pair Int64 (Pair Int64 (Pair Bool (Option ilx/IndentToken))))))) (t ilx/IndentToken)] -> (Pair (List rd/SExpr) (Pair (List ilx/IndentToken) (Pair Int64 (Pair Int64 (Pair Bool (Option ilx/IndentToken)))))) (let [(collected (pairFirst acc)) (subToks (pairFirst (pairSecond acc))) (parenDepth (pairFirst (pairSecond (pairSecond acc)))) (bracketDepth (pairFirst (pairSecond (pairSecond (pairSecond acc))))) (isCall (pairFirst (pairSecond (pairSecond (pairSecond (pairSecond acc)))))) (lastTok (pairSecond (pairSecond (pairSecond (pairSecond (pairSecond acc))))))] (mt t.kind ((tokLparen) (let [(nxtP (+ parenDepth 1)) (callFlag (if (= parenDepth 0) (mt lastTok ((some lt) (and (= lt.line t.line) (= (+ lt.col (stringLength lt.rawText)) t.col))) ((none) false)) isCall))] (pair collected (pair (cons t subToks) (pair nxtP (pair bracketDepth (pair callFlag lastTok))))))) ((tokRparen) (let [(nxtP (- parenDepth 1))] (if (and (<= nxtP 0) (= bracketDepth 0)) (let [(allParenToks (listReverse (cons t subToks))) (parenItems (pairSecond (parseParenGroup allParenToks))) (subSexpr (rd/makeList parenItems))] (if isCall (mt (listHead collected) ((some headExpr) (if (and (rd/isAtom? headExpr) (not (stringStartsWith? (rd/sexprHead headExpr) ":")) (not (stringStartsWith? (rd/sexprHead headExpr) "\"")) (!= (rd/sexprHead headExpr) "let") (!= (rd/sexprHead headExpr) "fn") (!= (rd/sexprHead headExpr) "if") (!= (rd/sexprHead headExpr) "match") (!= (rd/sexprHead headExpr) "try") (!= (rd/sexprHead headExpr) "|>") (!= (rd/sexprHead headExpr) "->") (!= (rd/sexprHead headExpr) "?") (!= (rd/sexprHead headExpr) "??") (!= (rd/sexprHead headExpr) "=")) (let [(callSexpr (rd/makeList (cons headExpr parenItems))) (remCollected (optionOr (listTail collected) (list)))] (pair (cons callSexpr remCollected) (pair (list) (pair 0 (pair 0 (pair false (none))))))) (pair (cons subSexpr collected) (pair (list) (pair 0 (pair 0 (pair false (none)))))))) ((none) (pair (cons subSexpr collected) (pair (list) (pair 0 (pair 0 (pair false (none)))))))) (pair (cons subSexpr collected) (pair (list) (pair 0 (pair 0 (pair false (none)))))))) (pair collected (pair (cons t subToks) (pair nxtP (pair bracketDepth (pair isCall lastTok)))))))) ((tokLbracket) (let [(nxtB (+ bracketDepth 1))] (pair collected (pair (cons t subToks) (pair parenDepth (pair nxtB (pair isCall lastTok))))))) ((tokRbracket) (let [(nxtB (- bracketDepth 1))] (if (and (<= nxtB 0) (= parenDepth 0)) (let [(allBrkToks (listReverse (cons t subToks))) (brkItems (pairSecond (parseBracketGroup allBrkToks))) (subSexpr (rd/makeList (cons (rd/makeAtom "list") brkItems)))] (pair (cons subSexpr collected) (pair (list) (pair 0 (pair 0 (pair false (none))))))) (pair collected (pair (cons t subToks) (pair parenDepth (pair nxtB (pair isCall lastTok)))))))) ((tokQuestion) (if (or (> parenDepth 0) (> bracketDepth 0)) (pair collected (pair (cons t subToks) (pair parenDepth (pair bracketDepth (pair isCall lastTok))))) (mt (listHead collected) ((some prevExpr) (let [(rem (optionOr (listTail collected) (list))) (isAdjacent (mt lastTok ((some lt) (and (= lt.line t.line) (= (+ lt.col (stringLength lt.rawText)) t.col))) ((none) false))) (isSym (rd/isAtom? prevExpr)) (prevName (if isSym (rd/sexprHead prevExpr) "")) (shouldBeSymbol (and isAdjacent isSym (mt lastTok ((some lt) (mt lt.kind ((tokSymbol _) true) (_ false))) ((none) false))))] (if shouldBeSymbol (let [(mergedAtom (rd/makeAtom (str prevName "?"))) (newTok (ilx/makeIndentToken (ilx/tokSymbol (str prevName "?")) (str prevName "?") t.line t.col))] (pair (cons mergedAtom rem) (pair (list) (pair 0 (pair 0 (pair false (some newTok))))))) (let [(desugared (desugarTry prevExpr))] (pair (cons desugared rem) (pair (list) (pair 0 (pair 0 (pair false (none)))))))))) ((none) (pair (cons (parseSingleTokenExpr t) collected) (pair (list) (pair 0 (pair 0 (pair false (some t)))))))))) (_ (if (or (> parenDepth 0) (> bracketDepth 0)) (pair collected (pair (cons t subToks) (pair parenDepth (pair bracketDepth (pair isCall lastTok))))) (pair (cons (parseSingleTokenExpr t) collected) (pair (list) (pair 0 (pair 0 (pair false (some t))))))))))) (pair (list) (pair (list) (pair 0 (pair 0 (pair false (none)))))) toks))] (listReverse (pairFirst items)))

fn isLetDestructureLine? toks: (List ilx/IndentToken) -> Bool
  (mt (listHead toks) ((none) false) ((some t0) (if (= t0.rawText "let") (fold (fn [(acc Bool) (t ilx/IndentToken)] -> Bool (or acc (or (= t.rawText "=") (mt t.kind ((tokEqual) true) (_ false))))) false toks) false)))

(schema LetLineInfo (:f isRecord Bool) (:f vars (List String)) (:f expr rd/SExpr) (:f inlineBody (List rd/SExpr)) (:f hasInlineBody Bool))

fn parseLetLineInfo toks: (List ilx/IndentToken) -> LetLineInfo
  (let [(toksAfterLet (optionOr (listTail toks) (list))) (openTok (optionOr (listHead toksAfterLet) (ilx/makeIndentToken (ilx/tokLbracket) "[" 1 1))) (isRecord (or (= openTok.rawText "{") (mt openTok.kind ((tokLbrace) true) (_ false)))) (isBracket (or (= openTok.rawText "[") (mt openTok.kind ((tokLbracket) true) (_ false))))] (if (not (or isRecord isBracket)) (let [(varName openTok.rawText) (vars (list varName)) (afterVar (optionOr (listTail toksAfterLet) (list))) (afterEq (mt (listHead afterVar) ((some eqTok) (if (or (= eqTok.rawText "=") (mt eqTok.kind ((tokEqual) true) (_ false))) (optionOr (listTail afterVar) (list)) afterVar)) ((none) (list))))] (let [(inSplit (splitTokensAtWord afterEq "in")) (hasIn (pairSecond (pairSecond inSplit)))] (if hasIn (let [(exprToks (pairFirst inSplit)) (bodyToks (pairFirst (pairSecond inSplit))) (expr (parseLineTokensToSexpr exprToks)) (body (if (listEmpty? bodyToks) (list) (list (parseLineTokensToSexpr bodyToks))))] (LetLineInfo :isRecord false :vars vars :expr expr :inlineBody body :hasInlineBody (not (listEmpty? body)))) (let [(colonSplit (splitTokensAtColon afterEq)) (hasColon (pairSecond (pairSecond colonSplit)))] (if hasColon (let [(exprToks (pairFirst colonSplit)) (bodyToks (pairFirst (pairSecond colonSplit))) (expr (parseLineTokensToSexpr exprToks)) (body (if (listEmpty? bodyToks) (list) (list (parseLineTokensToSexpr bodyToks))))] (LetLineInfo :isRecord false :vars vars :expr expr :inlineBody body :hasInlineBody (not (listEmpty? body)))) (let [(expr (parseLineTokensToSexpr afterEq))] (LetLineInfo :isRecord false :vars vars :expr expr :inlineBody (list) :hasInlineBody false))))))) (let [(patternToks (optionOr (listTail toksAfterLet) (list))) (patRes (extractPatternVars patternToks isRecord)) (vars patRes.vars) (afterPat patRes.rest)] (let [(afterEq (mt (listHead afterPat) ((some eqTok) (if (or (= eqTok.rawText "=") (mt eqTok.kind ((tokEqual) true) (_ false))) (optionOr (listTail afterPat) (list)) afterPat)) ((none) (list))))] (let [(inSplit (splitTokensAtWord afterEq "in")) (hasIn (pairSecond (pairSecond inSplit)))] (if hasIn (let [(exprToks (pairFirst inSplit)) (bodyToks (pairFirst (pairSecond inSplit))) (expr (parseLineTokensToSexpr exprToks)) (body (if (listEmpty? bodyToks) (list) (list (parseLineTokensToSexpr bodyToks))))] (LetLineInfo :isRecord isRecord :vars vars :expr expr :inlineBody body :hasInlineBody (not (listEmpty? body)))) (let [(colonSplit (splitTokensAtColon afterEq)) (hasColon (pairSecond (pairSecond colonSplit)))] (if hasColon (let [(exprToks (pairFirst colonSplit)) (bodyToks (pairFirst (pairSecond colonSplit))) (expr (parseLineTokensToSexpr exprToks)) (body (if (listEmpty? bodyToks) (list) (list (parseLineTokensToSexpr bodyToks))))] (LetLineInfo :isRecord isRecord :vars vars :expr expr :inlineBody body :hasInlineBody (not (listEmpty? body)))) (let [(exprList (parseTokensToExprList afterEq)) (cnt (listLength exprList))] (cond ((= cnt 0) (LetLineInfo :isRecord isRecord :vars vars :expr (rd/makeAtom "") :inlineBody (list) :hasInlineBody false)) ((= cnt 1) (LetLineInfo :isRecord isRecord :vars vars :expr (optionOr (listHead exprList) (rd/makeAtom "")) :inlineBody (list) :hasInlineBody false)) ((and (> cnt 1) (rd/isList? (optionOr (listGet exprList (- cnt 1)) (rd/makeAtom "")))) (let [(lastItem (optionOr (listGet exprList (- cnt 1)) (rd/makeAtom ""))) (initItems (optionOr (listSlice exprList 0 (- cnt 1)) (list))) (expr (if (= (listLength initItems) 1) (optionOr (listHead initItems) (rd/makeAtom "")) (rd/makeList initItems)))] (LetLineInfo :isRecord isRecord :vars vars :expr expr :inlineBody (list lastItem) :hasInlineBody true))) (else (LetLineInfo :isRecord isRecord :vars vars :expr (rd/makeList exprList) :inlineBody (list) :hasInlineBody false))))))))))))

fn applyLetDesugar info: LetLineInfo body: (List rd/SExpr) -> rd/SExpr
  (if (and (not info.isRecord) (= (listLength info.vars) 1)) (desugarLetBinding (optionOr (listHead info.vars) "") info.expr body) (desugarDestructuring info.isRecord info.vars info.expr body))

fn hasPipeSymbol? items: (List rd/SExpr) -> Bool
  (fold (fn [(acc Bool) (it rd/SExpr)] -> Bool (or acc (and (rd/isAtom? it) (= (rd/sexprHead it) "|>")))) false items)

fn desugarPipeList items: (List rd/SExpr) -> rd/SExpr
  (let [(parts (fold (fn [(acc (Pair (List rd/SExpr) (List rd/SExpr))) (it rd/SExpr)] -> (Pair (List rd/SExpr) (List rd/SExpr)) (let [(currentSegment (pairFirst acc)) (allSegments (pairSecond acc))] (if (and (rd/isAtom? it) (= (rd/sexprHead it) "|>")) (let [(segExpr (if (= (listLength currentSegment) 1) (optionOr (listHead currentSegment) (rd/makeAtom "")) (rd/makeList (listReverse currentSegment))))] (pair (list) (cons segExpr allSegments))) (pair (cons it currentSegment) allSegments)))) (pair (list) (list)) items))] (let [(lastSeg (pairFirst parts)) (priorSegments (pairSecond parts)) (lastExpr (if (= (listLength lastSeg) 1) (optionOr (listHead lastSeg) (rd/makeAtom "")) (rd/makeList (listReverse lastSeg)))) (allExprs (listReverse (cons lastExpr priorSegments)))] (rd/makeList (cons (rd/makeAtom "|>") allExprs))))

fn desugarTryPrefix items: (List rd/SExpr) -> (List rd/SExpr)
  (mt (listHead items) ((none) (list)) ((some hd) (let [(tl (optionOr (listTail items) (list)))] (if (and (rd/isAtom? hd) (= (rd/sexprHead hd) "try")) (mt (listHead tl) ((none) (list hd)) ((some nextExpr) (let [(rem (optionOr (listTail tl) (list))) (desugared (desugarTry nextExpr))] (cons desugared (desugarTryPrefix rem))))) (cons hd (desugarTryPrefix tl))))))

fn hasCoalesceSymbol? items: (List rd/SExpr) -> Bool
  (fold (fn [(acc Bool) (it rd/SExpr)] -> Bool (or acc (and (rd/isAtom? it) (= (rd/sexprHead it) "??")))) false items)

fn desugarCoalesce items: (List rd/SExpr) -> rd/SExpr
  (let [(split (fold (fn [(acc (Pair (List rd/SExpr) (Pair (List rd/SExpr) Bool))) (it rd/SExpr)] -> (Pair (List rd/SExpr) (Pair (List rd/SExpr) Bool)) (let [(left (pairFirst acc)) (right (pairFirst (pairSecond acc))) (seen (pairSecond (pairSecond acc)))] (if seen (pair left (pair (cons it right) true)) (if (and (rd/isAtom? it) (= (rd/sexprHead it) "??")) (pair left (pair (list) true)) (pair (cons it left) (pair (list) false)))))) (pair (list) (pair (list) false)) items))] (let [(leftItems (listReverse (pairFirst split))) (rightItems (listReverse (pairFirst (pairSecond split)))) (leftExpr (if (= (listLength leftItems) 1) (optionOr (listHead leftItems) (rd/makeAtom "")) (rd/makeList leftItems))) (rightExpr (if (hasCoalesceSymbol? rightItems) (desugarCoalesce rightItems) (if (= (listLength rightItems) 1) (optionOr (listHead rightItems) (rd/makeAtom "")) (rd/makeList rightItems))))] (rd/makeList (list (rd/makeAtom "??") leftExpr rightExpr))))

fn isDotAccessorAtom? name: String -> Bool
  (stringStartsWith? name ".-")

fn memberChainToPath s: rd/SExpr -> (Option String)
  (mt s
    ((rd/sexprAtom name) (if (isDotAccessorAtom? name) (none) (some name)))
    ((rd/sexprList items)
     (if (= (listLength items) 2)
       (let [(h (optionOr (listHead items) (rd/makeAtom ""))) (inner (optionOr (listGet items 1) (rd/makeAtom "")))]
         (if (and (rd/isAtom? h) (isDotAccessorAtom? (rd/sexprHead h)))
           (mt (memberChainToPath inner)
             ((some base) (some (str base "." (optionOr (stringSlice (rd/sexprHead h) 2 (stringLength (rd/sexprHead h))) ""))))
             ((none) (none)))
           (none)))
       (none)))
    ((rd/sexprVect _) (none)))

fn repairModulePathSexpr s: rd/SExpr -> rd/SExpr
  (mt (memberChainToPath s)
    ((some path) (rd/makeAtom path))
    ((none)
     (mt s
       ((rd/sexprList items) (rd/makeList (map repairModulePathSexpr items)))
       ((rd/sexprVect items) (rd/makeVect (map repairModulePathSexpr items)))
       ((rd/sexprAtom _) s))))

fn isModuleFormSexpr? s: rd/SExpr -> Bool
  (and (rd/isList? s) (= (rd/sexprHead s) "module"))

fn parseLineTokensToSexpr toks: (List ilx/IndentToken) -> rd/SExpr
  (if (isLetDestructureLine? toks) (let [(info (parseLetLineInfo toks))] (applyLetDesugar info info.inlineBody)) (let [(rawList (parseTokensToExprList toks)) (resList (desugarTryPrefix rawList)) (built (cond ((hasPipeSymbol? resList) (desugarPipeList resList)) ((hasCoalesceSymbol? resList) (desugarCoalesce resList)) ((= (listLength resList) 1) (optionOr (listHead resList) (rd/makeAtom ""))) (else (rd/makeList resList))))] (if (isModuleFormSexpr? built) (repairModulePathSexpr built) built)))

(schema BlockResult (:f rest (List ilx/IndentToken)) (:f forms (List rd/SExpr)) (:f poses (List (Pair Int64 Int64))))

fn isIfLine? toks: (List ilx/IndentToken) -> Bool
  (mt (listHead toks) ((some t) (= t.rawText "if")) ((none) false))

fn parseBlockLine remToks: (List ilx/IndentToken) forms: (List rd/SExpr) curLevel: Int64 targetLevel: Int64 -> (Pair (List rd/SExpr) (Pair (List ilx/IndentToken) (Pair Int64 Bool)))
  (let [(lineSplit (takeUntilLineEnd remToks)) (lineToks (pairFirst lineSplit)) (afterLine (pairSecond lineSplit))] (if (isLetDestructureLine? lineToks) (let [(info (parseLetLineInfo lineToks))] (if info.hasInlineBody (let [(letSexpr (applyLetDesugar info info.inlineBody))] (pair (cons letSexpr forms) (pair afterLine (pair curLevel false)))) (mt (listHead afterLine) ((some nextT) (mt nextT.kind ((tokIndent lvl) (let [(blockRes (parseIndentedBlock (optionOr (listTail afterLine) (list)) lvl)) (bodyForms blockRes.forms) (remAfter blockRes.rest) (letSexpr (applyLetDesugar info bodyForms))] (pair (cons letSexpr forms) (pair remAfter (pair curLevel false))))) (_ (let [(restBlock (parseIndentedBlock afterLine targetLevel)) (bodyForms restBlock.forms) (remAfter restBlock.rest) (letSexpr (applyLetDesugar info bodyForms))] (pair (cons letSexpr forms) (pair remAfter (pair curLevel true))))))) ((none) (let [(letSexpr (applyLetDesugar info (list)))] (pair (cons letSexpr forms) (pair afterLine (pair curLevel true)))))))) (if (isIfLine? lineToks) (let [(condToks (filter (fn [(t ilx/IndentToken)] -> Bool (and (!= t.rawText "if") (!= t.rawText ":"))) lineToks)) (condExpr (parseLineTokensToSexpr condToks))] (mt (listHead afterLine) ((some nextT) (mt nextT.kind ((tokIndent lvl) (let [(thenBlockRes (parseIndentedBlock (optionOr (listTail afterLine) (list)) lvl)) (thenForms thenBlockRes.forms) (afterThen thenBlockRes.rest) (thenExpr (if (= (listLength thenForms) 1) (optionOr (listHead thenForms) (rd/makeAtom "")) (rd/makeList (cons (rd/makeAtom "do") thenForms)))) (afterThenClean (skipNewlines afterThen))] (mt (listHead afterThenClean) ((some elseTok) (if (= elseTok.rawText "else") (let [(elseSplit (takeUntilLineEnd afterThenClean)) (elseLineToks (pairFirst elseSplit)) (afterElseLine (pairSecond elseSplit)) (elseInline (filter (fn [(t ilx/IndentToken)] -> Bool (and (!= t.rawText "else") (!= t.rawText ":"))) elseLineToks))] (if (not (listEmpty? elseInline)) (let [(elseExpr (parseLineTokensToSexpr elseInline)) (ifSexpr (rd/makeList (list (rd/makeAtom "if") condExpr thenExpr elseExpr)))] (pair (cons ifSexpr forms) (pair afterElseLine (pair curLevel false)))) (mt (listHead afterElseLine) ((some nextElseT) (mt nextElseT.kind ((tokIndent elseLvl) (let [(elseBlockRes (parseIndentedBlock (optionOr (listTail afterElseLine) (list)) elseLvl)) (elseForms elseBlockRes.forms) (remAfterElse elseBlockRes.rest) (elseExpr (if (= (listLength elseForms) 1) (optionOr (listHead elseForms) (rd/makeAtom "")) (rd/makeList (cons (rd/makeAtom "do") elseForms)))) (ifSexpr (rd/makeList (list (rd/makeAtom "if") condExpr thenExpr elseExpr)))] (pair (cons ifSexpr forms) (pair remAfterElse (pair curLevel false))))) (_ (let [(ifSexpr (rd/makeList (list (rd/makeAtom "if") condExpr thenExpr (rd/makeAtom "nil"))))] (pair (cons ifSexpr forms) (pair afterElseLine (pair curLevel false))))))) ((none) (let [(ifSexpr (rd/makeList (list (rd/makeAtom "if") condExpr thenExpr (rd/makeAtom "nil"))))] (pair (cons ifSexpr forms) (pair (list) (pair curLevel false)))))))) (let [(ifSexpr (rd/makeList (list (rd/makeAtom "if") condExpr thenExpr (rd/makeAtom "nil"))))] (pair (cons ifSexpr forms) (pair afterThen (pair curLevel false)))))) ((none) (let [(ifSexpr (rd/makeList (list (rd/makeAtom "if") condExpr thenExpr (rd/makeAtom "nil"))))] (pair (cons ifSexpr forms) (pair (list) (pair curLevel false)))))))) (_ (let [(lineForm (parseLineTokensToSexpr lineToks))] (pair (cons lineForm forms) (pair afterLine (pair curLevel false))))))) ((none) (let [(lineForm (parseLineTokensToSexpr lineToks))] (pair (cons lineForm forms) (pair afterLine (pair curLevel false))))))) (let [(lineForm (parseLineTokensToSexpr lineToks))] (if (= (rd/sexprHead lineForm) "match") (mt (listHead afterLine) ((some nextT) (mt nextT.kind ((tokIndent lvl) (let [(matchRes (parseMatchArms (optionOr (listTail afterLine) (list)) lvl)) (arms matchRes.arms) (remAfterMatch matchRes.rest) (targetSexpr (optionOr (listGet (rd/sexprToList lineForm) 1) (rd/makeAtom "_"))) (fullMatchSexpr (rd/makeList (list (rd/makeAtom "match") targetSexpr (rd/makeList arms))))] (pair (cons fullMatchSexpr forms) (pair remAfterMatch (pair curLevel false))))) (_ (pair (cons lineForm forms) (pair afterLine (pair curLevel false)))))) ((none) (pair (cons lineForm forms) (pair afterLine (pair curLevel false))))) (pair (cons lineForm forms) (pair afterLine (pair curLevel false))))))))

fn blockLoop remToks: (List ilx/IndentToken) forms: (List rd/SExpr) poses: (List (Pair Int64 Int64)) curLevel: Int64 targetLevel: Int64 -> BlockResult
  (mt (listHead remToks) ((none) (BlockResult :rest (list) :forms (listReverse forms) :poses (listReverse poses))) ((some t) (mt t.kind ((tokDedent l) (if (<= l targetLevel) (BlockResult :rest (optionOr (listTail remToks) (list)) :forms (listReverse forms) :poses (listReverse poses)) (blockLoop (optionOr (listTail remToks) (list)) forms poses l targetLevel))) ((tokNewline) (blockLoop (optionOr (listTail remToks) (list)) forms poses curLevel targetLevel)) ((tokIndent l) (blockLoop (optionOr (listTail remToks) (list)) forms poses l targetLevel)) ((tokEof) (BlockResult :rest remToks :forms (listReverse forms) :poses (listReverse poses))) (_ (let [(lineRes (parseBlockLine remToks forms curLevel targetLevel))] (let [(newForms (pairFirst lineRes)) (newRem (pairFirst (pairSecond lineRes))) (newCur (pairFirst (pairSecond (pairSecond lineRes)))) (isDone (pairSecond (pairSecond (pairSecond lineRes)))) (newPoses (if (> (listLength newForms) (listLength forms)) (cons (pair t.line t.col) poses) poses))] (if isDone (BlockResult :rest newRem :forms (listReverse newForms) :poses (listReverse newPoses)) (let [(safeRem (if (= (listLength newRem) (listLength remToks)) (optionOr (listTail remToks) (list)) newRem))] (blockLoop safeRem newForms newPoses newCur targetLevel)))))))))

fn parseIndentedBlock toks: (List ilx/IndentToken) targetLevel: Int64 -> BlockResult
  (blockLoop toks (list) (list) targetLevel targetLevel)

(schema MatchArm (:f pattern rd/SExpr) (:f body rd/SExpr))

fn parseMatchArmLine lineToks: (List ilx/IndentToken) -> MatchArm
  (let [(split (fold (fn [(acc (Pair (List ilx/IndentToken) (Pair (List ilx/IndentToken) Bool))) (t ilx/IndentToken)] -> (Pair (List ilx/IndentToken) (Pair (List ilx/IndentToken) Bool)) (let [(pat (pairFirst acc)) (bod (pairFirst (pairSecond acc))) (seenArrow (pairSecond (pairSecond acc)))] (if seenArrow (pair pat (pair (cons t bod) true)) (mt t.kind ((tokArrow) (pair pat (pair (list) true))) (_ (pair (cons t pat) (pair (list) false))))))) (pair (list) (pair (list) false)) lineToks))] (let [(patToks (listReverse (pairFirst split))) (bodToks (listReverse (pairFirst (pairSecond split)))) (seenArrow (pairSecond (pairSecond split)))] (let [(patSexpr (parseLineTokensToSexpr patToks)) (bodSexpr (if seenArrow (if (listEmpty? bodToks) (rd/makeAtom "") (parseLineTokensToSexpr bodToks)) (rd/makeAtom "")))] (MatchArm :pattern patSexpr :body bodSexpr))))

(schema MatchBlockResult (:f rest (List ilx/IndentToken)) (:f arms (List rd/SExpr)))

fn matchArmsLoop remToks: (List ilx/IndentToken) arms: (List rd/SExpr) matchLevel: Int64 -> MatchBlockResult
  (mt (listHead remToks) ((none) (MatchBlockResult :rest (list) :arms (listReverse arms))) ((some t) (mt t.kind ((tokDedent l) (if (<= l matchLevel) (MatchBlockResult :rest (optionOr (listTail remToks) (list)) :arms (listReverse arms)) (matchArmsLoop (optionOr (listTail remToks) (list)) arms matchLevel))) ((tokNewline) (matchArmsLoop (optionOr (listTail remToks) (list)) arms matchLevel)) ((tokIndent _) (matchArmsLoop (optionOr (listTail remToks) (list)) arms matchLevel)) ((tokEof) (MatchBlockResult :rest remToks :arms (listReverse arms))) (_ (let [(lineSplit (takeUntilLineEnd remToks)) (lineToks (pairFirst lineSplit)) (afterLine (pairSecond lineSplit)) (arm (parseMatchArmLine lineToks)) (isBodyEmpty (or (and (rd/isAtom? arm.body) (= (rd/sexprHead arm.body) "")) (and (rd/isList? arm.body) (listEmpty? (rd/sexprToList arm.body)))))] (if isBodyEmpty (mt (listHead afterLine) ((some nextT) (mt nextT.kind ((tokIndent armLvl) (let [(armBlockRes (parseIndentedBlock (optionOr (listTail afterLine) (list)) armLvl)) (armBodyForms armBlockRes.forms) (remAfterArm armBlockRes.rest) (armBody (if (= (listLength armBodyForms) 1) (optionOr (listHead armBodyForms) (rd/makeAtom "")) (rd/makeList (cons (rd/makeAtom "do") armBodyForms)))) (armSexpr (rd/makeList (list arm.pattern armBody)))] (matchArmsLoop remAfterArm (cons armSexpr arms) matchLevel))) (_ (let [(armSexpr (rd/makeList (list arm.pattern arm.body)))] (matchArmsLoop afterLine (cons armSexpr arms) matchLevel))))) ((none) (let [(armSexpr (rd/makeList (list arm.pattern arm.body)))] (MatchBlockResult :rest (list) :arms (listReverse (cons armSexpr arms)))))) (let [(armSexpr (rd/makeList (list arm.pattern arm.body)))] (matchArmsLoop afterLine (cons armSexpr arms) matchLevel))))))))

fn parseMatchArms toks: (List ilx/IndentToken) matchLevel: Int64 -> MatchBlockResult
  (matchArmsLoop toks (list) matchLevel)

(schema FnSignature (:f name String) (:f effect Bool) (:f params rd/SExpr) (:f retType rd/SExpr) (:f docstring (Option String)))

(schema GroupResult (:f group (List ilx/IndentToken)) (:f rest (List ilx/IndentToken)))

fn takeBalancedGroup toks: (List ilx/IndentToken) -> GroupResult
  (let [(step (fold (fn [(acc (Pair (List ilx/IndentToken) (Pair (List ilx/IndentToken) (Pair Int64 Bool)))) (t ilx/IndentToken)] -> (Pair (List ilx/IndentToken) (Pair (List ilx/IndentToken) (Pair Int64 Bool))) (let [(group (pairFirst acc)) (rem (pairFirst (pairSecond acc))) (depth (pairFirst (pairSecond (pairSecond acc)))) (done (pairSecond (pairSecond (pairSecond acc))))] (if done (pair group (pair (cons t rem) (pair depth true))) (let [(dChange (mt t.kind ((tokLparen) 1) ((tokLbracket) 1) ((tokLbrace) 1) ((tokRparen) -1) ((tokRbracket) -1) ((tokRbrace) -1) (_ 0))) (newD (+ depth dChange))] (if (<= newD 0) (pair (cons t group) (pair rem (pair 0 true))) (pair (cons t group) (pair rem (pair newD false)))))))) (pair (list) (pair (list) (pair 0 false))) toks))] (GroupResult :group (listReverse (pairFirst step)) :rest (listReverse (pairFirst (pairSecond step)))))

fn parseOneParamToks toks: (List ilx/IndentToken) paired: Bool -> (Pair (Option rd/SExpr) (List ilx/IndentToken))
  (mt (listHead toks) ((none) (pair (none) (list))) ((some t0) (let [(k t0.kind) (raw t0.rawText)] (cond ((or (= raw ",") (or (= raw ":") (mt k ((tokNewline) true) (_ false)))) (parseOneParamToks (optionOr (listTail toks) (list)) paired)) ((mt k ((tokLparen) true) (_ false)) (let [(bg (takeBalancedGroup toks)) (inner (stripOuterDelims bg.group)) (nameTok (listHead inner))] (mt nameTok ((some nt) (let [(rawName nt.rawText) (pName (if (stringEndsWith? rawName ":") (optionOr (stringSlice rawName 0 (- (stringLength rawName) 1)) rawName) rawName)) (afterName (optionOr (listTail inner) (list))) (typeToks (if (and (not (listEmpty? afterName)) (= (optionOr (listHead afterName) nt).rawText ":")) (optionOr (listTail afterName) (list)) afterName)) (typeExpr (if (listEmpty? typeToks) (rd/makeAtom "") (let [(exprs (parseTokensToExprList typeToks))] (if (= (listLength exprs) 1) (optionOr (listHead exprs) (rd/makeAtom "")) (rd/makeList exprs)))))] (pair (some (rd/makeList (list (rd/makeAtom pName) typeExpr))) bg.rest))) ((none) (pair (none) bg.rest))))) (else (let [(hasColonSuffix (stringEndsWith? raw ":")) (pName (if hasColonSuffix (optionOr (stringSlice raw 0 (- (stringLength raw) 1)) raw) raw)) (afterName (optionOr (listTail toks) (list))) (hasSeparateColon (and (not (listEmpty? afterName)) (= (optionOr (listHead afterName) t0).rawText ":"))) (afterColon (if hasSeparateColon (optionOr (listTail afterName) (list)) afterName))] (if (not (or paired (or hasColonSuffix hasSeparateColon))) (pair (some (rd/makeList (list (rd/makeAtom pName) (rd/makeAtom "")))) afterName) (mt (listHead afterColon) ((none) (pair (some (rd/makeList (list (rd/makeAtom pName) (rd/makeAtom "")))) (list))) ((some t1) (cond ((mt t1.kind ((tokLparen) true) (_ false)) (let [(bg (takeBalancedGroup afterColon)) (exprs (parseTokensToExprList bg.group)) (typeExpr (if (= (listLength exprs) 1) (optionOr (listHead exprs) (rd/makeAtom "")) (rd/makeList exprs)))] (pair (some (rd/makeList (list (rd/makeAtom pName) typeExpr))) bg.rest))) ((mt t1.kind ((tokLbracket) true) (_ false)) (let [(bg (takeBalancedGroup afterColon)) (exprs (parseTokensToExprList bg.group)) (typeExpr (if (= (listLength exprs) 1) (optionOr (listHead exprs) (rd/makeAtom "")) (rd/makeList exprs)))] (pair (some (rd/makeList (list (rd/makeAtom pName) typeExpr))) bg.rest))) (else (let [(typeExpr (desugarDot t1.rawText))] (pair (some (rd/makeList (list (rd/makeAtom pName) typeExpr))) (optionOr (listTail afterColon) (list)))))))))))))))

fn parseParamsStep toks: (List ilx/IndentToken) paired: Bool acc: (List rd/SExpr) -> (List rd/SExpr)
  (if (listEmpty? toks) (listReverse acc) (let [(res (parseOneParamToks toks paired))] (mt (pairFirst res) ((some p) (let [(rem (pairSecond res))] (if (= (listLength rem) (listLength toks)) (listReverse (cons p acc)) (parseParamsStep rem paired (cons p acc))))) ((none) (listReverse acc)))))

fn parseParamsVector pToks: (List ilx/IndentToken) -> rd/SExpr
  (let [(cnt (listLength pToks))] (let [(bracketed (and (>= cnt 2) (mt (optionOr (listHead pToks) (ilx/makeIndentToken (ilx/tokSymbol "") "" 1 1)).kind ((tokLbracket) true) (_ false)) (mt (optionOr (listGet pToks (- cnt 1)) (ilx/makeIndentToken (ilx/tokSymbol "") "" 1 1)).kind ((tokRbracket) true) (_ false)))) (cleanToks (if bracketed (stripOuterDelims pToks) pToks))] (rd/makeVect (parseParamsStep cleanToks bracketed (list)))))

fn parseFnParamsAndReturn toks: (List ilx/IndentToken) -> FnSignature
  (let [(isBangFirst (mt (listHead toks) ((some t) (= t.rawText "!")) ((none) false))) (nameTok (if isBangFirst (listHead (optionOr (listTail toks) (list))) (listHead toks))) (fnName (mt nameTok ((some t) t.rawText) ((none) "anonymous"))) (afterNameToks (if isBangFirst (optionOr (listTail (optionOr (listTail toks) (list))) (list)) (optionOr (listTail toks) (list)))) (firstAfter (listHead afterNameToks)) (hasEffect (or isBangFirst (mt firstAfter ((some fr) (= fr.rawText "!")) ((none) (stringEndsWith? fnName "!"))))) (paramAndRetToks (if (and (not isBangFirst) hasEffect (some? firstAfter) (= (optionOr firstAfter (ilx/makeIndentToken (ilx/tokSymbol "") "" 1 1)).rawText "!")) (optionOr (listTail afterNameToks) (list)) afterNameToks)) (arrowSplit (splitTokensAtWord paramAndRetToks "->")) (pToks (pairFirst arrowSplit)) (hasArrow (pairSecond (pairSecond arrowSplit))) (afterArrow (pairFirst (pairSecond arrowSplit))) (paramsVect (parseParamsVector pToks)) (docSplit (splitTokensAtWord afterArrow ":d")) (hasDoc (pairSecond (pairSecond docSplit))) (retToks (if hasDoc (pairFirst docSplit) afterArrow)) (docToks (if hasDoc (pairFirst (pairSecond docSplit)) (list))) (docstring (mt (listHead docToks) ((some dt) (some dt.rawText)) ((none) (none)))) (retTypeSexpr (if (not hasArrow) (rd/makeAtom ":inferredUnit") (if (listEmpty? retToks) (rd/makeAtom "Unit") (parseLineTokensToSexpr retToks))))] (FnSignature :name fnName :effect hasEffect :params paramsVect :retType retTypeSexpr :docstring docstring))

fn hasLbrace? toks: (List ilx/IndentToken) -> Bool
  (fold (fn [(acc Bool) (t ilx/IndentToken)] -> Bool (or acc (mt t.kind ((tokLbrace) true) (_ false)))) false toks)

fn takeTokensInsideBraces toks: (List ilx/IndentToken) -> (Pair (List ilx/IndentToken) (List ilx/IndentToken))
  (let [(step (fold (fn [(acc (Pair (List ilx/IndentToken) (Pair (List ilx/IndentToken) (Pair Int64 (Pair Bool Bool))))) (t ilx/IndentToken)] -> (Pair (List ilx/IndentToken) (Pair (List ilx/IndentToken) (Pair Int64 (Pair Bool Bool)))) (let [(inner (pairFirst acc)) (rem (pairFirst (pairSecond acc))) (depth (pairFirst (pairSecond (pairSecond acc)))) (started (pairFirst (pairSecond (pairSecond (pairSecond acc))))) (done (pairSecond (pairSecond (pairSecond (pairSecond acc)))))] (if done (pair inner (pair (cons t rem) (pair depth (pair started true)))) (mt t.kind ((tokLbrace) (if (not started) (pair inner (pair rem (pair 1 (pair true false)))) (pair (cons t inner) (pair rem (pair (+ depth 1) (pair true false)))))) ((tokRbrace) (if (<= depth 1) (pair inner (pair rem (pair 0 (pair true true)))) (pair (cons t inner) (pair rem (pair (- depth 1) (pair true false)))))) (_ (if started (pair (cons t inner) (pair rem (pair depth (pair true false)))) (pair inner (pair rem (pair depth (pair false false)))))))))) (pair (list) (pair (list) (pair 0 (pair false false)))) toks))] (pair (listReverse (pairFirst step)) (listReverse (pairFirst (pairSecond step)))))

fn collectBlockTokens toks: (List ilx/IndentToken) targetLevel: Int64 -> (Pair (List ilx/IndentToken) (List ilx/IndentToken))
  (let [(step (fold (fn [(acc (Pair (List ilx/IndentToken) (Pair (List ilx/IndentToken) Bool))) (t ilx/IndentToken)] -> (Pair (List ilx/IndentToken) (Pair (List ilx/IndentToken) Bool)) (let [(inner (pairFirst acc)) (rem (pairFirst (pairSecond acc))) (done (pairSecond (pairSecond acc)))] (if done (pair inner (pair (cons t rem) true)) (mt t.kind ((tokDedent l) (if (<= l targetLevel) (pair inner (pair (cons t rem) true)) (pair (cons t inner) (pair rem false)))) ((tokEof) (pair inner (pair rem true))) (_ (pair (cons t inner) (pair rem false))))))) (pair (list) (pair (list) false)) toks))] (pair (listReverse (pairFirst step)) (listReverse (pairFirst (pairSecond step)))))

fn splitTokensByLines toks: (List ilx/IndentToken) -> (List (List ilx/IndentToken))
  (let [(step (fold (fn [(acc (Pair (List (List ilx/IndentToken)) (List ilx/IndentToken))) (t ilx/IndentToken)] -> (Pair (List (List ilx/IndentToken)) (List ilx/IndentToken)) (let [(lines (pairFirst acc)) (curLine (pairSecond acc))] (mt t.kind ((tokNewline) (if (listEmpty? curLine) acc (pair (cons (listReverse curLine) lines) (list)))) ((tokIndent _) acc) ((tokDedent _) acc) ((tokEof) (if (listEmpty? curLine) acc (pair (cons (listReverse curLine) lines) (list)))) (_ (pair lines (cons t curLine)))))) (pair (list) (list)) toks))] (let [(lines (pairFirst step)) (curLine (pairSecond step))] (if (listEmpty? curLine) (listReverse lines) (listReverse (cons (listReverse curLine) lines)))))

fn schemaField name: String ty: rd/SExpr -> rd/SExpr
  (rd/makeList (list (rd/makeAtom ":field") (rd/makeAtom name) ty (rd/makeAtom "\"\"")))

fn withFieldDoc fields: (List rd/SExpr) doc: String -> (List rd/SExpr)
  (mt (listHead fields)
    ((none) fields)
    ((some lastF) (let [(fItems (rd/sexprToList lastF))]
                    (if (>= (listLength fItems) 3)
                      (cons (rd/makeList (list (rd/makeAtom ":field") (optionOr (listGet fItems 1) (rd/makeAtom "")) (optionOr (listGet fItems 2) (rd/makeAtom "")) (rd/makeAtom (str "\"" doc "\"")))) (optionOr (listTail fields) (list)))
                      fields))))

fn schemaFieldsLoop toks: (List ilx/IndentToken) fields: (List rd/SExpr) pending: (Option String) -> (List rd/SExpr)
  (mt (listHead toks)
    ((none) (listReverse fields))
    ((some t) (let [(rest (optionOr (listTail toks) (list)))
                    (opens (mt t.kind ((ilx/tokLparen) true) ((ilx/tokLbracket) true) (_ false)))]
                (mt t.kind
                  ((ilx/tokSymbol s) (mt pending
                                   ((none) (schemaFieldsLoop rest fields (some s)))
                                   ((some fName) (schemaFieldsLoop rest (cons (schemaField fName (desugarDot s)) fields) (none)))))
                  ((ilx/tokString s) (if (listEmpty? fields) (schemaFieldsLoop rest fields pending) (schemaFieldsLoop rest (withFieldDoc fields s) (none))))
                  (_ (mt pending
                       ((some fName) (if opens
                                       (let [(g (takeBalancedGroup toks))
                                             (ty (optionOr (listHead (parseTokensToExprList g.group)) (rd/makeAtom "")))]
                                         (schemaFieldsLoop g.rest (cons (schemaField fName ty) fields) (none)))
                                       (schemaFieldsLoop rest fields pending)))
                       ((none) (schemaFieldsLoop rest fields pending))))))))

fn parseSchemaFieldTokens toks: (List ilx/IndentToken) -> (List rd/SExpr)
  (schemaFieldsLoop toks (list) (none))

fn parseSchemaTopForm cleanToks: (List ilx/IndentToken) -> TopFormResult
  (let [(afterKw (optionOr (listTail cleanToks) (list))) (nameTok (listHead afterKw))] (mt nameTok ((none) (TopFormResult :rest (list) :form (none) :kids (list))) ((some nt) (let [(rawName nt.rawText) (schemaName (if (stringEndsWith? rawName ":") (optionOr (stringSlice rawName 0 (- (stringLength rawName) 1)) rawName) rawName)) (afterName (optionOr (listTail afterKw) (list)))] (if (hasLbrace? afterName) (let [(braceRes (takeTokensInsideBraces afterName)) (innerToks (pairFirst braceRes)) (remToks (pairSecond braceRes)) (fields (parseSchemaFieldTokens innerToks)) (schemaSexpr (rd/makeList (listAppend (list (rd/makeAtom "schema") (rd/makeAtom schemaName)) fields)))] (TopFormResult :rest remToks :form (some schemaSexpr) :kids (list))) (let [(lineSplit (takeUntilLineEnd afterName)) (afterLine (pairSecond lineSplit)) (inlineToks (filter (fn [(t ilx/IndentToken)] -> Bool (!= t.rawText ":")) (pairFirst lineSplit)))] (if (not (listEmpty? inlineToks)) (let [(fields (parseSchemaFieldTokens inlineToks)) (schemaSexpr (rd/makeList (listAppend (list (rd/makeAtom "schema") (rd/makeAtom schemaName)) fields)))] (TopFormResult :rest afterLine :form (some schemaSexpr) :kids (list))) (mt (listHead afterLine) ((some indTok) (mt indTok.kind ((tokIndent lvl) (let [(blockRes (collectBlockTokens (optionOr (listTail afterLine) (list)) lvl)) (blockToks (pairFirst blockRes)) (remToks (pairSecond blockRes)) (fields (parseSchemaFieldTokens blockToks)) (schemaSexpr (rd/makeList (listAppend (list (rd/makeAtom "schema") (rd/makeAtom schemaName)) fields)))] (TopFormResult :rest remToks :form (some schemaSexpr) :kids (list)))) (_ (let [(schemaSexpr (rd/makeList (list (rd/makeAtom "schema") (rd/makeAtom schemaName))))] (TopFormResult :rest afterLine :form (some schemaSexpr) :kids (list)))))) ((none) (let [(schemaSexpr (rd/makeList (list (rd/makeAtom "schema") (rd/makeAtom schemaName))))] (TopFormResult :rest (list) :form (some schemaSexpr) :kids (list))))))))))))

fn docToken? t: ilx/IndentToken -> Bool
  (mt t.kind ((tokString _) true) (_ false))

fn parseEnumCaseLine lt: (List ilx/IndentToken) -> rd/SExpr
  (let [(isParen (mt (listHead lt) ((some t) (mt t.kind ((tokLparen) true) (_ false))) ((none) false)))
        (grouped (if isParen (takeBalancedGroup lt) (GroupResult :group lt :rest (list))))
        (inner (filter (fn [(t ilx/IndentToken)] -> Bool (not (docToken? t))) (if isParen (stripOuterDelims grouped.group) grouped.group)))
        (docToks (filter docToken? (if isParen grouped.rest lt)))
        (doc (mt (listHead docToks) ((some d) (mt d.kind ((tokString text) (str "\"" (escapeStringContent text) "\"")) (_ "\"\""))) ((none) "\"\"")))]
    (mt (listHead inner)
      ((none) (rd/makeList (list (rd/makeAtom ":case") (rd/makeAtom "Unknown") (rd/makeVect (list)) (rd/makeAtom "\"\""))))
      ((some vt) (rd/makeList (list (rd/makeAtom ":case") (rd/makeAtom vt.rawText) (rd/makeVect (parseParamsStep (optionOr (listTail inner) (list)) false (list))) (rd/makeAtom doc))))))

fn inlineDocFrom toks: (List ilx/IndentToken) -> (Pair String (List ilx/IndentToken))
  (mt (listHead toks)
    ((none) (pair "\"\"" toks))
    ((some d)
     (if (docToken? d)
       (mt d.kind
         ((tokString text) (pair (str "\"" (escapeStringContent text) "\"") (optionOr (listTail toks) (list))))
         (_ (pair "\"\"" toks)))
       (pair "\"\"" toks))))

fn inlineEnumCaseGroup lt: (List ilx/IndentToken) -> (Pair rd/SExpr (List ilx/IndentToken))
  (let [(isParen (mt (listHead lt) ((some t) (mt t.kind ((tokLparen) true) (_ false))) ((none) false)))]
    (if isParen
      (let [(grouped (takeBalancedGroup lt))
            (inner (stripOuterDelims grouped.group))
            (nameTok (listHead inner))
            (fields (optionOr (listTail inner) (list)))
            (caseName (mt nameTok ((some vt) vt.rawText) ((none) "Unknown")))
            (docRes (inlineDocFrom grouped.rest))
            (doc (pairFirst docRes))
            (rest2 (pairSecond docRes))
            (isCaseForm (mt nameTok ((some vt) (mt vt.kind ((tokKeyword k) (or (= k ":case") (= k ":c"))) (_ false))) ((none) false)))]
        (if isCaseForm
          (pair (optionOr (listHead (parseTokensToExprList grouped.group)) (rd/makeList (list))) grouped.rest)
          (pair (rd/makeList (list (rd/makeAtom ":case") (rd/makeAtom caseName) (rd/makeVect (parseParamsStep fields false (list))) (rd/makeAtom doc))) rest2)))
      (mt (listHead lt)
        ((none) (pair (rd/makeList (list (rd/makeAtom ":case") (rd/makeAtom "Unknown") (rd/makeVect (list)) (rd/makeAtom "\"\""))) (list)))
        ((some t0)
         (let [(docRes (inlineDocFrom (optionOr (listTail lt) (list))))
               (doc (pairFirst docRes))
               (rest2 (pairSecond docRes))]
           (pair (rd/makeList (list (rd/makeAtom ":case") (rd/makeAtom t0.rawText) (rd/makeVect (list)) (rd/makeAtom doc))) rest2))))))

fn inlineEnumCasesLoop toks: (List ilx/IndentToken) acc: (List rd/SExpr) -> (List rd/SExpr)
  (mt (listHead toks)
    ((none) (listReverse acc))
    ((some t0)
     (mt t0.kind
       ((tokColon) (inlineEnumCasesLoop (optionOr (listTail toks) (list)) acc))
       (_ (let [(res (inlineEnumCaseGroup toks)) (rem (pairSecond res))]
            (if (= (listLength rem) (listLength toks))
              (listReverse acc)
              (inlineEnumCasesLoop rem (cons (pairFirst res) acc))))))))

fn inlineEnumCases toks: (List ilx/IndentToken) -> (List rd/SExpr)
  (inlineEnumCasesLoop toks (list))

fn parseEnumTopForm cleanToks: (List ilx/IndentToken) -> TopFormResult
  (let [(afterKw (optionOr (listTail cleanToks) (list))) (nameTok (listHead afterKw))] (mt nameTok ((none) (TopFormResult :rest (list) :form (none) :kids (list))) ((some nt) (let [(rawName nt.rawText) (enumName (if (stringEndsWith? rawName ":") (optionOr (stringSlice rawName 0 (- (stringLength rawName) 1)) rawName) rawName)) (afterName (optionOr (listTail afterKw) (list)))] (if (hasLbrace? afterName) (let [(braceRes (takeTokensInsideBraces afterName)) (innerToks (pairFirst braceRes)) (remToks (pairSecond braceRes)) (symbols (filter (fn [(t ilx/IndentToken)] -> Bool (mt t.kind ((tokSymbol _) true) (_ false))) innerToks)) (cases (map (fn [(t ilx/IndentToken)] -> rd/SExpr (rd/makeList (list (rd/makeAtom ":case") (rd/makeAtom t.rawText) (rd/makeVect (list)) (rd/makeAtom "\"\"")))) symbols)) (enumSexpr (rd/makeList (listAppend (list (rd/makeAtom "enum") (rd/makeAtom enumName)) cases)))] (TopFormResult :rest remToks :form (some enumSexpr) :kids (list))) (let [(lineSplit (takeUntilLineEnd afterName)) (afterLine (pairSecond lineSplit)) (inlineToks (filter (fn [(t ilx/IndentToken)] -> Bool (!= t.rawText ":")) (pairFirst lineSplit)))] (if (not (listEmpty? inlineToks)) (let [(cases (inlineEnumCases (pairFirst lineSplit))) (enumSexpr (rd/makeList (listAppend (list (rd/makeAtom "enum") (rd/makeAtom enumName)) cases)))] (TopFormResult :rest afterLine :form (some enumSexpr) :kids (list))) (mt (listHead afterLine) ((some indTok) (mt indTok.kind ((tokIndent lvl) (let [(blockRes (collectBlockTokens (optionOr (listTail afterLine) (list)) lvl)) (blockToks (pairFirst blockRes)) (remToks (pairSecond blockRes)) (lines (splitTokensByLines blockToks)) (cases (map parseEnumCaseLine lines)) (enumSexpr (rd/makeList (listAppend (list (rd/makeAtom "enum") (rd/makeAtom enumName)) cases)))] (TopFormResult :rest remToks :form (some enumSexpr) :kids (list)))) (_ (let [(enumSexpr (rd/makeList (list (rd/makeAtom "enum") (rd/makeAtom enumName))))] (TopFormResult :rest afterLine :form (some enumSexpr) :kids (list)))))) ((none) (let [(enumSexpr (rd/makeList (list (rd/makeAtom "enum") (rd/makeAtom enumName))))] (TopFormResult :rest (list) :form (some enumSexpr) :kids (list))))))))))))

(schema TopFormResult (:f rest (List ilx/IndentToken)) (:f form (Option rd/SExpr)) (:f kids (List (Pair Int64 Int64))))

fn parseIfTopForm toks: (List ilx/IndentToken) -> TopFormResult
  (let [(lineSplit (takeUntilLineEnd toks)) (lineToks (pairFirst lineSplit)) (afterLine (pairSecond lineSplit)) (condToks (filter (fn [(t ilx/IndentToken)] -> Bool (and (!= t.rawText "if") (!= t.rawText ":"))) lineToks)) (condExpr (parseLineTokensToSexpr condToks))] (mt (listHead afterLine) ((some indTok) (mt indTok.kind ((tokIndent lvl) (let [(thenBlockRes (parseIndentedBlock (optionOr (listTail afterLine) (list)) lvl)) (thenForms thenBlockRes.forms) (afterThen thenBlockRes.rest) (thenExpr (if (= (listLength thenForms) 1) (optionOr (listHead thenForms) (rd/makeAtom "")) (rd/makeList (cons (rd/makeAtom "do") thenForms)))) (cleanAfterThen (skipNewlines afterThen))] (mt (listHead cleanAfterThen) ((some elseTok) (if (= elseTok.rawText "else") (let [(elseSplit (takeUntilLineEnd cleanAfterThen)) (elseLineToks (pairFirst elseSplit)) (afterElseLine (pairSecond elseSplit)) (elseInline (filter (fn [(t ilx/IndentToken)] -> Bool (and (!= t.rawText "else") (!= t.rawText ":"))) elseLineToks))] (if (not (listEmpty? elseInline)) (let [(elseExpr (parseLineTokensToSexpr elseInline)) (ifSexpr (rd/makeList (list (rd/makeAtom "if") condExpr thenExpr elseExpr)))] (TopFormResult :rest afterElseLine :form (some ifSexpr) :kids (list))) (mt (listHead afterElseLine) ((some nextElseT) (mt nextElseT.kind ((tokIndent elseLvl) (let [(elseBlockRes (parseIndentedBlock (optionOr (listTail afterElseLine) (list)) elseLvl)) (elseForms elseBlockRes.forms) (remAfterElse elseBlockRes.rest) (elseExpr (if (= (listLength elseForms) 1) (optionOr (listHead elseForms) (rd/makeAtom "")) (rd/makeList (cons (rd/makeAtom "do") elseForms)))) (ifSexpr (rd/makeList (list (rd/makeAtom "if") condExpr thenExpr elseExpr)))] (TopFormResult :rest remAfterElse :form (some ifSexpr) :kids (list)))) (_ (let [(ifSexpr (rd/makeList (list (rd/makeAtom "if") condExpr thenExpr (rd/makeAtom "nil"))))] (TopFormResult :rest afterElseLine :form (some ifSexpr) :kids (list)))))) ((none) (let [(ifSexpr (rd/makeList (list (rd/makeAtom "if") condExpr thenExpr (rd/makeAtom "nil"))))] (TopFormResult :rest (list) :form (some ifSexpr) :kids (list))))))) (let [(ifSexpr (rd/makeList (list (rd/makeAtom "if") condExpr thenExpr (rd/makeAtom "nil"))))] (TopFormResult :rest afterThen :form (some ifSexpr) :kids (list))))) ((none) (let [(ifSexpr (rd/makeList (list (rd/makeAtom "if") condExpr thenExpr (rd/makeAtom "nil"))))] (TopFormResult :rest (list) :form (some ifSexpr) :kids (list))))))) (_ (let [(ifSexpr (rd/makeList (list (rd/makeAtom "if") condExpr (rd/makeAtom "nil") (rd/makeAtom "nil"))))] (TopFormResult :rest afterLine :form (some ifSexpr) :kids (list)))))) ((none) (let [(ifSexpr (rd/makeList (list (rd/makeAtom "if") condExpr (rd/makeAtom "nil") (rd/makeAtom "nil"))))] (TopFormResult :rest (list) :form (some ifSexpr) :kids (list))))))

fn extractBodyDoc headerDoc: (Option String) bodyForms: (List rd/SExpr) -> (Pair (List rd/SExpr) (List rd/SExpr))
  (mt headerDoc ((some d) (let [(dAtom (if (stringStartsWith? d "\"") (rd/makeAtom d) (rd/makeAtom (str "\"" d "\""))))] (pair (list (rd/makeAtom ":d") dAtom) bodyForms))) ((none) (mt (listHead bodyForms) ((some firstForm) (mt firstForm ((sexprList fItems) (mt (listHead fItems) ((some hAtom) (let [(hName (rd/sexprHead hAtom))] (if (or (= hName ":d") (= hName ":doc")) (let [(docVal (optionOr (listGet fItems 1) (rd/makeAtom "\"\""))) (remForms (optionOr (listTail bodyForms) (list)))] (pair (list (rd/makeAtom ":d") docVal) remForms)) (pair (list) bodyForms)))) ((none) (pair (list) bodyForms)))) ((sexprAtom aName) (if (or (= aName ":d") (= aName ":doc")) (let [(tailForms (optionOr (listTail bodyForms) (list))) (docVal (optionOr (listHead tailForms) (rd/makeAtom "\"\""))) (remForms (optionOr (listTail tailForms) (list)))] (pair (list (rd/makeAtom ":d") docVal) remForms)) (pair (list) bodyForms))) (_ (pair (list) bodyForms)))) ((none) (pair (list) (list))))))

fn parseTopForm toks: (List ilx/IndentToken) -> TopFormResult
  (let [(cleanToks (skipNewlines toks))] (mt (listHead cleanToks) ((none) (TopFormResult :rest (list) :form (none) :kids (list))) ((some t) (mt t.kind ((tokEof) (TopFormResult :rest (list) :form (none) :kids (list))) ((tokSymbol s) (cond ((= s "fn") (let [(lineSplit (takeUntilLineEnd (optionOr (listTail cleanToks) (list)))) (headerToks (pairFirst lineSplit)) (afterHeader (pairSecond lineSplit)) (sig (parseFnParamsAndReturn headerToks))] (mt (listHead afterHeader) ((some indTok) (mt indTok.kind ((tokIndent lvl) (let [(blockRes (parseIndentedBlock (optionOr (listTail afterHeader) (list)) lvl)) (rawBodyForms blockRes.forms) (remToks blockRes.rest) (docRes (extractBodyDoc sig.docstring rawBodyForms)) (finalDocList (pairFirst docRes)) (finalBodyForms (pairSecond docRes)) (effList (if sig.effect (list (rd/makeAtom "!")) (list))) (fnParts (listAppend (listAppend (list (rd/makeAtom "fn") (rd/makeAtom sig.name)) effList) (listAppend (list sig.params (rd/makeAtom "->") sig.retType) (listAppend finalDocList finalBodyForms)))) (fnSexpr (rd/makeList fnParts))] (TopFormResult :rest remToks :form (some fnSexpr) :kids blockRes.poses))) (_ (let [(effList (if sig.effect (list (rd/makeAtom "!")) (list))) (docList (mt sig.docstring ((some d) (list (rd/makeAtom ":d") (rd/makeAtom (if (stringStartsWith? d "\"") d (str "\"" d "\""))))) ((none) (list)))) (fnParts (listAppend (listAppend (list (rd/makeAtom "fn") (rd/makeAtom sig.name)) effList) (listAppend (list sig.params (rd/makeAtom "->") sig.retType) docList))) (fnSexpr (rd/makeList fnParts))] (TopFormResult :rest afterHeader :form (some fnSexpr) :kids (list)))))) ((none) (let [(effList (if sig.effect (list (rd/makeAtom "!")) (list))) (docList (mt sig.docstring ((some d) (list (rd/makeAtom ":d") (rd/makeAtom (if (stringStartsWith? d "\"") d (str "\"" d "\""))))) ((none) (list)))) (fnParts (listAppend (listAppend (list (rd/makeAtom "fn") (rd/makeAtom sig.name)) effList) (listAppend (list sig.params (rd/makeAtom "->") sig.retType) docList))) (fnSexpr (rd/makeList fnParts))] (TopFormResult :rest (list) :form (some fnSexpr) :kids (list))))))) ((= s "match") (let [(lineSplit (takeUntilLineEnd (optionOr (listTail cleanToks) (list)))) (targetToks (pairFirst lineSplit)) (afterHeader (pairSecond lineSplit)) (targetSexpr (parseLineTokensToSexpr targetToks))] (mt (listHead afterHeader) ((some indTok) (mt indTok.kind ((tokIndent lvl) (let [(matchRes (parseMatchArms (optionOr (listTail afterHeader) (list)) lvl)) (arms matchRes.arms) (remToks matchRes.rest)] (let [(matchSexpr (rd/makeList (list (rd/makeAtom "match") targetSexpr (rd/makeList arms))))] (TopFormResult :rest remToks :form (some matchSexpr) :kids (list))))) (_ (let [(matchSexpr (rd/makeList (list (rd/makeAtom "match") targetSexpr)))] (TopFormResult :rest afterHeader :form (some matchSexpr) :kids (list)))))) ((none) (let [(matchSexpr (rd/makeList (list (rd/makeAtom "match") targetSexpr)))] (TopFormResult :rest (list) :form (some matchSexpr) :kids (list))))))) ((and (= s "let") (isLetDestructureLine? cleanToks)) (let [(lineSplit (takeUntilLineEnd cleanToks)) (lineToks (pairFirst lineSplit)) (afterLine (pairSecond lineSplit)) (info (parseLetLineInfo lineToks))] (if info.hasInlineBody (let [(letSexpr (desugarDestructuring info.isRecord info.vars info.expr info.inlineBody))] (TopFormResult :rest afterLine :form (some letSexpr) :kids (list))) (mt (listHead afterLine) ((some nextT) (mt nextT.kind ((tokIndent lvl) (let [(blockRes (parseIndentedBlock (optionOr (listTail afterLine) (list)) lvl)) (bodyForms blockRes.forms) (remToks blockRes.rest) (letSexpr (desugarDestructuring info.isRecord info.vars info.expr bodyForms))] (TopFormResult :rest remToks :form (some letSexpr) :kids (list)))) (_ (let [(letSexpr (desugarDestructuring info.isRecord info.vars info.expr (list)))] (TopFormResult :rest afterLine :form (some letSexpr) :kids (list)))))) ((none) (let [(letSexpr (desugarDestructuring info.isRecord info.vars info.expr (list)))] (TopFormResult :rest afterLine :form (some letSexpr) :kids (list)))))))) ((or (= s "schema") (= s "defschema")) (parseSchemaTopForm cleanToks)) ((or (= s "enum") (= s "defenum")) (parseEnumTopForm cleanToks)) ((= s "if") (parseIfTopForm cleanToks)) (else (let [(lineSplit (takeUntilLineEnd cleanToks)) (lineToks (pairFirst lineSplit)) (afterLine (pairSecond lineSplit)) (lineSexpr (parseLineTokensToSexpr lineToks))] (TopFormResult :rest afterLine :form (some lineSexpr) :kids (list)))))) (_ (let [(lineSplit (takeUntilLineEnd cleanToks)) (lineToks (pairFirst lineSplit)) (afterLine (pairSecond lineSplit)) (lineSexpr (parseLineTokensToSexpr lineToks))] (TopFormResult :rest afterLine :form (some lineSexpr) :kids (list))))))))

fn topFormsLoop toks: (List ilx/IndentToken) collected: (List rd/SExpr) -> (List rd/SExpr)
  (if (listEmpty? toks) (listReverse collected) (let [(topRes (parseTopForm toks))] (mt topRes.form ((some f) (let [(rem topRes.rest)] (if (listEmpty? rem) (listReverse (cons f collected)) (let [(safeRem (if (= (listLength rem) (listLength toks)) (optionOr (listTail toks) (list)) rem))] (topFormsLoop safeRem (cons f collected)))))) ((none) (let [(rem topRes.rest)] (if (listEmpty? rem) (listReverse collected) (let [(safeRem (if (= (listLength rem) (listLength toks)) (optionOr (listTail toks) (list)) rem))] (topFormsLoop safeRem collected))))))))

(schema IndentForm (:f expr rd/SExpr) (:f line Int64) (:f col Int64) (:f kids (List (Pair Int64 Int64))))

fn topFormsPosLoop toks: (List ilx/IndentToken) collected: (List IndentForm) -> (List IndentForm)
  (let [(clean (skipNewlines toks))] (mt (listHead clean) ((none) (listReverse collected)) ((some t0) (let [(topRes (parseTopForm clean)) (rem topRes.rest) (next (mt topRes.form ((some f) (cons (IndentForm :expr f :line t0.line :col t0.col :kids topRes.kids) collected)) ((none) collected)))] (if (listEmpty? rem) (listReverse next) (topFormsPosLoop (if (= (listLength rem) (listLength clean)) (optionOr (listTail clean) (list)) rem) next))))))

fn parseIndentedFormsPos src: String -> (Result (List IndentForm) IndentError)
  (mt (lexIndented src) ((err e) (err e)) ((ok toks) (ok (topFormsPosLoop toks (list)))))

(schema IndentError (:f msg String) (:f line Int64) (:f col Int64))

(schema DelimScan (:f open (List ilx/IndentToken)) (:f fail (Option IndentError)))

fn closerOf t: ilx/IndentToken -> String
  (mt t.kind ((ilx/tokLparen) ")") ((ilx/tokLbracket) "]") (_ "}"))

fn closeDelim st: DelimScan t: ilx/IndentToken -> DelimScan
  (mt (listHead st.open)
    ((none) (DelimScan :open (list) :fail (some (IndentError :msg (str "unmatched '" t.rawText "'") :line t.line :col t.col))))
    ((some o) (if (= (closerOf o) t.rawText)
      (DelimScan :open (optionOr (listTail st.open) (list)) :fail (none))
      (with st :fail (some (IndentError :msg (str "'" t.rawText "' closes '" o.rawText "' opened at " (stringFromInt64 o.line) ":" (stringFromInt64 o.col)) :line t.line :col t.col))))))

fn delimStep st: DelimScan t: ilx/IndentToken -> DelimScan
  (if (some? st.fail) st
    (mt t.kind
      ((ilx/tokLparen) (DelimScan :open (cons t st.open) :fail (none)))
      ((ilx/tokLbracket) (DelimScan :open (cons t st.open) :fail (none)))
      ((ilx/tokLbrace) (DelimScan :open (cons t st.open) :fail (none)))
      ((ilx/tokRparen) (closeDelim st t))
      ((ilx/tokRbracket) (closeDelim st t))
      ((ilx/tokRbrace) (closeDelim st t))
      (_ st)))

fn delimError toks: (List ilx/IndentToken) -> (Option IndentError)
  (let [(st (fold delimStep (DelimScan :open (list) :fail (none)) toks))]
    (mt st.fail
      ((some e) (some e))
      ((none) (mt (listHead st.open) ((some o) (some (IndentError :msg (str "unclosed '" o.rawText "' at end of file") :line o.line :col o.col))) ((none) (none))))))

(schema HeaderSegment (:f origLine Int64) (:f joinedStart Int64) (:f colOffset Int64))

fn leadingSpaceCount line: String -> Int64
  (pairFirst (fold (fn [(acc (Pair Int64 Bool)) (ch String)] -> (Pair Int64 Bool)
                     (let [(n (pairFirst acc)) (stopped (pairSecond acc))]
                       (if stopped acc (if (= ch " ") (pair (+ n 1) false) (pair n true)))))
                   (pair 0 false) (stringChars line)))

fn buildHeaderSegmentsLoop headerLineNum: Int64 accLen: Int64 lineOffset: Int64 lines: (List String) -> (List HeaderSegment)
  (mt (listHead lines)
    ((none) (list))
    ((some line)
     (let [(rest (optionOr (listTail lines) (list)))
           (clean (fh/stripCrLine line))
           (trimmed (stringTrim clean))
           (lead (leadingSpaceCount clean))
           (joinedStart (+ accLen 2))
           (seg (HeaderSegment :origLine (+ headerLineNum lineOffset) :joinedStart joinedStart :colOffset (- (+ lead 1) joinedStart)))
           (newAccLen (+ accLen (+ 1 (stringLength trimmed))))]
       (cons seg (buildHeaderSegmentsLoop headerLineNum newAccLen (+ lineOffset 1) rest)))))

fn buildHeaderSegments headerLineNum: Int64 headerText: String consumed: (List String) -> (List HeaderSegment)
  (cons (HeaderSegment :origLine headerLineNum :joinedStart 1 :colOffset 0)
        (buildHeaderSegmentsLoop headerLineNum (stringLength headerText) 1 consumed))

fn remapCol segments: (List HeaderSegment) joinedCol: Int64 -> (Pair Int64 Int64)
  (let [(chosen (fold (fn [(acc HeaderSegment) (seg HeaderSegment)] -> HeaderSegment
                         (if (<= seg.joinedStart joinedCol) seg acc))
                       (optionOr (listHead segments) (HeaderSegment :origLine 0 :joinedStart 1 :colOffset 0))
                       segments))]
    (pair chosen.origLine (+ joinedCol chosen.colOffset)))

fn remapErrorPos table: (List (Pair Int64 (List HeaderSegment))) line: Int64 col: Int64 -> (Pair Int64 Int64)
  (mt (listHead (filter (fn [(e (Pair Int64 (List HeaderSegment)))] -> Bool (= (pairFirst e) line)) table))
    ((none) (pair line col))
    ((some e) (remapCol (pairSecond e) col)))


fn fnHeaderScanLine line: String inStr: Bool esc: Bool -> (Pair Bool Bool)
  (fold (fn [(acc (Pair Bool Bool)) (ch String)] -> (Pair Bool Bool)
          (let [(st (pairFirst acc)) (es (pairSecond acc))]
            (if st
              (cond
                (es (pair st false))
                ((= ch "\\") (pair st true))
                ((= ch "\"") (pair false false))
                (else (pair st false)))
              (if (= ch "\"") (pair true false) (pair st false)))))
        (pair inStr esc) (stringChars line))

fn fnHeaderStringFlagsLoop lines: (List String) inStr: Bool esc: Bool -> (List Bool)
  (mt (listHead lines)
    ((none) (list))
    ((some line)
     (let [(rest (optionOr (listTail lines) (list)))
           (startFlag inStr)
           (next (fnHeaderScanLine line inStr esc))
           (nextInStr (pairFirst next))
           (nextEsc (pairSecond next))]
       (cons startFlag (fnHeaderStringFlagsLoop rest nextInStr nextEsc)))))

fn fnHeaderStringFlags src: String -> (List Bool)
  (fnHeaderStringFlagsLoop (stringSplit src "\n") false false)

fn takeNonStringLines pairs: (List (Pair String Bool)) -> (List String)
  (mt (listHead pairs)
    ((none) (list))
    ((some p) (if (pairSecond p) (list) (cons (pairFirst p) (takeNonStringLines (optionOr (listTail pairs) (list)))))))

fn joinFnHeaderContinuationsLoop pairs: (List (Pair String Bool)) lineNum: Int64 -> (Pair (List String) (List (Pair Int64 (List HeaderSegment))))
  (mt (listHead pairs)
    ((none) (pair (list) (list)))
    ((some p)
     (let [(line (pairFirst p)) (insideStr (pairSecond p)) (rest (optionOr (listTail pairs) (list)))]
       (if (and (not insideStr) (and (or (stringStartsWith? line "fn ") (stringStartsWith? line "fn!")) (not (fh/headerArrow? line))))
         (let [(cleanedHeader (fh/stripCrLine line)) (candidateLines (takeNonStringLines rest))]
           (mt (fh/headerJoin cleanedHeader candidateLines 0)
             ((none) (let [(below (joinFnHeaderContinuationsLoop rest (+ lineNum 1)))]
                       (pair (cons line (pairFirst below)) (pairSecond below))))
             ((some j)
              (let [(joinedLine (pairFirst j))
                    (taken (pairSecond j))
                    (consumedTexts (map pairFirst (optionOr (listSlice rest 0 taken) (list))))
                    (segments (buildHeaderSegments lineNum cleanedHeader consumedTexts))
                    (blanks (map (fn [(_ Int64)] -> String "") (range 0 taken)))
                    (remaining (listDrop rest taken))
                    (below (joinFnHeaderContinuationsLoop remaining (+ (+ lineNum 1) taken)))]
                (pair (cons joinedLine (listAppend blanks (pairFirst below)))
                      (cons (pair lineNum segments) (pairSecond below)))))))
         (let [(below (joinFnHeaderContinuationsLoop rest (+ lineNum 1)))]
           (pair (cons line (pairFirst below)) (pairSecond below)))))))

fn joinFnHeaderContinuations src: String -> (Pair String (List (Pair Int64 (List HeaderSegment))))
  (let [(lines (stringSplit src "\n"))
        (flags (fnHeaderStringFlags src))
        (result (joinFnHeaderContinuationsLoop (zip lines flags) 1))]
    (pair (stringJoin (pairFirst result) "\n") (pairSecond result)))

fn lexIndented src: String -> (Result (List ilx/IndentToken) IndentError)
  (let [(joinRes (joinFnHeaderContinuations src))
        (joinedSrc (pairFirst joinRes))
        (segTable (pairSecond joinRes))
        (lexRes (ilx/tokenizeIndented joinedSrc))
        (rawToks (pairFirst lexRes))
        (firstErr (listHead (filter (fn [(d ilx/LexerDiagnostic)] -> Bool (stringStartsWith? d.code "E")) (pairSecond lexRes))))]
    (mt firstErr
      ((some d) (let [(remapped (remapErrorPos segTable d.line d.col))]
                  (err (IndentError :msg d.msg :line (pairFirst remapped) :col (pairSecond remapped)))))
      ((none) (mt (delimError rawToks)
                ((some e) (let [(remapped (remapErrorPos segTable e.line e.col))]
                            (err (IndentError :msg e.msg :line (pairFirst remapped) :col (pairSecond remapped)))))
                ((none) (ok (preprocessTokens rawToks)))))))

fn parseIndentedForms src: String -> (Result (List rd/SExpr) String)
  (mt (lexIndented src) ((err e) (err (str (stringFromInt64 e.line) ":" (stringFromInt64 e.col) ": " e.msg))) ((ok toks) (ok (topFormsLoop toks (list)))))

fn parseIndented src: String -> (Result rd/SExpr String)
  (let [(formsRes (parseIndentedForms src))] (mt formsRes ((ok forms) (mt (listHead forms) ((some f) (ok (displayFunctionParamTypes f))) ((none) (err "No valid indented form parsed from source")))) ((err msg) (err msg))))

fn displayParamType p: rd/SExpr -> rd/SExpr
  (mt p
    ((rd/sexprList items)
     (if (= (listLength items) 2)
       (mt (listGet items 0)
         ((some name)
          (mt (listGet items 1)
            ((some t)
             (mt t
               ((rd/sexprAtom value) (if (stringEmpty? value) (rd/makeList (list name (rd/makeAtom "Any"))) p))
               (_ p)))
            ((none) p)))
         ((none) p))
       p))
    (_ p))

fn displayFunctionParamTypes form: rd/SExpr -> rd/SExpr
  (mt form
    ((rd/sexprList items)
     (if (and (> (listLength items) 2) (or (= (rd/sexprHead form) "fn") (= (rd/sexprHead form) "df")))
       (mt (listGet items 2)
         ((some paramNode)
          (mt paramNode
            ((rd/sexprVect params)
             (rd/makeList (listAppend (optionOr (listSlice items 0 2) (list)) (cons (rd/makeVect (map displayParamType params)) (optionOr (listSlice items 3 (listLength items)) (list))))))
            (_ form)))
         ((none) form))
       form))
    (_ form))

fn dropInferredArrowPair items: (List rd/SExpr) -> (List rd/SExpr)
  (mt (listHead items)
    ((none) (list))
    ((some h)
     (if (and (rd/isAtom? h) (= (rd/sexprHead h) "->"))
       (let [(rest (optionOr (listTail items) (list)))]
         (mt (listHead rest)
           ((none) (list h))
           ((some h2)
            (if (and (rd/isAtom? h2) (= (rd/sexprHead h2) ":inferredUnit"))
              (optionOr (listTail rest) (list))
              items))))
       (cons h (dropInferredArrowPair (optionOr (listTail items) (list)))))))

fn stripInferredUnit form: rd/SExpr -> rd/SExpr
  (if (= (rd/sexprHead form) "fn")
    (mt form ((rd/sexprList items) (rd/makeList (dropInferredArrowPair items))) (_ form))
    form)
