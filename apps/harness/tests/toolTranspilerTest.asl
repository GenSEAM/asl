(module aslHarness/toolTranspilerTest :x [testCompactToolSchema testJsonToolCallToAsn testAsnToToolResult testMeasureToolCompaction runTests] :i [(toolTranspiler :a tt)])

fn testCompactToolSchema -> Bool
  (let [(sig (tt/compactToolSchema "fs-read" (list "path Str" "line I64") "Str"))] (assert (stringContains? sig "(tool fs-read") "contains tool fs-read") (assert (stringContains? sig "[:path Str :line I64] -> Str)") "contains signature") true)

fn testJsonToolCallToAsn -> Bool
  (let [(asn (tt/jsonToolCallToAsn "fs-read" "{\"path\": \"src/main.asl\", \"line\": 42}"))] (assert (stringContains? asn "(! fs-read") "contains invocation frame") (assert (stringContains? asn ":path src/main.asl") "contains :path argument") true)

fn testAsnToToolResult -> Bool
  (let [(res (tt/asnToToolResult "call_99" "File read successfully" false))] (assert (stringContains? res "\"type\": \"tool_result\"") "contains tool_result type") (assert (stringContains? res "\"tool_use_id\": \"call_99\"") "contains tool_use_id") true)

fn testMeasureToolCompaction -> Bool
  (let [(jsonCall "{\"role\": \"assistant\", \"tool_calls\": [{\"id\": \"call_123\", \"type\": \"function\", \"function\": {\"name\": \"fs-read\", \"arguments\": \"{\\\"path\\\": \\\"packages/asl-codec/src/transpile.asl\\\", \\\"start_line\\\": 1, \\\"end_line\\\": 100}\"}}]} ") (asnCall "(! fs-read :path \"packages/asl-codec/src/transpile.asl\" :start 1 :end 100)") (res (tt/measureToolCompaction "fs-read" jsonCall asnCall))] (assert (> res.jsonTokens res.asnTokens) "json tokens > asn tokens") (assert (>= res.savingsPercent 50.0) "savings percent >= 50") true)

fn runTests -> Bool
  (do (testCompactToolSchema) (testJsonToolCallToAsn) (testAsnToToolResult) (testMeasureToolCompaction) true)
