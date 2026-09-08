(module asl-parser/grammar-trie
  :d "In-memory grammar trie state machine for constrained decoding and structured ASN emission"
  :x [GrammarTrieNode
      build-grammar-trie
      compute-valid-tokens
      validate-token-sequence]
  :i [])

(dfs GrammarTrieNode
  (:f token-id Str "Token identifier or state label of current node")
  (:f terminal Bool "Indicates if this state represents a valid sequence termination")
  (:f allowed-transitions (List Str) "List of allowed subsequent token IDs or encoded transition edges")
  (:f mask-id I64 "Unique bitmask or state index for vocabulary logit masking"))

(df clean-token [(tok Str)] -> Str
  :d "Trims whitespace from tokens and normalizes token identifiers"
  (let [(trimmed (string-trim tok))]
    (if (and (string-ends-with? trimmed ")") (> (string-length trimmed) 1))
      (clean-token (option-or (string-slice trimmed 0 (- (string-length trimmed) 1)) ""))
      (if (= trimmed ")")
        ""
        trimmed))))

(df parse-rule-tokens [(rule Str)] -> (List Str)
  :d "Splits grammar rule string by whitespace and delimiters into discrete ordered token symbols"
  (let [(norm (string-replace (string-replace (string-replace rule "\t" " ") "\n" " ") "( " "("))
        (raw-toks (string-split norm " "))
        (cleaned (map clean-token raw-toks))]
    (filter (fn [(t Str)] -> Bool (not (string-empty? t))) cleaned)))

(df extract-pairwise-transitions [(toks (List Str))] -> (List Str)
  :d "Extracts pairwise transition edges and terminal marker from tokens"
  (if (list-empty? toks)
    (list)
    (let [(curr (option-or (list-head toks) ""))
          (rest (option-or (list-tail toks) (list)))]
      (if (list-empty? rest)
        (list (str curr "->END"))
        (let [(next-tok (option-or (list-head rest) ""))]
          (cons (str curr "->" next-tok)
                (extract-pairwise-transitions rest)))))))

(df extract-rule-transitions [(toks (List Str))] -> (List Str)
  :d "Extracts all transitions from an ordered token sequence starting at root"
  (if (list-empty? toks)
    (list)
    (let [(first-tok (option-or (list-head toks) ""))
          (start-edge (str "START->" first-tok))
          (body-edges (extract-pairwise-transitions toks))]
      (cons start-edge body-edges))))

(df collect-transitions [(rules (List Str))] -> (List Str)
  :d "Extracts and deduplicates transitions across all grammar rules"
  (fold (fn [(acc (List Str)) (rule Str)] -> (List Str)
          (let [(edges (extract-rule-transitions (parse-rule-tokens rule)))]
            (fold (fn [(inner-acc (List Str)) (edge Str)] -> (List Str)
                    (if (list-contains? inner-acc edge)
                      inner-acc
                      (list-append inner-acc (list edge))))
                  acc
                  edges)))
        (list)
        rules))

(df build-grammar-trie [(grammar-rules (List Str))] -> GrammarTrieNode
  :d "Builds in-memory grammar trie state machine from structured ASN grammar rules"
  (let [(transitions (collect-transitions grammar-rules))]
    (GrammarTrieNode
      :token-id "ROOT"
      :terminal false
      :allowed-transitions transitions
      :mask-id 0)))

(df get-prefix-key [(prefix Str)] -> Str
  :d "Normalizes prefix string to transition lookup key"
  (let [(trimmed (string-trim prefix))]
    (if (or (string-empty? trimmed) (or (= trimmed "ROOT") (= trimmed "START")))
      "START"
      (let [(toks (parse-rule-tokens trimmed))]
        (if (list-empty? toks)
          "START"
          (option-or (list-last toks) trimmed))))))

(df compute-valid-tokens [(trie GrammarTrieNode) (prefix Str)] -> (List Str)
  :d "Computes exact legal next token set admitted by grammar trie given current prefix"
  (let [(key (get-prefix-key prefix))
        (marker (str key "->"))
        (marker-len (string-length marker))]
    (fold (fn [(acc (List Str)) (edge Str)] -> (List Str)
            (if (string-starts-with? edge marker)
              (let [(target (option-or (string-slice edge marker-len (string-length edge)) ""))]
                (if (and (not (= target "END")) (not (list-contains? acc target)))
                  (list-append acc (list target))
                  acc))
              acc))
          (list)
          (.-allowed-transitions trie))))

(df validate-step [(trie GrammarTrieNode) (curr Str) (rest (List Str))] -> Bool
  :d "Validates pairwise transition steps to terminal"
  (if (list-empty? rest)
    (list-contains? (.-allowed-transitions trie) (str curr "->END"))
    (let [(next-tok (option-or (list-head rest) ""))]
      (if (list-contains? (compute-valid-tokens trie curr) next-tok)
        (validate-step trie next-tok (option-or (list-tail rest) (list)))
        false))))

(df validate-token-sequence [(trie GrammarTrieNode) (tokens (List Str))] -> Bool
  :d "Validates whether sequential token stream satisfies grammar trie transition constraints to terminal state"
  (if (list-empty? tokens)
    (.-terminal trie)
    (let [(clean-toks (filter (fn [(t Str)] -> Bool (not (string-empty? t))) (map clean-token tokens)))]
      (if (list-empty? clean-toks)
        (.-terminal trie)
        (let [(first-tok (option-or (list-head clean-toks) ""))]
          (if (list-contains? (compute-valid-tokens trie "") first-tok)
            (validate-step trie first-tok (option-or (list-tail clean-toks) (list)))
            false))))))
