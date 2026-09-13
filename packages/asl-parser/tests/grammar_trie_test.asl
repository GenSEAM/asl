(module asl-parser/tests/grammarTrieTest
  :d "Unit tests for in-memory grammar trie constrained decoding under strict falsification"
  :x [testTrieConstruction
      testComputeValidRootTokens
      testComputeValidSubsequentTokens
      testMultiRuleBranching
      testValidateTokenSequenceValid
      testValidateTokenSequenceInvalid
      testValidateTokenSequenceTerminal
      runTests]
  :i [(grammar_trie :a gt)])

(df testTrieConstruction [] -> Bool
  :d "Verifies grammar trie node initialization from structured ASN rules"
  (let [(rules (list "(:task :id :title :gate)" "(:phase :name :state)"))
        (trie (gt/buildGrammarTrie rules))]
    (assert (= (.-tokenId trie) "ROOT") "Root token-id must be ROOT")
    (assert (= (.-terminal trie) false) "Root terminal must be false")
    (assert (= (.-maskId trie) 0) "Root mask-id must be 0")
    (assert (> (list-length (.-allowedTransitions trie)) 0) "Transitions list must not be empty")
    (assert (list-contains? (.-allowedTransitions trie) "START->(:task") "Must contain start transition for (:task")
    (assert (list-contains? (.-allowedTransitions trie) ":gate->END") "Must contain terminal transition for :gate")
    true))

(df testComputeValidRootTokens [] -> Bool
  :d "Verifies exact admitted root tokens for empty, START, and ROOT prefixes"
  (let [(rules (list "(:task :id :title :gate)" "(:phase :name :state)"))
        (trie (gt/buildGrammarTrie rules))]
    (assert (= (list-length (gt/computeValidTokens trie "")) 2) "Empty prefix must yield 2 root tokens")
    (assert (list-contains? (gt/computeValidTokens trie "") "(:task") "Admitted root tokens must contain (:task")
    (assert (list-contains? (gt/computeValidTokens trie "") "(:phase") "Admitted root tokens must contain (:phase")
    (assert (= (list-length (gt/computeValidTokens trie "START")) 2) "START prefix must yield 2 root tokens")
    (assert (= (list-length (gt/computeValidTokens trie "ROOT")) 2) "ROOT prefix must yield 2 root tokens")
    (assert (= (list-length (gt/computeValidTokens trie ":invalid")) 0) "Disallowed start token must yield empty valid tokens")
    true))

(df testComputeValidSubsequentTokens [] -> Bool
  :d "Verifies sequential next token transitions and terminal boundary conditions"
  (let [(rules (list "(:task :id :title :gate)" "(:phase :name :state)"))
        (trie (gt/buildGrammarTrie rules))]
    (assert (list-contains? (gt/computeValidTokens trie "(:task") ":id") "Following (:task must allow :id")
    (assert (= (list-length (gt/computeValidTokens trie "(:task")) 1) "Following (:task must only allow :id")
    (assert (list-contains? (gt/computeValidTokens trie ":id") ":title") "Following :id must allow :title")
    (assert (list-contains? (gt/computeValidTokens trie ":title") ":gate") "Following :title must allow :gate")
    (assert (= (list-length (gt/computeValidTokens trie ":gate")) 0) "Terminal :gate must have no further non-terminal transitions")
    (assert (= (list-length (gt/computeValidTokens trie "unknown-prefix")) 0) "Unknown prefix must yield empty list")
    true))

(df testMultiRuleBranching [] -> Bool
  :d "Verifies trie branching when multiple rules share a common prefix"
  (let [(rules (list "(:node :id :name)" "(:node :id :value)"))
        (trie (gt/buildGrammarTrie rules))]
    (assert (= (list-length (gt/computeValidTokens trie ":id")) 2) "Branching :id must yield 2 choices")
    (assert (list-contains? (gt/computeValidTokens trie ":id") ":name") "Branching choices must contain :name")
    (assert (list-contains? (gt/computeValidTokens trie ":id") ":value") "Branching choices must contain :value")
    (assert (= (list-length (gt/computeValidTokens trie "(:node")) 1) "(:node must yield only :id")
    (assert (= (list-length (gt/computeValidTokens trie ":name")) 0) ":name must have no further non-terminal transitions")
    true))

(df testValidateTokenSequenceValid [] -> Bool
  :d "Verifies sequence validator succeeds on full valid sequences"
  (let [(rules (list "(:task :id :title :gate)" "(:phase :name :state)"))
        (trie (gt/buildGrammarTrie rules))
        (rules2 (list "(:task :id :title :gate)" "(:atom)"))
        (trie2 (gt/buildGrammarTrie rules2))]
    (assert (gt/validateTokenSequence trie (list "(:task" ":id" ":title" ":gate")) "Full valid task sequence must pass")
    (assert (gt/validateTokenSequence trie (list "(:phase" ":name" ":state")) "Full valid phase sequence must pass")
    (assert (gt/validateTokenSequence trie2 (list "(:atom")) "Single token rule sequence must pass")
    (assert (gt/validateTokenSequence trie (list "  (:task  " " :id " " :title " " :gate) ")) "Whitespace-padded tokens must pass")
    (assert (gt/validateTokenSequence trie2 (list "(:task" ":id" ":title" ":gate")) "Valid task sequence on multi-rule trie must pass")
    true))

(df testValidateTokenSequenceInvalid [] -> Bool
  :d "Verifies sequence validator rejects sequences with illegal steps or start tokens"
  (let [(rules (list "(:task :id :title :gate)" "(:phase :name :state)"))
        (trie (gt/buildGrammarTrie rules))]
    (assert (not (gt/validateTokenSequence trie (list))) "Empty token sequence must be rejected")
    (assert (not (gt/validateTokenSequence trie (list ":invalid" ":id" ":title" ":gate"))) "Sequence starting with invalid token must be rejected")
    (assert (not (gt/validateTokenSequence trie (list "(:task" ":state" ":title" ":gate"))) "Sequence with illegal middle transition must be rejected")
    (assert (not (gt/validateTokenSequence trie (list "(:task" ":unknown-tok"))) "Sequence with unknown vocabulary token must be rejected")
    (assert (not (gt/validateTokenSequence trie (list "(:task" ":id" ":title" ":state"))) "Sequence ending in mismatched terminal must be rejected")
    (assert (not (gt/validateTokenSequence trie (list "(:phase" ":id" ":state"))) "Sequence mixing branches illegally must be rejected")
    true))

(df testValidateTokenSequenceTerminal [] -> Bool
  :d "Verifies sequence validator rejects truncated sequences that do not reach terminal state"
  (let [(rules (list "(:task :id :title :gate)" "(:phase :name :state)"))
        (trie (gt/buildGrammarTrie rules))]
    (assert (not (gt/validateTokenSequence trie (list "(:task"))) "Single non-terminal start token must be rejected")
    (assert (not (gt/validateTokenSequence trie (list "(:task" ":id"))) "Truncated two-token sequence must be rejected")
    (assert (not (gt/validateTokenSequence trie (list "(:task" ":id" ":title"))) "Truncated three-token sequence must be rejected")
    (assert (not (gt/validateTokenSequence trie (list "(:phase" ":name"))) "Truncated phase sequence must be rejected")
    true))

(df runTests [] -> Bool
  :d "Executes all unit tests in grammar trie test suite"
  (assert (testTrieConstruction) "test-trie-construction must pass")
  (assert (testComputeValidRootTokens) "test-compute-valid-root-tokens must pass")
  (assert (testComputeValidSubsequentTokens) "test-compute-valid-subsequent-tokens must pass")
  (assert (testMultiRuleBranching) "test-multi-rule-branching must pass")
  (assert (testValidateTokenSequenceValid) "test-validate-token-sequence-valid must pass")
  (assert (testValidateTokenSequenceInvalid) "test-validate-token-sequence-invalid must pass")
  (assert (testValidateTokenSequenceTerminal) "test-validate-token-sequence-terminal must pass")
  true)
