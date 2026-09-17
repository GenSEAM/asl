(module asl-slm/masker
  :d "Pure ASL EBNF Grammar Automaton, Pushdown State Tracker, and Token Mask Bitset Engine"
  :x [GrammarPda MaskerState TokenMaskBitset
      compileGrammarToDfa maskerInit advanceMaskerState advanceMaskerSubword
      resetMaskerBuffer computeTokenMaskBitset isTokenAllowed isTokenValidAtState
      isSubwordPrefixValid isGrammarTerminalAllowed]
  :i [])

(dfs GrammarPda
  (:f status Str "ok or error status string")
  (:f diagnosticCode Str "Canonical diagnostic code on failure, or empty string on success")
  (:f stateCount Int "Total state count in pushdown automaton")
  (:f startState Int "Initial start state index")
  (:f acceptState Int "Accepting terminal state index")
  (:f rootRequiresDelimiter Bool "True if root rule begins with delimiter requiring stack depth > 0")
  (:f ruleNames (List Str) "List of parsed production rule names")
  (:f terminals (List Str) "List of terminal categories and literal tokens recognized by grammar")
  (:f delimiters (List Str) "List of delimiter characters recognized by grammar"))

(dfs MaskerState
  (:f currentState Int "Active pushdown automaton state index")
  (:f stackDepth Int "Current open delimiter balance depth")
  (:f isEosAllowed Bool "True if EOS token is permitted at current state")
  (:f isPrefixValid Bool "True if current subword prefix matches grammar rules")
  (:f buffer Str "Accumulated partial subword token string"))

(dfs TokenMaskBitset
  (:f allowedTokenIds (List Int) "List of permitted token IDs at current state")
  (:f totalVocabSize Int "Total size of vocabulary evaluated"))

(df isDigitsOnly [(s Str)] -> Bool
  (let [(len (string-length s))]
    (if (= len 0)
      false
      (digitsLoop s 0 len))))

(df digitsLoop [(s Str) (idx Int) (len Int)] -> Bool
  (if (>= idx len)
    true
    (let [(ch (option-or (string-slice s idx (+ idx 1)) ""))]
      (if (and (>= ch "0") (<= ch "9"))
        (digitsLoop s (+ idx 1) len)
        false))))

(df isValidIdentifierToken [(s Str)] -> Bool
  (let [(len (string-length s))]
    (if (= len 0)
      false
      (let [(c0 (option-or (string-slice s 0 1) ""))]
        (if (or (and (>= c0 "a") (<= c0 "z"))
                (or (and (>= c0 "A") (<= c0 "Z"))
                    (= c0 "_")))
          (identifierCharsLoop s 1 len)
          false)))))

(df identifierCharsLoop [(s Str) (idx Int) (len Int)] -> Bool
  (if (>= idx len)
    true
    (let [(ch (option-or (string-slice s idx (+ idx 1)) ""))]
      (if (or (and (>= ch "a") (<= ch "z"))
              (or (and (>= ch "A") (<= ch "Z"))
                  (or (and (>= ch "0") (<= ch "9"))
                      (or (= ch "_") (= ch "-")))))
        (identifierCharsLoop s (+ idx 1) len)
        false))))

(df isValidStringLiteralToken [(s Str)] -> Bool
  (let [(len (string-length s))]
    (if (< len 2)
      false
      (and (string-starts-with? s "\"") (string-ends-with? s "\"")))))

(df isDelimiterToken [(tok Str)] -> Bool
  (or (= tok "(")
      (or (= tok ")")
          (or (= tok "[")
              (or (= tok "]")
                  (or (= tok "{")
                      (= tok "}")))))))

(df isOperatorToken [(tok Str)] -> Bool
  (or (= tok "+")
      (or (= tok "-")
          (or (= tok "*")
              (= tok "/")))))

(df extractDelimiters [(src Str) (base (List Str))] -> (List Str)
  (let [(d1 (if (string-contains? src "(") (list-append base (list "(" ")")) base))
        (d2 (if (string-contains? src "[") (list-append d1 (list "[" "]")) d1))
        (d3 (if (string-contains? src "{") (list-append d2 (list "{" "}")) d2))]
    d3))

(df extractTerminals [(src Str) (base (List Str))] -> (List Str)
  (let [(t1 (if (string-contains? src "symbol") (list-append base (list "symbol")) base))
        (t2 (if (string-contains? src "number") (list-append t1 (list "number")) t1))
        (t3 (if (string-contains? src "string") (list-append t2 (list "string")) t2))
        (t4 (if (string-contains? src "'+'") (list-append t3 (list "+")) t3))
        (t5 (if (string-contains? src "'-'") (list-append t4 (list "-")) t4))
        (t6 (if (string-contains? src "'*'") (list-append t5 (list "*")) t5))
        (t7 (if (string-contains? src "'/'") (list-append t6 (list "/")) t6))]
    t7))

(df parseRulesLoop [(rules (List Str))
                    (ruleNames (List Str))
                    (rootRequiresDelim Bool)
                    (terms (List Str))
                    (delims (List Str))
                    (origGrammar Str)] -> GrammarPda
  (if (= (list-length rules) 0)
    (let [(finalDelims (extractDelimiters origGrammar delims))
          (finalTerms (extractTerminals origGrammar terms))
          (ruleCount (list-length ruleNames))
          (stateCount (+ 4 (* 2 ruleCount)))
          (acceptSt (- stateCount 1))]
      (GrammarPda
        :status "ok"
        :diagnosticCode ""
        :stateCount stateCount
        :startState 0
        :acceptState acceptSt
        :rootRequiresDelimiter rootRequiresDelim
        :ruleNames ruleNames
        :terminals finalTerms
        :delimiters finalDelims))
    (let [(head (option-or (list-head rules) ""))
          (tail (option-or (list-tail rules) (list)))
          (trimHead (string-trim head))]
      (if (= trimHead "")
        (parseRulesLoop tail ruleNames rootRequiresDelim terms delims origGrammar)
        (mt (string-index-of trimHead "::=")
          ((none)
           (GrammarPda
             :status "error"
             :diagnosticCode "ERR_GRAMMAR_MALFORMED_RULE"
             :stateCount 0
             :startState -1
             :acceptState -1
             :rootRequiresDelimiter false
             :ruleNames (list)
             :terminals (list)
             :delimiters (list)))
          ((some arrowIdx)
           (let [(lhs (string-trim (option-or (string-slice trimHead 0 arrowIdx) "")))
                 (rhs (string-trim (option-or (string-slice trimHead (+ arrowIdx 3) (string-length trimHead)) "")))]
             (if (or (= lhs "") (not (isValidIdentifierToken lhs)))
               (GrammarPda
                 :status "error"
                 :diagnosticCode "ERR_GRAMMAR_MALFORMED_RULE"
                 :stateCount 0
                 :startState -1
                 :acceptState -1
                 :rootRequiresDelimiter false
                 :ruleNames (list)
                 :terminals (list)
                 :delimiters (list))
               (if (= rhs "")
                 (GrammarPda
                   :status "error"
                   :diagnosticCode "ERR_GRAMMAR_PARSE_FAILURE"
                   :stateCount 0
                   :startState -1
                   :acceptState -1
                   :rootRequiresDelimiter false
                   :ruleNames (list)
                   :terminals (list)
                   :delimiters (list))
                 (let [(isRoot (= lhs "root"))
                       (requiresDelim (if isRoot
                                        (or (string-starts-with? rhs "'('")
                                            (or (string-starts-with? rhs "\"(\"")
                                                (or (string-starts-with? rhs "'['")
                                                    (string-starts-with? rhs "'{'"))))
                                        rootRequiresDelim))]
                   (parseRulesLoop tail
                                   (list-append ruleNames (list lhs))
                                   requiresDelim
                                   terms
                                   delims
                                   origGrammar)))))))))))

(df compileGrammarToDfa [(grammarStr Str)] -> GrammarPda
  :d "Compiles EBNF grammar into deterministic pushdown automaton with delimiter balance states."
  (let [(trimmed (string-trim grammarStr))]
    (if (= trimmed "")
      (GrammarPda
        :status "error"
        :diagnosticCode "ERR_GRAMMAR_EMPTY"
        :stateCount 0
        :startState -1
        :acceptState -1
        :rootRequiresDelimiter false
        :ruleNames (list)
        :terminals (list)
        :delimiters (list))
      (let [(chunks (string-split trimmed ";"))
            (rawRules (list-filter (fn [(c Str)] (not (= (string-trim c) ""))) chunks))]
        (if (= (list-length rawRules) 0)
          (GrammarPda
            :status "error"
            :diagnosticCode "ERR_GRAMMAR_EMPTY"
            :stateCount 0
            :startState -1
            :acceptState -1
            :rootRequiresDelimiter false
            :ruleNames (list)
            :terminals (list)
            :delimiters (list))
          (parseRulesLoop rawRules (list) false (list) (list) grammarStr))))))

(df maskerInit [(pda GrammarPda) (eosTokenId Int)] -> MaskerState
  :d "Initializes pushdown masker state tracking with zero delimiter depth."
  (MaskerState
    :currentState (.-startState pda)
    :stackDepth 0
    :isEosAllowed false
    :isPrefixValid true
    :buffer ""))

(df resetMaskerBuffer [(st MaskerState)] -> MaskerState
  :d "Resets accumulated partial subword buffer to empty string."
  (MaskerState
    :currentState (.-currentState st)
    :stackDepth (.-stackDepth st)
    :isEosAllowed (.-isEosAllowed st)
    :isPrefixValid true
    :buffer ""))

(df isGrammarTerminalAllowed [(pda GrammarPda) (tok Str)] -> Bool
  :d "Checks whether candidate token matches terminal rules recognized by grammar."
  (if (isDigitsOnly tok)
    (list-any? (fn [(t Str)] (= t "number")) (.-terminals pda))
    (if (isValidStringLiteralToken tok)
      (list-any? (fn [(t Str)] (= t "string")) (.-terminals pda))
      (if (isValidIdentifierToken tok)
        (list-any? (fn [(t Str)] (= t "symbol")) (.-terminals pda))
        (if (isOperatorToken tok)
          (list-any? (fn [(t Str)] (= t tok)) (.-terminals pda))
          false)))))

(df isSubwordPrefixValid [(pda GrammarPda) (prefix Str)] -> Bool
  :d "Validates whether accumulated subword buffer matches valid prefix of grammar terminal."
  (let [(len (string-length prefix))]
    (if (= len 0)
      true
      (if (isDigitsOnly prefix)
        true
        (if (isValidIdentifierToken prefix)
          true
          (if (string-starts-with? prefix "\"")
            true
            (if (or (isDelimiterToken prefix) (isOperatorToken prefix))
              true
              false)))))))

(df advanceMaskerState [(pda GrammarPda) (st MaskerState) (tokenText Str)] -> MaskerState
  :d "Transitions pushdown automaton state and updates delimiter balance depth on sampled token."
  (let [(curDepth (.-stackDepth st))]
    (if (or (= tokenText "(") (or (= tokenText "[") (= tokenText "{")))
      (MaskerState
        :currentState 1
        :stackDepth (+ curDepth 1)
        :isEosAllowed false
        :isPrefixValid true
        :buffer "")
      (if (or (= tokenText ")") (or (= tokenText "]") (= tokenText "}")))
        (let [(nextDepth (if (> curDepth 0) (- curDepth 1) 0))
              (isAccept (= nextDepth 0))]
          (MaskerState
            :currentState (if isAccept (.-acceptState pda) 1)
            :stackDepth nextDepth
            :isEosAllowed isAccept
            :isPrefixValid true
            :buffer ""))
        (if (= tokenText "<eos>")
          st
          (let [(isTopLevelAtom (and (= curDepth 0) (not (.-rootRequiresDelimiter pda))))]
            (MaskerState
              :currentState (if isTopLevelAtom (.-acceptState pda) (if (> curDepth 0) 2 (.-currentState st)))
              :stackDepth curDepth
              :isEosAllowed isTopLevelAtom
              :isPrefixValid true
              :buffer "")))))))

(df advanceMaskerSubword [(pda GrammarPda) (st MaskerState) (subword Str)] -> MaskerState
  :d "Performs BPE subword prefix matching and updates partial token buffer state."
  (let [(newBuf (str (.-buffer st) subword))
        (isValid (isSubwordPrefixValid pda newBuf))]
    (MaskerState
      :currentState (.-currentState st)
      :stackDepth (.-stackDepth st)
      :isEosAllowed false
      :isPrefixValid isValid
      :buffer newBuf)))

(df isTokenValidAtState [(pda GrammarPda) (st MaskerState) (tokenId Int) (tokenText Str)] -> Bool
  :d "Evaluates whether candidate token is permitted under active grammar pushdown state."
  (if (= tokenText "<eos>")
    (.-isEosAllowed st)
    (if (= tokenText ")")
      (> (.-stackDepth st) 0)
      (if (= tokenText "(")
        true
        (if (= tokenText "]")
          (> (.-stackDepth st) 0)
          (if (= tokenText "[")
            true
            (if (= tokenText "}")
              (> (.-stackDepth st) 0)
              (if (= tokenText "{")
                true
                (let [(curDepth (.-stackDepth st))
                      (isAtom (isGrammarTerminalAllowed pda tokenText))]
                  (if isAtom
                    (if (> curDepth 0)
                      true
                      (not (.-rootRequiresDelimiter pda)))
                    false))))))))))

(df computeTokenMaskBitset [(pda GrammarPda) (st MaskerState) (vocab (List (Pair Int Str)))] -> TokenMaskBitset
  :d "Precomputes token mask bitset over vocabulary prohibiting invalid tokens and enforcing EOS masking."
  (let [(curBuf (.-buffer st))
        (allowed (list-fold
                   (fn [(acc (List Int)) (item (Pair Int Str))]
                     (let [(tId (pair-first item))
                           (tText (pair-second item))
                           (isValid (if (= curBuf "")
                                      (isTokenValidAtState pda st tId tText)
                                      (let [(testBuf (str curBuf tText))]
                                        (isSubwordPrefixValid pda testBuf))))]
                       (if isValid
                         (list-append acc (list tId))
                         acc)))
                   (list)
                   vocab))]
    (TokenMaskBitset
      :allowedTokenIds allowed
      :totalVocabSize (list-length vocab))))

(df isTokenAllowed [(mask TokenMaskBitset) (tokenId Int)] -> Bool
  :d "Queries whether a token ID is permitted under the computed mask bitset."
  (list-any? (fn [(id Int)] (= id tokenId)) (.-allowedTokenIds mask)))
