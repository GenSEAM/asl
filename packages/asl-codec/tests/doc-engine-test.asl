(module asl-codec/doc-engine-test
  :d "Unit verification test suite for ASN Documentation Schema and Dual-Target Compiler."
  :x [test-create-doc-module
      test-compile-doc-to-markdown
      test-extract-agent-doc-stub
      test-extract-missing-symbol
      test-estimate-doc-token-savings
      run-doc-engine-tests]
  :i [(doc-engine :a de)])

(df test-create-doc-module [] -> Bool
  :d "Tests initializing a DocModule with symbols and invariants."
  (let [(s1 (de/create-doc-symbol "wire-encode" "fn" "[(WireFrame)] -> Str" "Encodes frame to wire"))
        (m1 (de/create-doc-module "asl-bus/wire" "Wire Protocol" "High serialization latency" "Binary ASB" (list "Pure ASL" "Zero Foreign") (list s1)))]
    (and (= (.-module-id m1) "asl-bus/wire")
         (= (length (.-symbols m1)) 1)
         (= (length (.-invariants m1)) 2))))

(df test-compile-doc-to-markdown [] -> Bool
  :d "Tests compiling DocModule into human-readable Markdown."
  (let [(s1 (de/create-doc-symbol "bus-join" "fn" "[(SwarmRoom) (SwarmPeer)] -> SwarmRoom" "Joins peer to room"))
        (m1 (de/create-doc-module "asl-bus/presence" "Room Presence" "No presence discovery" "In-memory rooms" (list "Deterministic") (list s1)))
        (md (de/compile-doc-to-markdown m1))]
    (and (string-contains? md "# Room Presence")
         (string-contains? md "## Problem Solved")
         (string-contains? md "## Solution & Architecture")
         (string-contains? md "## API Reference")
         (string-contains? md "`bus-join`"))))

(df test-extract-agent-doc-stub [] -> Bool
  :d "Tests extracting token-dense ASN stub for an agent."
  (let [(s1 (de/create-doc-symbol "bus-who" "fn" "[(SwarmRoom)] -> (List SwarmPeer)" "Lists online peers"))
        (m1 (de/create-doc-module "asl-bus/presence" "Room Presence" "No peer list" "Query peer list" (list "Non-blocking") (list s1)))
        (stub-opt (de/extract-agent-doc-stub m1 "bus-who"))]
    (mt stub-opt
      ((none) false)
      ((some stub)
       (and (string-contains? stub ":doc-stub :mod \"asl-bus/presence\"")
            (string-contains? stub ":sym \"bus-who\"")
            (string-contains? stub ":rules [\"Non-blocking\"]"))))))

(df test-extract-missing-symbol [] -> Bool
  :d "Tests that querying non-existent symbol returns none."
  (let [(m1 (de/create-doc-module "test/mod" "Title" "Prob" "Sol" (list) (list)))
        (stub-opt (de/extract-agent-doc-stub m1 "missing-symbol"))]
    (option-is-none? stub-opt)))

(df test-estimate-doc-token-savings [] -> Bool
  :d "Tests that agent stubs achieve substantial token reduction over markdown prose."
  (let [(s1 (de/create-doc-symbol "transpile-json" "fn" "[(Str)] -> Str" "Converts JSON to ASN"))
        (m1 (de/create-doc-module "asl-codec/transpile" "Transpile Engine"
                                  "JSON uses too many tokens in context window for LLMs"
                                  "Transpile to dense S-expressions to cut tokens by 72%"
                                  (list "100% Pure ASL" "Strict Validation")
                                  (list s1)))
        (savings (de/estimate-doc-token-savings m1))]
    (> savings 50.0)))

(df run-doc-engine-tests [] -> Bool
  :d "Runs all doc engine unit tests."
  (and (test-create-doc-module)
       (test-compile-doc-to-markdown)
       (test-extract-agent-doc-stub)
       (test-extract-missing-symbol)
       (test-estimate-doc-token-savings)))
