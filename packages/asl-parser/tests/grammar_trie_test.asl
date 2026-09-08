(module asl-parser/tests/grammar-trie-test
  :d "Unit tests for in-memory grammar trie constrained decoding under strict falsification"
  :x [test-trie-construction
      test-compute-valid-root-tokens
      test-compute-valid-subsequent-tokens
      test-multi-rule-branching
      test-validate-token-sequence-valid
      test-validate-token-sequence-invalid
      test-validate-token-sequence-terminal
      run-tests]
  :i [(grammar_trie :a gt)])

(df test-trie-construction [] -> Bool
  :d "Verifies grammar trie node initialization from structured ASN rules"
  (let [(rules (list "(:task :id :title :gate)" "(:phase :name :state)"))
        (trie (gt/build-grammar-trie rules))]
    (assert (= (.-token-id trie) "ROOT") "Root token-id must be ROOT")
    (assert (= (.-terminal trie) false) "Root terminal must be false")
    (assert (= (.-mask-id trie) 0) "Root mask-id must be 0")
    (assert (> (list-length (.-allowed-transitions trie)) 0) "Transitions list must not be empty")
    (assert (list-contains? (.-allowed-transitions trie) "START->(:task") "Must contain start transition for (:task")
    (assert (list-contains? (.-allowed-transitions trie) ":gate->END") "Must contain terminal transition for :gate")
    true))

(df test-compute-valid-root-tokens [] -> Bool
  :d "Verifies exact admitted root tokens for empty, START, and ROOT prefixes"
  (let [(rules (list "(:task :id :title :gate)" "(:phase :name :state)"))
        (trie (gt/build-grammar-trie rules))]
    (assert (= (list-length (gt/compute-valid-tokens trie "")) 2) "Empty prefix must yield 2 root tokens")
    (assert (list-contains? (gt/compute-valid-tokens trie "") "(:task") "Admitted root tokens must contain (:task")
    (assert (list-contains? (gt/compute-valid-tokens trie "") "(:phase") "Admitted root tokens must contain (:phase")
    (assert (= (list-length (gt/compute-valid-tokens trie "START")) 2) "START prefix must yield 2 root tokens")
    (assert (= (list-length (gt/compute-valid-tokens trie "ROOT")) 2) "ROOT prefix must yield 2 root tokens")
    (assert (= (list-length (gt/compute-valid-tokens trie ":invalid")) 0) "Disallowed start token must yield empty valid tokens")
    true))

(df test-compute-valid-subsequent-tokens [] -> Bool
  :d "Verifies sequential next token transitions and terminal boundary conditions"
  (let [(rules (list "(:task :id :title :gate)" "(:phase :name :state)"))
        (trie (gt/build-grammar-trie rules))]
    (assert (list-contains? (gt/compute-valid-tokens trie "(:task") ":id") "Following (:task must allow :id")
    (assert (= (list-length (gt/compute-valid-tokens trie "(:task")) 1) "Following (:task must only allow :id")
    (assert (list-contains? (gt/compute-valid-tokens trie ":id") ":title") "Following :id must allow :title")
    (assert (list-contains? (gt/compute-valid-tokens trie ":title") ":gate") "Following :title must allow :gate")
    (assert (= (list-length (gt/compute-valid-tokens trie ":gate")) 0) "Terminal :gate must have no further non-terminal transitions")
    (assert (= (list-length (gt/compute-valid-tokens trie "unknown-prefix")) 0) "Unknown prefix must yield empty list")
    true))

(df test-multi-rule-branching [] -> Bool
  :d "Verifies trie branching when multiple rules share a common prefix"
  (let [(rules (list "(:node :id :name)" "(:node :id :value)"))
        (trie (gt/build-grammar-trie rules))]
    (assert (= (list-length (gt/compute-valid-tokens trie ":id")) 2) "Branching :id must yield 2 choices")
    (assert (list-contains? (gt/compute-valid-tokens trie ":id") ":name") "Branching choices must contain :name")
    (assert (list-contains? (gt/compute-valid-tokens trie ":id") ":value") "Branching choices must contain :value")
    (assert (= (list-length (gt/compute-valid-tokens trie "(:node")) 1) "(:node must yield only :id")
    (assert (= (list-length (gt/compute-valid-tokens trie ":name")) 0) ":name must have no further non-terminal transitions")
    true))

(df test-validate-token-sequence-valid [] -> Bool
  :d "Verifies sequence validator succeeds on full valid sequences"
  (let [(rules (list "(:task :id :title :gate)" "(:phase :name :state)"))
        (trie (gt/build-grammar-trie rules))
        (rules2 (list "(:task :id :title :gate)" "(:atom)"))
        (trie2 (gt/build-grammar-trie rules2))]
    (assert (gt/validate-token-sequence trie (list "(:task" ":id" ":title" ":gate")) "Full valid task sequence must pass")
    (assert (gt/validate-token-sequence trie (list "(:phase" ":name" ":state")) "Full valid phase sequence must pass")
    (assert (gt/validate-token-sequence trie2 (list "(:atom")) "Single token rule sequence must pass")
    (assert (gt/validate-token-sequence trie (list "  (:task  " " :id " " :title " " :gate) ")) "Whitespace-padded tokens must pass")
    (assert (gt/validate-token-sequence trie2 (list "(:task" ":id" ":title" ":gate")) "Valid task sequence on multi-rule trie must pass")
    true))

(df test-validate-token-sequence-invalid [] -> Bool
  :d "Verifies sequence validator rejects sequences with illegal steps or start tokens"
  (let [(rules (list "(:task :id :title :gate)" "(:phase :name :state)"))
        (trie (gt/build-grammar-trie rules))]
    (assert (not (gt/validate-token-sequence trie (list))) "Empty token sequence must be rejected")
    (assert (not (gt/validate-token-sequence trie (list ":invalid" ":id" ":title" ":gate"))) "Sequence starting with invalid token must be rejected")
    (assert (not (gt/validate-token-sequence trie (list "(:task" ":state" ":title" ":gate"))) "Sequence with illegal middle transition must be rejected")
    (assert (not (gt/validate-token-sequence trie (list "(:task" ":unknown-tok"))) "Sequence with unknown vocabulary token must be rejected")
    (assert (not (gt/validate-token-sequence trie (list "(:task" ":id" ":title" ":state"))) "Sequence ending in mismatched terminal must be rejected")
    (assert (not (gt/validate-token-sequence trie (list "(:phase" ":id" ":state"))) "Sequence mixing branches illegally must be rejected")
    true))

(df test-validate-token-sequence-terminal [] -> Bool
  :d "Verifies sequence validator rejects truncated sequences that do not reach terminal state"
  (let [(rules (list "(:task :id :title :gate)" "(:phase :name :state)"))
        (trie (gt/build-grammar-trie rules))]
    (assert (not (gt/validate-token-sequence trie (list "(:task"))) "Single non-terminal start token must be rejected")
    (assert (not (gt/validate-token-sequence trie (list "(:task" ":id"))) "Truncated two-token sequence must be rejected")
    (assert (not (gt/validate-token-sequence trie (list "(:task" ":id" ":title"))) "Truncated three-token sequence must be rejected")
    (assert (not (gt/validate-token-sequence trie (list "(:phase" ":name"))) "Truncated phase sequence must be rejected")
    true))

(df run-tests [] -> Bool
  :d "Executes all unit tests in grammar trie test suite"
  (assert (test-trie-construction) "test-trie-construction must pass")
  (assert (test-compute-valid-root-tokens) "test-compute-valid-root-tokens must pass")
  (assert (test-compute-valid-subsequent-tokens) "test-compute-valid-subsequent-tokens must pass")
  (assert (test-multi-rule-branching) "test-multi-rule-branching must pass")
  (assert (test-validate-token-sequence-valid) "test-validate-token-sequence-valid must pass")
  (assert (test-validate-token-sequence-invalid) "test-validate-token-sequence-invalid must pass")
  (assert (test-validate-token-sequence-terminal) "test-validate-token-sequence-terminal must pass")
  true)
