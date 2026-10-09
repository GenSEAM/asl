(module asl-transpile/docEngineTest :x [testCreateDocModule testCompileDocToMarkdown testExtractAgentDocStub testExtractMissingSymbol testEstimateDocTokenSavings runDocEngineTests runTests] :i [(asl-transpile/docEngine :a de)])

fn testCreateDocModule -> Bool
  (let [(s1 (de/createDocSymbol "wire-encode" "fn" "[(WireFrame)] -> Str" "Encodes frame to wire")) (m1 (de/createDocModule "asl-bus/wire" "Wire Protocol" "High serialization latency" "Binary ASB" (list "Pure ASL" "Zero Foreign") (list s1)))] (assert (= m1.moduleId "asl-bus/wire") "module-id must match") (assert (= (listLength m1.symbols) 1) "symbols count must be 1") (assert (= (listLength m1.invariants) 2) "invariants count must be 2") (assert (not (stringContains? m1.moduleId "unknown")) "module-id not unknown") true)

fn testCompileDocToMarkdown -> Bool
  (let [(s1 (de/createDocSymbol "bus-join" "fn" "[(SwarmRoom) (SwarmPeer)] -> SwarmRoom" "Joins peer to room")) (m1 (de/createDocModule "asl-bus/presence" "Room Presence" "No presence discovery" "In-memory rooms" (list "Deterministic") (list s1))) (md (de/compileDocToMarkdown m1))] (assert (stringContains? md "# Room Presence") "md must contain title") (assert (stringContains? md "## Problem Solved") "md must contain problem") (assert (stringContains? md "## Solution & Architecture") "md must contain solution") (assert (stringContains? md "## API Reference") "md must contain api ref") (assert (stringContains? md "`bus-join`") "md must contain bus-join") (assert (not (stringContains? md "NonExistentHeading")) "md has no non-existent heading") true)

fn testExtractAgentDocStub -> Bool
  (let [(s1 (de/createDocSymbol "bus-who" "fn" "[(SwarmRoom)] -> (List SwarmPeer)" "Lists online peers")) (m1 (de/createDocModule "asl-bus/presence" "Room Presence" "No peer list" "Query peer list" (list "Non-blocking") (list s1))) (stubOpt (de/extractAgentDocStub m1 "bus-who"))] (mt stubOpt ((none) false) ((some stub) (do (assert (stringContains? stub ":doc-stub :mod \"asl-bus/presence\"") "stub has mod") (assert (stringContains? stub ":sym \"bus-who\"") "stub has sym") (assert (stringContains? stub ":rules [\"Non-blocking\"]") "stub has rules") (assert (not (stringContains? stub "invalid-rule")) "stub has no invalid rules") true))))

fn testExtractMissingSymbol -> Bool
  (let [(s1 (de/createDocSymbol "present-sym" "fn" "[] -> Str" "Present")) (m1 (de/createDocModule "test/mod" "Title" "Prob" "Sol" (list) (list s1))) (missingOpt (de/extractAgentDocStub m1 "missing-symbol")) (presentOpt (de/extractAgentDocStub m1 "present-sym"))] (assert (none? missingOpt) "missing symbol must be none") (assert (not (none? presentOpt)) "present symbol must not be none") true)

fn testEstimateDocTokenSavings -> Bool
  (let [(s1 (de/createDocSymbol "transpile-json" "fn" "[(Str)] -> Str" "Converts JSON to ASN")) (m1 (de/createDocModule "asl-transpile/transpile" "Transpile Engine" "JSON uses too many tokens in context window for LLMs" "Transpile to dense S-expressions to cut tokens by 72%" (list "100% Pure ASL" "Strict Validation") (list s1))) (savings (de/estimateDocTokenSavings m1))] (assert (> savings 50.0) "savings must be > 50%") (assert (not (<= savings 0.0)) "savings must not be zero or negative") true)

fn runDocEngineTests -> Bool
  (runTests)

fn runTests -> Bool
  (do (assert (testCreateDocModule) "test-create-doc-module must pass") (assert (testCompileDocToMarkdown) "test-compile-doc-to-markdown must pass") (assert (testExtractAgentDocStub) "test-extract-agent-doc-stub must pass") (assert (testExtractMissingSymbol) "test-extract-missing-symbol must pass") (assert (testEstimateDocTokenSavings) "test-estimate-doc-token-savings must pass") true)
