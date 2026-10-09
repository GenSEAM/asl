(module asl-slm/masker :x [GrammarPda MaskerState TokenMaskBitset compileGrammarToDfa maskerInit advanceMaskerState advanceMaskerSubword resetMaskerBuffer computeTokenMaskBitset isTokenAllowed isTokenValidAtState isSubwordPrefixValid isGrammarTerminalAllowed] :i [])

(schema GrammarPda (:f status Str) (:f diagnosticCode Str) (:f stateCount Int) (:f startState Int) (:f acceptState Int) (:f rootRequiresDelimiter Bool) (:f ruleNames (List Str)) (:f terminals (List Str)) (:f delimiters (List Str)))

(schema MaskerState (:f currentState Int) (:f stackDepth Int) (:f isEosAllowed Bool) (:f isPrefixValid Bool) (:f buffer Str))

(schema TokenMaskBitset (:f allowedTokenIds (List Int)) (:f totalVocabSize Int))

fn isDigitsOnly s: Str -> Bool
  (let [(len (stringLength s))] (if (= len 0) false (digitsLoop s 0 len)))

fn digitsLoop s: Str idx: Int len: Int -> Bool
  (if (>= idx len) true (let [(ch (optionOr (stringSlice s idx (+ idx 1)) ""))] (if (and (>= ch "0") (<= ch "9")) (digitsLoop s (+ idx 1) len) false)))

fn isValidIdentifierToken s: Str -> Bool
  (let [(len (stringLength s))] (if (= len 0) false (let [(c0 (optionOr (stringSlice s 0 1) ""))] (if (or (and (>= c0 "a") (<= c0 "z")) (or (and (>= c0 "A") (<= c0 "Z")) (= c0 "_"))) (identifierCharsLoop s 1 len) false))))

fn identifierCharsLoop s: Str idx: Int len: Int -> Bool
  (if (>= idx len) true (let [(ch (optionOr (stringSlice s idx (+ idx 1)) ""))] (if (or (and (>= ch "a") (<= ch "z")) (or (and (>= ch "A") (<= ch "Z")) (or (and (>= ch "0") (<= ch "9")) (or (= ch "_") (= ch "-"))))) (identifierCharsLoop s (+ idx 1) len) false)))

fn isValidStringLiteralToken s: Str -> Bool
  (let [(len (stringLength s))] (if (< len 2) false (and (stringStartsWith? s "\"") (stringEndsWith? s "\""))))

fn isDelimiterToken tok: Str -> Bool
  (or (= tok "(") (or (= tok ")") (or (= tok "[") (or (= tok "]") (or (= tok "{") (= tok "}"))))))

fn isOperatorToken tok: Str -> Bool
  (or (= tok "+") (or (= tok "-") (or (= tok "*") (= tok "/"))))

fn extractDelimiters src: Str base: (List Str) -> (List Str)
  (let [(d1 (if (stringContains? src "(") (listAppend base (list "(" ")")) base)) (d2 (if (stringContains? src "[") (listAppend d1 (list "[" "]")) d1)) (d3 (if (stringContains? src "{") (listAppend d2 (list "{" "}")) d2))] d3)

fn extractTerminals src: Str base: (List Str) -> (List Str)
  (let [(t1 (if (stringContains? src "symbol") (listAppend base (list "symbol")) base)) (t2 (if (stringContains? src "number") (listAppend t1 (list "number")) t1)) (t3 (if (stringContains? src "string") (listAppend t2 (list "string")) t2)) (t4 (if (stringContains? src "'+'") (listAppend t3 (list "+")) t3)) (t5 (if (stringContains? src "'-'") (listAppend t4 (list "-")) t4)) (t6 (if (stringContains? src "'*'") (listAppend t5 (list "*")) t5)) (t7 (if (stringContains? src "'/'") (listAppend t6 (list "/")) t6))] t7)

fn parseRulesLoop rules: (List Str) ruleNames: (List Str) rootRequiresDelim: Bool terms: (List Str) delims: (List Str) origGrammar: Str -> GrammarPda
  (if (= (listLength rules) 0) (let [(finalDelims (extractDelimiters origGrammar delims)) (finalTerms (extractTerminals origGrammar terms)) (ruleCount (listLength ruleNames)) (stateCount (+ 4 (* 2 ruleCount))) (acceptSt (- stateCount 1))] (GrammarPda :status "ok" :diagnosticCode "" :stateCount stateCount :startState 0 :acceptState acceptSt :rootRequiresDelimiter rootRequiresDelim :ruleNames ruleNames :terminals finalTerms :delimiters finalDelims)) (let [(head (optionOr (listHead rules) "")) (tail (optionOr (listTail rules) (list))) (trimHead (stringTrim head))] (if (= trimHead "") (parseRulesLoop tail ruleNames rootRequiresDelim terms delims origGrammar) (mt (stringIndexOf trimHead "::=") ((none) (GrammarPda :status "error" :diagnosticCode "ERR_GRAMMAR_MALFORMED_RULE" :stateCount 0 :startState -1 :acceptState -1 :rootRequiresDelimiter false :ruleNames (list) :terminals (list) :delimiters (list))) ((some arrowIdx) (let [(lhs (stringTrim (optionOr (stringSlice trimHead 0 arrowIdx) ""))) (rhs (stringTrim (optionOr (stringSlice trimHead (+ arrowIdx 3) (stringLength trimHead)) "")))] (if (or (= lhs "") (not (isValidIdentifierToken lhs))) (GrammarPda :status "error" :diagnosticCode "ERR_GRAMMAR_MALFORMED_RULE" :stateCount 0 :startState -1 :acceptState -1 :rootRequiresDelimiter false :ruleNames (list) :terminals (list) :delimiters (list)) (if (= rhs "") (GrammarPda :status "error" :diagnosticCode "ERR_GRAMMAR_PARSE_FAILURE" :stateCount 0 :startState -1 :acceptState -1 :rootRequiresDelimiter false :ruleNames (list) :terminals (list) :delimiters (list)) (let [(isRoot (= lhs "root")) (requiresDelim (if isRoot (or (stringStartsWith? rhs "'('") (or (stringStartsWith? rhs "\"(\"") (or (stringStartsWith? rhs "'['") (stringStartsWith? rhs "'{'")))) rootRequiresDelim))] (parseRulesLoop tail (listAppend ruleNames (list lhs)) requiresDelim terms delims origGrammar))))))))))

fn compileGrammarToDfa grammarStr: Str -> GrammarPda
  (let [(trimmed (stringTrim grammarStr))] (if (= trimmed "") (GrammarPda :status "error" :diagnosticCode "ERR_GRAMMAR_EMPTY" :stateCount 0 :startState -1 :acceptState -1 :rootRequiresDelimiter false :ruleNames (list) :terminals (list) :delimiters (list)) (let [(chunks (stringSplit trimmed ";")) (rawRules (filter (fn [(c Str)] (not (= (stringTrim c) ""))) chunks))] (if (= (listLength rawRules) 0) (GrammarPda :status "error" :diagnosticCode "ERR_GRAMMAR_EMPTY" :stateCount 0 :startState -1 :acceptState -1 :rootRequiresDelimiter false :ruleNames (list) :terminals (list) :delimiters (list)) (parseRulesLoop rawRules (list) false (list) (list) grammarStr)))))

fn maskerInit pda: GrammarPda eosTokenId: Int -> MaskerState
  (MaskerState :currentState pda.startState :stackDepth 0 :isEosAllowed false :isPrefixValid true :buffer "")

fn resetMaskerBuffer st: MaskerState -> MaskerState
  (with st :isPrefixValid true :buffer "")

fn isGrammarTerminalAllowed pda: GrammarPda tok: Str -> Bool
  (if (isDigitsOnly tok) (listAny? (fn [(t Str)] (= t "number")) pda.terminals) (if (isValidStringLiteralToken tok) (listAny? (fn [(t Str)] (= t "string")) pda.terminals) (if (isValidIdentifierToken tok) (listAny? (fn [(t Str)] (= t "symbol")) pda.terminals) (if (isOperatorToken tok) (listAny? (fn [(t Str)] (= t tok)) pda.terminals) false))))

fn isSubwordPrefixValid pda: GrammarPda prefix: Str -> Bool
  (let [(len (stringLength prefix))] (if (= len 0) true (if (isDigitsOnly prefix) true (if (isValidIdentifierToken prefix) true (if (stringStartsWith? prefix "\"") true (if (or (isDelimiterToken prefix) (isOperatorToken prefix)) true false))))))

fn advanceMaskerState pda: GrammarPda st: MaskerState tokenText: Str -> MaskerState
  (let [(curDepth st.stackDepth)] (if (or (= tokenText "(") (or (= tokenText "[") (= tokenText "{"))) (MaskerState :currentState 1 :stackDepth (+ curDepth 1) :isEosAllowed false :isPrefixValid true :buffer "") (if (or (= tokenText ")") (or (= tokenText "]") (= tokenText "}"))) (let [(nextDepth (if (> curDepth 0) (- curDepth 1) 0)) (isAccept (= nextDepth 0))] (MaskerState :currentState (if isAccept pda.acceptState 1) :stackDepth nextDepth :isEosAllowed isAccept :isPrefixValid true :buffer "")) (if (= tokenText "<eos>") st (let [(isTopLevelAtom (and (= curDepth 0) (not pda.rootRequiresDelimiter)))] (MaskerState :currentState (if isTopLevelAtom pda.acceptState (if (> curDepth 0) 2 st.currentState)) :stackDepth curDepth :isEosAllowed isTopLevelAtom :isPrefixValid true :buffer ""))))))

fn advanceMaskerSubword pda: GrammarPda st: MaskerState subword: Str -> MaskerState
  (let [(newBuf (str st.buffer subword)) (isValid (isSubwordPrefixValid pda newBuf))] (with st :isEosAllowed false :isPrefixValid isValid :buffer newBuf))

fn isTokenValidAtState pda: GrammarPda st: MaskerState tokenId: Int tokenText: Str -> Bool
  (if (= tokenText "<eos>") st.isEosAllowed (if (= tokenText ")") (> st.stackDepth 0) (if (= tokenText "(") true (if (= tokenText "]") (> st.stackDepth 0) (if (= tokenText "[") true (if (= tokenText "}") (> st.stackDepth 0) (if (= tokenText "{") true (let [(curDepth st.stackDepth) (isAtom (isGrammarTerminalAllowed pda tokenText))] (if isAtom (if (> curDepth 0) true (not pda.rootRequiresDelimiter)) false)))))))))

fn computeTokenMaskBitset pda: GrammarPda st: MaskerState vocab: (List (Pair Int Str)) -> TokenMaskBitset
  (let [(curBuf st.buffer) (allowed (fold (fn [(acc (List Int)) (item (pair Int Str))] (let [(tId (pairFirst item)) (tText (pairSecond item)) (isValid (if (= curBuf "") (isTokenValidAtState pda st tId tText) (let [(testBuf (str curBuf tText))] (isSubwordPrefixValid pda testBuf))))] (if isValid (listAppend acc (list tId)) acc))) (list) vocab))] (TokenMaskBitset :allowedTokenIds allowed :totalVocabSize (listLength vocab)))

fn isTokenAllowed mask: TokenMaskBitset tokenId: Int -> Bool
  (listContains? mask.allowedTokenIds tokenId)
