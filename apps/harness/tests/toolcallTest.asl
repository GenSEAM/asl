(module aslHarness/toolcallTest :x [runTests testToolcall] :i [(coding :a c) (toolcall :a tc)])

fn testToolSchemaTyping -> Bool
  (let [(t (c/BuiltinTool :name "test-tool" :description "Test tool description" :params (list (c/ToolParam :name "file-path" :paramType "Str" :required true :doc "Path to file") (c/ToolParam :name "line-count" :paramType "I64" :required true :doc "Number of lines") (c/ToolParam :name "dry-run" :paramType "Bool" :required false :doc "Dry run mode")) :deterministic true)) (schema (tc/toolToOpenaiSchema t)) (json schema.parametersJson)] (assert (stringContains? json "\"file_path\": {\"type\": \"string\"") "schema has file_path string") (assert (stringContains? json "\"line_count\": {\"type\": \"integer\"") "schema has line_count integer") (assert (stringContains? json "\"dry_run\": {\"type\": \"boolean\"") "schema has dry_run boolean") (assert (stringContains? json "\"required\": [\"file_path\", \"line_count\"]") "schema has required array") (assert (not (stringContains? json ", }")) "no trailing comma before }") (assert (not (stringContains? json ", ]")) "no trailing comma before ]") true)

fn testParseOpenaiToolCall -> Bool
  (let [(call (tc/OpenAiToolCall :id "call_001" :functionName "fs_read" :argumentsJson "{\"path\": \"src/main.asl\", \"line_count\": 50}")) (parsed (tc/parseOpenaiToolCall call)) (args parsed.arguments) (headPair (optionOr (listHead args) (pair "" "")))] (assert (= parsed.id "call_001") "id is call_001") (assert (= parsed.toolName "fs-read") "tool-name is fs-read") (assert (= (listLength args) 2) "args length is 2") (assert (= (pairFirst headPair) "path") "first arg key is path") (assert (= (pairSecond headPair) "src/main.asl") "first arg val is src/main.asl") true)

fn testAsnCallToOpenaiJson -> Bool
  (let [(call (c/ToolCall :id "call_002" :toolName "fs-write" :arguments (list (pair "path" "output.txt") (pair "content" "hello")))) (json (tc/asnCallToOpenaiJson call))] (assert (stringContains? json "\"id\": \"call_002\"") "json has id call_002") (assert (stringContains? json "\"name\": \"fs_write\"") "json has name fs_write") (assert (stringContains? json "output.txt") "json has path output.txt") (assert (not (stringContains? json ", }")) "no trailing comma before }") true)

fn testToolsToOpenaiJson -> Bool
  (let [(tools (c/standardCodingTools)) (json (tc/toolsToOpenaiJson tools))] (assert (stringStartsWith? json "[") "starts with [") (assert (stringEndsWith? json "]") "ends with ]") (assert (not (stringContains? json ", ]")) "no trailing comma before ]") (assert (stringContains? json "\"name\": \"fs_read\"") "contains fs_read") true)

fn testAgentRpcSurface -> Bool
  (let [(tools (c/standardCodingTools)) (policy (tc/defaultAgentToolPolicy)) (json (tc/agentToolsToOpenaiJson tools)) (direct (tc/enforceAgentToolCall (c/ToolCall :id "direct-1" :toolName "fs-read" :arguments (list)))) (batch (tc/enforceAgentToolCall (c/ToolCall :id "batch-1" :toolName "rpc-batch" :arguments (list))))] (assert policy.rpcDescriptionVisible "rpc description visible") (assert (not policy.commandDescriptionVisible) "command descriptions hidden") (assert policy.allCommandsMapped "all commands mapped to rpc") (assert policy.batchRequired "batch calls required") (assert (stringContains? json "\"name\": \"rpc_batch\"") "rpc_batch is the only agent tool") (assert (stringContains? json "RPC operation descriptions") "rpc description is present") (assert (not (stringContains? json "fs_read")) "direct fs_read is hidden") (assert (not (stringContains? json "exec_cmd")) "direct exec_cmd is hidden") (assert (tc/allCommandsRpcMapped? tools) "every builtin has rpc mapping") (assert (not direct.success) "direct tool call rejected") (assert batch.success "rpc batch call accepted") true)

fn testToolcall -> Bool
  (do (assert (testToolSchemaTyping) "tool schema typing verified") (assert (testParseOpenaiToolCall) "parse openai tool call verified") (assert (testAsnCallToOpenaiJson) "asn call to openai json verified") (assert (testToolsToOpenaiJson) "tools to openai json verified") (assert (testAgentRpcSurface) "agent rpc surface verified") true)

fn runTests -> Bool
  (testToolcall)
