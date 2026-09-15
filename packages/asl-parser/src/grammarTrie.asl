(module asl-parser/grammarTrie
  :d "In-memory grammar trie state machine for constrained decoding and structured ASN emission"
  :x [GrammarTrieNode
      buildGrammarTrie
      computeValidTokens
      validateTokenSequence]
  :i [])

(dfs GrammarTrieNode
  (:f tokenId Str "Token identifier or state label of current node")
  (:f terminal Bool "Indicates if this state represents a valid sequence termination")
  (:f allowedTransitions (List Str) "List of allowed subsequent token IDs or encoded transition edges")
  (:f maskId I64 "Unique bitmask or state index for vocabulary logit masking"))

(df cleanToken [(tok Str)] -> Str
  :d "Trims whitespace from tokens and normalizes token identifiers"
  (let [(trimmed (string-trim tok))]
    (if (and (string-ends-with? trimmed ")") (> (string-length trimmed) 1))
      (cleanToken (option-or (string-slice trimmed 0 (- (string-length trimmed) 1)) ""))
      (if (= trimmed ")")
        ""
        trimmed))))

(df parseRuleTokens [(rule Str)] -> (List Str)
  :d "Splits grammar rule string by whitespace and delimiters into discrete ordered token symbols"
  (let [(norm (string-replace (string-replace (string-replace rule "\t" " ") "\n" " ") "( " "("))
        (rawToks (string-split norm " "))
        (cleaned (map cleanToken rawToks))]
    (filter (fn [(t Str)] -> Bool (not (string-empty? t))) cleaned)))

(df extractPairwiseTransitions [(toks (List Str))] -> (List Str)
  :d "Extracts pairwise transition edges and terminal marker from tokens"
  (if (list-empty? toks)
    (list)
    (let [(curr (option-or (list-head toks) ""))
          (rest (option-or (list-tail toks) (list)))]
      (if (list-empty? rest)
        (list (str curr "->END"))
        (let [(nextTok (option-or (list-head rest) ""))]
          (cons (str curr "->" nextTok)
                (extractPairwiseTransitions rest)))))))

(df extractRuleTransitions [(toks (List Str))] -> (List Str)
  :d "Extracts all transitions from an ordered token sequence starting at root"
  (if (list-empty? toks)
    (list)
    (let [(firstTok (option-or (list-head toks) ""))
          (startEdge (str "START->" firstTok))
          (bodyEdges (extractPairwiseTransitions toks))]
      (cons startEdge bodyEdges))))

(df collectTransitions [(rules (List Str))] -> (List Str)
  :d "Extracts and deduplicates transitions across all grammar rules"
  (fold (fn [(acc (List Str)) (rule Str)] -> (List Str)
          (let [(edges (extractRuleTransitions (parseRuleTokens rule)))]
            (fold (fn [(innerAcc (List Str)) (edge Str)] -> (List Str)
                    (if (list-contains? innerAcc edge)
                      innerAcc
                      (list-append innerAcc (list edge))))
                  acc
                  edges)))
        (list)
        rules))

(df buildGrammarTrie [(grammarRules (List Str))] -> GrammarTrieNode
  :d "Builds in-memory grammar trie state machine from structured ASN grammar rules"
  (let [(transitions (collectTransitions grammarRules))]
    (GrammarTrieNode
      :tokenId "ROOT"
      :terminal false
      :allowedTransitions transitions
      :maskId 0)))

(df getPrefixKey [(prefix Str)] -> Str
  :d "Normalizes prefix string to transition lookup key"
  (let [(trimmed (string-trim prefix))]
    (if (or (string-empty? trimmed) (or (= trimmed "ROOT") (= trimmed "START")))
      "START"
      (let [(toks (parseRuleTokens trimmed))]
        (if (list-empty? toks)
          "START"
          (option-or (list-last toks) trimmed))))))

(df computeValidTokens [(trie GrammarTrieNode) (prefix Str)] -> (List Str)
  :d "Computes exact legal next token set admitted by grammar trie given current prefix"
  (let [(key (getPrefixKey prefix))
        (marker (str key "->"))
        (markerLen (string-length marker))]
    (fold (fn [(acc (List Str)) (edge Str)] -> (List Str)
            (if (string-starts-with? edge marker)
              (let [(target (option-or (string-slice edge markerLen (string-length edge)) ""))]
                (if (and (not (= target "END")) (not (list-contains? acc target)))
                  (list-append acc (list target))
                  acc))
              acc))
          (list)
          (.-allowedTransitions trie))))

(df validateStep [(trie GrammarTrieNode) (curr Str) (rest (List Str))] -> Bool
  :d "Validates pairwise transition steps to terminal"
  (if (list-empty? rest)
    (list-contains? (.-allowedTransitions trie) (str curr "->END"))
    (let [(nextTok (option-or (list-head rest) ""))]
      (if (list-contains? (computeValidTokens trie curr) nextTok)
        (validateStep trie nextTok (option-or (list-tail rest) (list)))
        false))))

(df validateTokenSequence [(trie GrammarTrieNode) (tokens (List Str))] -> Bool
  :d "Validates whether sequential token stream satisfies grammar trie transition constraints to terminal state"
  (if (list-empty? tokens)
    (.-terminal trie)
    (let [(cleanToks (filter (fn [(t Str)] -> Bool (not (string-empty? t))) (map cleanToken tokens)))]
      (if (list-empty? cleanToks)
        (.-terminal trie)
        (let [(firstTok (option-or (list-head cleanToks) ""))]
          (if (list-contains? (computeValidTokens trie "") firstTok)
            (validateStep trie firstTok (option-or (list-tail cleanToks) (list)))
            false))))))
