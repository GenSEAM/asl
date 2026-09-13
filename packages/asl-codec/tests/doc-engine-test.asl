(module asl-codec/docEngineTest
  :d "Unit verification test suite for ASN Documentation Schema and Dual-Target Compiler."
  :x [testCreateDocModule
      testCompileDocToMarkdown
      testExtractAgentDocStub
      testExtractMissingSymbol
      testEstimateDocTokenSavings
      runDocEngineTests
      runTests]
  :i [(asl-codec/docEngine :a de)])

(df testCreateDocModule [] -> Bool
  :d "Tests initializing a DocModule with symbols and invariants."
  (let [(s1 (de/createDocSymbol "wire-encode" "fn" "[(WireFrame)] -> Str" "Encodes frame to wire"))
        (m1 (de/createDocModule "asl-bus/wire" "Wire Protocol" "High serialization latency" "Binary ASB" (list "Pure ASL" "Zero Foreign") (list s1)))]
    (assert (= (.-moduleId m1) "asl-bus/wire") "module-id must match")
    (assert (= (list-length (.-symbols m1)) 1) "symbols count must be 1")
    (assert (= (list-length (.-invariants m1)) 2) "invariants count must be 2")
    (assert (not (string-contains? (.-moduleId m1) "unknown")) "module-id not unknown")
    true))

(df testCompileDocToMarkdown [] -> Bool
  :d "Tests compiling DocModule into human-readable Markdown."
  (let [(s1 (de/createDocSymbol "bus-join" "fn" "[(SwarmRoom) (SwarmPeer)] -> SwarmRoom" "Joins peer to room"))
        (m1 (de/createDocModule "asl-bus/presence" "Room Presence" "No presence discovery" "In-memory rooms" (list "Deterministic") (list s1)))
        (md (de/compileDocToMarkdown m1))]
    (assert (string-contains? md "# Room Presence") "md must contain title")
    (assert (string-contains? md "## Problem Solved") "md must contain problem")
    (assert (string-contains? md "## Solution & Architecture") "md must contain solution")
    (assert (string-contains? md "## API Reference") "md must contain api ref")
    (assert (string-contains? md "`bus-join`") "md must contain bus-join")
    (assert (not (string-contains? md "NonExistentHeading")) "md has no non-existent heading")
    true))

(df testExtractAgentDocStub [] -> Bool
  :d "Tests extracting token-dense ASN stub for an agent."
  (let [(s1 (de/createDocSymbol "bus-who" "fn" "[(SwarmRoom)] -> (List SwarmPeer)" "Lists online peers"))
        (m1 (de/createDocModule "asl-bus/presence" "Room Presence" "No peer list" "Query peer list" (list "Non-blocking") (list s1)))
        (stubOpt (de/extractAgentDocStub m1 "bus-who"))]
    (mt stubOpt
      ((none) false)
      ((some stub)
       (do
         (assert (string-contains? stub ":doc-stub :mod \"asl-bus/presence\"") "stub has mod")
         (assert (string-contains? stub ":sym \"bus-who\"") "stub has sym")
         (assert (string-contains? stub ":rules [\"Non-blocking\"]") "stub has rules")
         (assert (not (string-contains? stub "invalid-rule")) "stub has no invalid rules")
         true)))))

(df testExtractMissingSymbol [] -> Bool
  :d "Tests querying existent and non-existent symbols."
  (let [(s1 (de/createDocSymbol "present-sym" "fn" "[] -> Str" "Present"))
        (m1 (de/createDocModule "test/mod" "Title" "Prob" "Sol" (list) (list s1)))
        (missingOpt (de/extractAgentDocStub m1 "missing-symbol"))
        (presentOpt (de/extractAgentDocStub m1 "present-sym"))]
    (assert (optionIsNone? missingOpt) "missing symbol must be none")
    (assert (not (optionIsNone? presentOpt)) "present symbol must not be none")
    true))

(df testEstimateDocTokenSavings [] -> Bool
  :d "Tests that agent stubs achieve substantial token reduction over markdown prose."
  (let [(s1 (de/createDocSymbol "transpile-json" "fn" "[(Str)] -> Str" "Converts JSON to ASN"))
        (m1 (de/createDocModule "asl-codec/transpile" "Transpile Engine"
                                  "JSON uses too many tokens in context window for LLMs"
                                  "Transpile to dense S-expressions to cut tokens by 72%"
                                  (list "100% Pure ASL" "Strict Validation")
                                  (list s1)))
        (savings (de/estimateDocTokenSavings m1))]
    (assert (> savings 50.0) "savings must be > 50%")
    (assert (not (<= savings 0.0)) "savings must not be zero or negative")
    true))

(df runDocEngineTests [] -> Bool
  :d "Runs all doc engine unit tests."
  (runTests))

(df runTests [] -> Bool
  :d "Runs all doc engine unit tests."
  (do
    (assert (testCreateDocModule) "test-create-doc-module must pass")
    (assert (testCompileDocToMarkdown) "test-compile-doc-to-markdown must pass")
    (assert (testExtractAgentDocStub) "test-extract-agent-doc-stub must pass")
    (assert (testExtractMissingSymbol) "test-extract-missing-symbol must pass")
    (assert (testEstimateDocTokenSavings) "test-estimate-doc-token-savings must pass")
    true))
