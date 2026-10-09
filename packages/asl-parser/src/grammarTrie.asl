(module asl-parser/grammarTrie :x [GrammarTrieNode buildGrammarTrie computeValidTokens validateTokenSequence] :i [])

(schema GrammarTrieNode (:f tokenId Str) (:f terminal Bool) (:f allowedTransitions (List Str)) (:f maskId I64))

fn cleanToken tok: Str -> Str
  (let [(trimmed (stringTrim tok))] (if (and (stringEndsWith? trimmed ")") (> (stringLength trimmed) 1)) (cleanToken (optionOr (stringSlice trimmed 0 (- (stringLength trimmed) 1)) "")) (if (= trimmed ")") "" trimmed)))

fn parseRuleTokens rule: Str -> (List Str)
  (let [(norm (stringReplace (stringReplace (stringReplace rule "\t" " ") "\n" " ") "( " "(")) (rawToks (stringSplit norm " ")) (cleaned (map cleanToken rawToks))] (filter (fn [(t Str)] -> Bool (not (stringEmpty? t))) cleaned))

fn extractPairwiseTransitions toks: (List Str) -> (List Str)
  (if (listEmpty? toks) (list) (let [(curr (optionOr (listHead toks) "")) (rest (optionOr (listTail toks) (list)))] (if (listEmpty? rest) (list (str curr "->END")) (let [(nextTok (optionOr (listHead rest) ""))] (cons (str curr "->" nextTok) (extractPairwiseTransitions rest))))))

fn extractRuleTransitions toks: (List Str) -> (List Str)
  (if (listEmpty? toks) (list) (let [(firstTok (optionOr (listHead toks) "")) (startEdge (str "START->" firstTok)) (bodyEdges (extractPairwiseTransitions toks))] (cons startEdge bodyEdges)))

fn collectTransitions rules: (List Str) -> (List Str)
  (fold (fn [(acc (List Str)) (rule Str)] -> (List Str) (let [(edges (extractRuleTransitions (parseRuleTokens rule)))] (fold (fn [(innerAcc (List Str)) (edge Str)] -> (List Str) (if (listContains? innerAcc edge) innerAcc (listAppend innerAcc (list edge)))) acc edges))) (list) rules)

fn buildGrammarTrie grammarRules: (List Str) -> GrammarTrieNode
  (let [(transitions (collectTransitions grammarRules))] (GrammarTrieNode :tokenId "ROOT" :terminal false :allowedTransitions transitions :maskId 0))

fn getPrefixKey prefix: Str -> Str
  (let [(trimmed (stringTrim prefix))] (if (or (stringEmpty? trimmed) (or (= trimmed "ROOT") (= trimmed "START"))) "START" (let [(toks (parseRuleTokens trimmed))] (if (listEmpty? toks) "START" (optionOr (listLast toks) trimmed)))))

fn computeValidTokens trie: GrammarTrieNode prefix: Str -> (List Str)
  (let [(key (getPrefixKey prefix)) (marker (str key "->")) (markerLen (stringLength marker))] (fold (fn [(acc (List Str)) (edge Str)] -> (List Str) (if (stringStartsWith? edge marker) (let [(target (optionOr (stringSlice edge markerLen (stringLength edge)) ""))] (if (and (not (= target "END")) (not (listContains? acc target))) (listAppend acc (list target)) acc)) acc)) (list) trie.allowedTransitions))

fn validateStep trie: GrammarTrieNode curr: Str rest: (List Str) -> Bool
  (if (listEmpty? rest) (listContains? trie.allowedTransitions (str curr "->END")) (let [(nextTok (optionOr (listHead rest) ""))] (if (listContains? (computeValidTokens trie curr) nextTok) (validateStep trie nextTok (optionOr (listTail rest) (list))) false)))

fn validateTokenSequence trie: GrammarTrieNode tokens: (List Str) -> Bool
  (if (listEmpty? tokens) trie.terminal (let [(cleanToks (filter (fn [(t Str)] -> Bool (not (stringEmpty? t))) (map cleanToken tokens)))] (if (listEmpty? cleanToks) trie.terminal (let [(firstTok (optionOr (listHead cleanToks) ""))] (if (listContains? (computeValidTokens trie "") firstTok) (validateStep trie firstTok (optionOr (listTail cleanToks) (list))) false)))))
