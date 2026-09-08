(module asl-codec/doc-engine-test
  :d "Unit verification test suite for ASN Documentation Schema and Dual-Target Compiler."
  :x [test-create-doc-module
      test-compile-doc-to-markdown
      test-extract-agent-doc-stub
      test-extract-missing-symbol
      test-estimate-doc-token-savings
      run-doc-engine-tests
      run-tests]
  :i [(doc-engine :a de)])

(df test-create-doc-module [] -> Bool
  :d "Tests initializing a DocModule with symbols and invariants."
  (let [(s1 (de/create-doc-symbol "wire-encode" "fn" "[(WireFrame)] -> Str" "Encodes frame to wire"))
        (m1 (de/create-doc-module "asl-bus/wire" "Wire Protocol" "High serialization latency" "Binary ASB" (list "Pure ASL" "Zero Foreign") (list s1)))]
    (assert (= (.-module-id m1) "asl-bus/wire") "module-id must match")
    (assert (= (list-length (.-symbols m1)) 1) "symbols count must be 1")
    (assert (= (list-length (.-invariants m1)) 2) "invariants count must be 2")
    (assert (not (string-contains? (.-module-id m1) "unknown")) "module-id not unknown")
    true))

(df test-compile-doc-to-markdown [] -> Bool
  :d "Tests compiling DocModule into human-readable Markdown."
  (let [(s1 (de/create-doc-symbol "bus-join" "fn" "[(SwarmRoom) (SwarmPeer)] -> SwarmRoom" "Joins peer to room"))
        (m1 (de/create-doc-module "asl-bus/presence" "Room Presence" "No presence discovery" "In-memory rooms" (list "Deterministic") (list s1)))
        (md (de/compile-doc-to-markdown m1))]
    (assert (string-contains? md "# Room Presence") "md must contain title")
    (assert (string-contains? md "## Problem Solved") "md must contain problem")
    (assert (string-contains? md "## Solution & Architecture") "md must contain solution")
    (assert (string-contains? md "## API Reference") "md must contain api ref")
    (assert (string-contains? md "`bus-join`") "md must contain bus-join")
    (assert (not (string-contains? md "NonExistentHeading")) "md has no non-existent heading")
    true))

(df test-extract-agent-doc-stub [] -> Bool
  :d "Tests extracting token-dense ASN stub for an agent."
  (let [(s1 (de/create-doc-symbol "bus-who" "fn" "[(SwarmRoom)] -> (List SwarmPeer)" "Lists online peers"))
        (m1 (de/create-doc-module "asl-bus/presence" "Room Presence" "No peer list" "Query peer list" (list "Non-blocking") (list s1)))
        (stub-opt (de/extract-agent-doc-stub m1 "bus-who"))]
    (mt stub-opt
      ((none) false)
      ((some stub)
       (do
         (assert (string-contains? stub ":doc-stub :mod \"asl-bus/presence\"") "stub has mod")
         (assert (string-contains? stub ":sym \"bus-who\"") "stub has sym")
         (assert (string-contains? stub ":rules [\"Non-blocking\"]") "stub has rules")
         (assert (not (string-contains? stub "invalid-rule")) "stub has no invalid rules")
         true)))))

(df test-extract-missing-symbol [] -> Bool
  :d "Tests querying existent and non-existent symbols."
  (let [(s1 (de/create-doc-symbol "present-sym" "fn" "[] -> Str" "Present"))
        (m1 (de/create-doc-module "test/mod" "Title" "Prob" "Sol" (list) (list s1)))
        (missing-opt (de/extract-agent-doc-stub m1 "missing-symbol"))
        (present-opt (de/extract-agent-doc-stub m1 "present-sym"))]
    (assert (option-is-none? missing-opt) "missing symbol must be none")
    (assert (not (option-is-none? present-opt)) "present symbol must not be none")
    true))

(df test-estimate-doc-token-savings [] -> Bool
  :d "Tests that agent stubs achieve substantial token reduction over markdown prose."
  (let [(s1 (de/create-doc-symbol "transpile-json" "fn" "[(Str)] -> Str" "Converts JSON to ASN"))
        (m1 (de/create-doc-module "asl-codec/transpile" "Transpile Engine"
                                  "JSON uses too many tokens in context window for LLMs"
                                  "Transpile to dense S-expressions to cut tokens by 72%"
                                  (list "100% Pure ASL" "Strict Validation")
                                  (list s1)))
        (savings (de/estimate-doc-token-savings m1))]
    (assert (> savings 50.0) "savings must be > 50%")
    (assert (not (<= savings 0.0)) "savings must not be zero or negative")
    true))

(df run-doc-engine-tests [] -> Bool
  :d "Runs all doc engine unit tests."
  (run-tests))

(df run-tests [] -> Bool
  :d "Runs all doc engine unit tests."
  (do
    (assert (test-create-doc-module) "test-create-doc-module must pass")
    (assert (test-compile-doc-to-markdown) "test-compile-doc-to-markdown must pass")
    (assert (test-extract-agent-doc-stub) "test-extract-agent-doc-stub must pass")
    (assert (test-extract-missing-symbol) "test-extract-missing-symbol must pass")
    (assert (test-estimate-doc-token-savings) "test-estimate-doc-token-savings must pass")
    true))
