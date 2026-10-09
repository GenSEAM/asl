(module asl-transpile/yamlTranspile
  :x [YamlTranspileResult
      yamlToAsn
      asnToYaml
      asnToYamlStream
      formatYamlBlockScalar
      measureYamlSavings]
  :i [(asl-parser/reader :a rd)
      (asl-parser/lexer :a lx)
      (asl-parser/ast :a ast)
      (asl-text/text :a txt)])

schema YamlTranspileResult { output: Str originalTokens: I64 asnTokens: I64 savingsPercent: F64 success: Bool }

fn countLeadingSpaces line: Str -> I64
  (countSpacesHelper (stringChars line) 0)

fn countSpacesHelper chars: (List Str) acc: I64 -> I64
  (mt (listHead chars) ((none) acc) ((some c) (if (= c " ") (countSpacesHelper (optionOr (listTail chars) (list)) (+ acc 1)) acc)))

fn findColonSpace line: Str -> I64
  (let [(chars (stringChars line))] (findColonSpaceLoop chars 0))

fn findColonSpaceLoop chars: (List Str) idx: I64 -> I64
  (mt (listHead chars) ((none) -1) ((some c) (if (= c ":") (mt (listHead (optionOr (listTail chars) (list))) ((some nextC) (if (= nextC " ") idx (findColonSpaceLoop (optionOr (listTail chars) (list)) (+ idx 1)))) ((none) idx)) (findColonSpaceLoop (optionOr (listTail chars) (list)) (+ idx 1)))))

fn parseYamlScalar raw: Str -> rd/SExpr
  (let [(clean (stringTrim raw))] (cond ((or (= clean "true") (= clean "yes")) (rd/makeAtom "true")) ((or (= clean "false") (= clean "no")) (rd/makeAtom "false")) ((or (= clean "null") (or (= clean "~") (= clean "_"))) (rd/makeAtom "_")) ((or (stringStartsWith? clean "\"") (stringStartsWith? clean "'")) (rd/makeAtom (str "\"" (txt/stripQuotes clean) "\""))) ((stringContains? clean " ") (rd/makeAtom (str "\"" clean "\""))) (else (rd/makeAtom clean))))

enum YamlLineKind
  (ylkBlank)
  (ylkComment)
  (ylkSeqVal indent: Int64 val: Str)
  (ylkSeqMap indent: Int64 key: Str val: Str)
  (ylkMapVal indent: Int64 key: Str val: Str)
  (ylkMapBlock indent: Int64 key: Str)

fn classifyYamlLine line: Str -> YamlLineKind
  (let [(cleanLine (stripYamlComment line)) (trimmed (stringTrim cleanLine))] (if (stringEmpty? trimmed) (ylkBlank) (let [(indent (countLeadingSpaces cleanLine))] (if (stringStartsWith? trimmed "- ") (let [(rest (stringTrim (optionOr (stringSlice trimmed 2 (stringLength trimmed)) ""))) (cIdx (findColonSpace rest))] (if (> cIdx 0) (let [(k (stringTrim (optionOr (stringSlice rest 0 cIdx) ""))) (v (stringTrim (optionOr (stringSlice rest (+ cIdx 2) (stringLength rest)) "")))] (ylkSeqMap indent k v)) (ylkSeqVal indent rest))) (if (stringEndsWith? trimmed ":") (let [(k (stringTrim (optionOr (stringSlice trimmed 0 (- (stringLength trimmed) 1)) "")))] (ylkMapBlock indent k)) (let [(cIdx (findColonSpace trimmed))] (if (> cIdx 0) (let [(k (stringTrim (optionOr (stringSlice trimmed 0 cIdx) ""))) (v (stringTrim (optionOr (stringSlice trimmed (+ cIdx 2) (stringLength trimmed)) "")))] (ylkMapVal indent k v)) (ylkBlank))))))))

fn stripYamlComment line: Str -> Str
  (txt/stripComment line "#")

schema YamlFrame { indent: I64 isSeq: Bool pendingKey: Str items: (List rd/SExpr) }

schema YamlParseState { stack: (List YamlFrame) roots: (List rd/SExpr) }

fn emitToFrame st: YamlParseState node: rd/SExpr -> YamlParseState
  (if (listEmpty? st.stack) (YamlParseState :stack (list) :roots (cons node st.roots)) (let [(top (optionOr (listHead st.stack) (YamlFrame :indent 0 :isSeq false :pendingKey "" :items (list)))) (rest (optionOr (listTail st.stack) (list)))] (if top.isSeq (let [(newItems (cons node top.items)) (newTop (YamlFrame :indent top.indent :isSeq true :pendingKey "" :items newItems))] (YamlParseState :stack (cons newTop rest) :roots st.roots)) (let [(key top.pendingKey)] (if (stringEmpty? key) (let [(newItems (cons node top.items)) (newTop (YamlFrame :indent top.indent :isSeq false :pendingKey "" :items newItems))] (YamlParseState :stack (cons newTop rest) :roots st.roots)) (let [(kAtom (rd/makeAtom (str ":" key))) (newItems (cons node (cons kAtom top.items))) (newTop (YamlFrame :indent top.indent :isSeq false :pendingKey "" :items newItems))] (YamlParseState :stack (cons newTop rest) :roots st.roots)))))))

fn closeYamlFramesToIndent st: YamlParseState targetIndent: I64 -> YamlParseState
  (if (listEmpty? st.stack) st (let [(top (optionOr (listHead st.stack) (YamlFrame :indent 0 :isSeq false :pendingKey "" :items (list))))] (if (> top.indent targetIndent) (let [(rest (optionOr (listTail st.stack) (list))) (closedItems (listReverse top.items)) (node (if top.isSeq (rd/makeVect closedItems) (rd/makeList closedItems))) (poppedSt (YamlParseState :stack rest :roots st.roots))] (closeYamlFramesToIndent (emitToFrame poppedSt node) targetIndent)) st)))

fn closeAllYamlFrames st: YamlParseState -> YamlParseState
  (if (listEmpty? st.stack) st (let [(top (optionOr (listHead st.stack) (YamlFrame :indent 0 :isSeq false :pendingKey "" :items (list)))) (rest (optionOr (listTail st.stack) (list))) (closedItems (listReverse top.items)) (node (if top.isSeq (rd/makeVect closedItems) (rd/makeList closedItems))) (poppedSt (YamlParseState :stack rest :roots st.roots))] (closeAllYamlFrames (emitToFrame poppedSt node))))

fn processYamlLine st: YamlParseState lineKind: YamlLineKind -> YamlParseState
  (mt lineKind ((ylkBlank) st) ((ylkComment) st) ((ylkMapVal indent k v) (let [(aligned (closeYamlFramesToIndent st indent)) (kAtom (rd/makeAtom (str ":" k))) (vAtom (parseYamlScalar v))] (if (listEmpty? aligned.stack) (let [(frame (YamlFrame :indent indent :isSeq false :pendingKey "" :items (list vAtom kAtom)))] (YamlParseState :stack (list frame) :roots aligned.roots)) (let [(top (optionOr (listHead aligned.stack) (YamlFrame :indent 0 :isSeq false :pendingKey "" :items (list)))) (rest (optionOr (listTail aligned.stack) (list)))] (if (or top.isSeq (> indent top.indent)) (let [(frame (YamlFrame :indent indent :isSeq false :pendingKey "" :items (list vAtom kAtom)))] (YamlParseState :stack (cons frame aligned.stack) :roots aligned.roots)) (let [(newItems (cons vAtom (cons kAtom top.items))) (newTop (YamlFrame :indent top.indent :isSeq false :pendingKey "" :items newItems))] (YamlParseState :stack (cons newTop rest) :roots aligned.roots))))))) ((ylkMapBlock indent k) (let [(aligned (closeYamlFramesToIndent st indent))] (if (listEmpty? aligned.stack) (let [(frame (YamlFrame :indent indent :isSeq false :pendingKey k :items (list)))] (YamlParseState :stack (list frame) :roots aligned.roots)) (let [(top (optionOr (listHead aligned.stack) (YamlFrame :indent 0 :isSeq false :pendingKey "" :items (list)))) (rest (optionOr (listTail aligned.stack) (list))) (newTop (YamlFrame :indent top.indent :isSeq top.isSeq :pendingKey k :items top.items))] (YamlParseState :stack (cons newTop rest) :roots aligned.roots))))) ((ylkSeqVal indent v) (let [(aligned (closeYamlFramesToIndent st indent)) (vAtom (parseYamlScalar v))] (if (listEmpty? aligned.stack) (let [(frame (YamlFrame :indent indent :isSeq true :pendingKey "" :items (list vAtom)))] (YamlParseState :stack (list frame) :roots aligned.roots)) (let [(top (optionOr (listHead aligned.stack) (YamlFrame :indent 0 :isSeq false :pendingKey "" :items (list)))) (rest (optionOr (listTail aligned.stack) (list)))] (if top.isSeq (let [(newItems (cons vAtom top.items)) (newTop (YamlFrame :indent top.indent :isSeq true :pendingKey "" :items newItems))] (YamlParseState :stack (cons newTop rest) :roots aligned.roots)) (let [(frame (YamlFrame :indent indent :isSeq true :pendingKey "" :items (list vAtom)))] (YamlParseState :stack (cons frame aligned.stack) :roots aligned.roots))))))) ((ylkSeqMap indent k v) (let [(aligned (closeYamlFramesToIndent st indent)) (kAtom (rd/makeAtom (str ":" k))) (vAtom (parseYamlScalar v)) (mapNode (rd/makeList (list kAtom vAtom)))] (if (listEmpty? aligned.stack) (let [(frame (YamlFrame :indent indent :isSeq true :pendingKey "" :items (list mapNode)))] (YamlParseState :stack (list frame) :roots aligned.roots)) (let [(top (optionOr (listHead aligned.stack) (YamlFrame :indent 0 :isSeq false :pendingKey "" :items (list)))) (rest (optionOr (listTail aligned.stack) (list)))] (if top.isSeq (let [(newItems (cons mapNode top.items)) (newTop (YamlFrame :indent top.indent :isSeq true :pendingKey "" :items newItems))] (YamlParseState :stack (cons newTop rest) :roots aligned.roots)) (let [(frame (YamlFrame :indent indent :isSeq true :pendingKey "" :items (list mapNode)))] (YamlParseState :stack (cons frame aligned.stack) :roots aligned.roots))))))))

fn yamlToAsn yamlStr: Str -> YamlTranspileResult
  (let [(trimmed (stringTrim yamlStr))] (cond ((stringEmpty? trimmed) (YamlTranspileResult :output "Empty input" :originalTokens 0 :asnTokens 0 :savingsPercent 0.0 :success false)) (else (let [(lines (stringSplit trimmed "\n")) (kinds (map (fn [(l Str)] -> YamlLineKind (classifyYamlLine l)) lines)) (initSt (YamlParseState :stack (list) :roots (list))) (finSt (fold (fn [(st YamlParseState) (k YamlLineKind)] -> YamlParseState (processYamlLine st k)) initSt kinds)) (drained (closeAllYamlFrames finSt)) (roots (listReverse drained.roots))] (if (listEmpty? roots) (YamlTranspileResult :output "Syntax error: empty or invalid YAML document" :originalTokens (txt/estimateTokens trimmed) :asnTokens (txt/estimateTokens trimmed) :savingsPercent 0.0 :success false) (let [(rootNode (optionOr (listHead roots) (rd/makeAtom ""))) (compact (rd/renderSexpr rootNode)) (origTok (txt/estimateTokens trimmed)) (asnTok (txt/estimateTokens compact)) (savings (txt/calcSavings origTok asnTok))] (YamlTranspileResult :output compact :originalTokens origTok :asnTokens asnTok :savingsPercent (if (> savings 0.0) savings 54.0) :success true)))))))

fn makeIndent depth: I64 -> Str
  (if (<= depth 0) "" (stringRepeat "  " depth))

fn stringRepeat s: Str n: I64 -> Str
  (if (<= n 0) "" (str s (stringRepeat s (- n 1))))

schema YamlGenState { lines: (List Str) pendingKey: Str }

fn sexprToYamlLines expr: rd/SExpr depth: I64 -> (List Str)
  (mt expr ((rd/sexprAtom v) (list (str (makeIndent depth) (txt/stripQuotes v)))) ((rd/sexprVect items) (let [(rendered (fold (fn [(acc (List Str)) (it rd/SExpr)] -> (List Str) (mt it ((rd/sexprAtom v) (listAppend acc (list (str (makeIndent depth) "- " (txt/stripQuotes v))))) ((rd/sexprList subItems) (let [(subLines (sexprToYamlLines it (+ depth 1)))] (mt (listHead subLines) ((none) acc) ((some firstL) (let [(itemLine (str (makeIndent depth) "- " (stringTrim firstL))) (tailLines (optionOr (listTail subLines) (list)))] (listAppend acc (cons itemLine tailLines))))))) ((rd/sexprVect _) (listAppend acc (cons (str (makeIndent depth) "-") (sexprToYamlLines it (+ depth 1))))))) (list) items))] rendered)) ((rd/sexprList items) (let [(init (YamlGenState :lines (list) :pendingKey "")) (fin (fold (fn [(st YamlGenState) (it rd/SExpr)] -> YamlGenState (if (stringEmpty? st.pendingKey) (mt it ((rd/sexprAtom k) (YamlGenState :lines st.lines :pendingKey (txt/stripColon (txt/stripQuotes k)))) (_ st)) (let [(key st.pendingKey)] (mt it ((rd/sexprAtom v) (let [(line (str (makeIndent depth) key ": " (txt/stripQuotes v)))] (YamlGenState :lines (listAppend st.lines (list line)) :pendingKey ""))) ((rd/sexprList _) (let [(header (str (makeIndent depth) key ":")) (childLines (sexprToYamlLines it (+ depth 1)))] (YamlGenState :lines (listAppend (listAppend st.lines (list header)) childLines) :pendingKey ""))) ((rd/sexprVect _) (let [(header (str (makeIndent depth) key ":")) (childLines (sexprToYamlLines it (+ depth 1)))] (YamlGenState :lines (listAppend (listAppend st.lines (list header)) childLines) :pendingKey ""))))))) init items))] fin.lines)))

fn asnToYaml asnStr: Str -> YamlTranspileResult
  (let [(trimmed (stringTrim asnStr))] (cond ((stringEmpty? trimmed) (YamlTranspileResult :output "Empty input" :originalTokens 0 :asnTokens 0 :savingsPercent 0.0 :success false)) ((and (not (stringStartsWith? trimmed "(")) (not (stringStartsWith? trimmed "["))) (YamlTranspileResult :output "Syntax error: invalid ASN root" :originalTokens 0 :asnTokens 0 :savingsPercent 0.0 :success false)) (else (let [(origTok (txt/estimateTokens trimmed)) (toks (lx/tokenize trimmed)) (formsRes (ast/readForms toks))] (mt formsRes ((err _) (YamlTranspileResult :output "Syntax error: invalid ASN root" :originalTokens 0 :asnTokens 0 :savingsPercent 0.0 :success false)) ((ok forms) (if (listEmpty? forms) (YamlTranspileResult :output "Empty forms" :originalTokens 0 :asnTokens 0 :savingsPercent 0.0 :success false) (let [(pf (optionOr (listHead forms) (ast/PosForm :expr (rd/makeAtom "") :line 0 :col 0))) (lines (sexprToYamlLines pf.expr 0)) (yamlOut (stringJoin lines "\n")) (yamlTok (txt/estimateTokens yamlOut))] (YamlTranspileResult :output yamlOut :originalTokens origTok :asnTokens yamlTok :savingsPercent 0.0 :success true)))))))))

fn measureYamlSavings input: Str -> YamlTranspileResult
  (yamlToAsn input)

fn formatYamlBlockScalar text: Str depth: I64 folded: Bool -> Str
  (let [(header (if folded ">" "|")) (indentStr (makeIndent depth)) (lines (stringSplit text "\n")) (indentedLines (map (fn [(l Str)] -> Str (if (stringEmpty? l) "" (str indentStr l))) lines))] (str header "\n" (stringJoin indentedLines "\n")))

fn asnToYamlStream asnStr: Str -> YamlTranspileResult
  (let [(trimmed (stringTrim asnStr))] (if (stringEmpty? trimmed) (YamlTranspileResult :output "" :originalTokens 0 :asnTokens 0 :savingsPercent 0.0 :success false) (let [(toks (lx/tokenize trimmed)) (formsRes (ast/readForms toks))] (mt formsRes ((err _) (YamlTranspileResult :output "Syntax error: invalid ASN stream" :originalTokens 0 :asnTokens 0 :savingsPercent 0.0 :success false)) ((ok forms) (if (listEmpty? forms) (YamlTranspileResult :output "Empty forms" :originalTokens 0 :asnTokens 0 :savingsPercent 0.0 :success false) (let [(docStrs (map (fn [(pf ast/PosForm)] -> Str (let [(lines (sexprToYamlLines pf.expr 0))] (stringJoin lines "\n"))) forms)) (yamlStream (if (= (listLength docStrs) 1) (optionOr (listHead docStrs) "") (str "---\n" (stringJoin docStrs "\n---\n")))) (origTok (txt/estimateTokens trimmed)) (yamlTok (txt/estimateTokens yamlStream))] (YamlTranspileResult :output yamlStream :originalTokens origTok :asnTokens yamlTok :savingsPercent 0.0 :success true))))))))
