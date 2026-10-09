(module aslAgentCore/toolcallTest :x [runTests] :i [(protocol :a proto) (dispatch :a disp)])

fn sampleRegistry -> disp/ToolRegistry
  (let [(pQ (proto/ToolParam :name "q" :paramType "Str" :required true :doc "Search query string")) (pLimit (proto/ToolParam :name "limit" :paramType "I64" :required false :doc "Max results count")) (searchTool (proto/ToolDef :name "search" :doc "Web and ecosystem search" :params (list pQ pLimit))) (pUrl (proto/ToolParam :name "url" :paramType "Str" :required true :doc "Target URL")) (fetchTool (proto/ToolDef :name "fetch" :doc "HTTP document fetcher" :params (list pUrl))) (emptyReg (disp/ToolRegistry :tools (list) :handlers (list)))] (disp/registerTool (disp/registerTool emptyReg searchTool) fetchTool))

fn testFormatToolDef -> Bool
  (let [(pQ (proto/ToolParam :name "q" :paramType "Str" :required true :doc "Search query")) (pLimit (proto/ToolParam :name "limit" :paramType "I64" :required false :doc "Max count")) (tdef (proto/ToolDef :name "search" :doc "Web search" :params (list pQ pLimit))) (spec (proto/formatToolDef tdef))] (assert (stringContains? spec "(tool :search") "Tool spec must contain (tool :search") (assert (stringContains? spec ":q! Str") "Tool spec must contain :q! Str") (assert (stringContains? spec ":limit I64") "Tool spec must contain :limit I64") true)

fn testParseInvocation -> Bool
  (let [(raw "(call :tool search :q \"agentscript language\" :limit 5)") (res (proto/parseInvocation raw))] (mt res ((err e) (do (assert false (str "parse-invocation failed: " e)) false)) ((ok inv) (do (assert (= inv.toolName "search") "Tool name must equal search") (assert (= (optionOr (proto/getArgValue inv.args "q") "") "agentscript language") "Arg q must match") (assert (= (optionOr (proto/getArgValue inv.args "limit") "") "5") "Arg limit must match 5") true))))

fn testValidateInvocation -> Bool
  (let [(reg (sampleRegistry)) (invValid (proto/ToolInvocation :toolName "search" :args (list (proto/ToolArg :key "q" :val "test")) :rawCall "(call :tool search :q \"test\")")) (invMissing (proto/ToolInvocation :toolName "search" :args (list (proto/ToolArg :key "limit" :val "10")) :rawCall "(call :tool search :limit 10)")) (invUnknown (proto/ToolInvocation :toolName "non-existent" :args (list) :rawCall "(call :tool non-existent)"))] (let [(resValid (disp/validateInvocation reg invValid)) (resMissing (disp/validateInvocation reg invMissing)) (resUnknown (disp/validateInvocation reg invUnknown))] (assert (ok? resValid) "Valid invocation must be ok") (assert (err? resMissing) "Missing arg invocation must be err") (assert (stringContains? (mt resMissing ((ok _) "") ((err e) e)) "Missing required argument: q") "Error msg must cite missing q") (assert (err? resUnknown) "Unknown tool invocation must be err") (assert (stringContains? (mt resUnknown ((ok _) "") ((err e) e)) "Unknown tool: non-existent") "Error msg must cite unknown tool") true))

fn testUnknownHandler -> Bool
  (let [(reg (sampleRegistry)) (raw "(call :tool search :q \"agentscript\" :limit 3)") (out (disp/dispatchCall reg raw))] (assert (stringContains? out "(result :tool search :ok false") "Dispatch without a registered handler must fail") (assert (stringContains? out "Missing handler: search") "Dispatch error must name missing handler") (not (stringContains? out "Executed tool search dynamically.")))

fn testDispatchError -> Bool
  (let [(reg (sampleRegistry)) (raw "(call :tool search :limit 5)") (out (disp/dispatchCall reg raw))] (assert (stringContains? out "(result :tool search :ok false") "Dispatch output must report ok false") (assert (stringContains? out "Missing required argument: q") "Dispatch output must cite missing q") true)

fn testDispatchBatch -> Bool
  (let [(reg (sampleRegistry)) (calls (list "(call :tool search :q \"lang\" :limit 2)" "(call :tool fetch :url \"https://asl.dev\")")) (results (disp/dispatchBatchCalls reg calls))] (assert (= (listLength results) 2) "Batch call must return 2 results") (assert (stringContains? (optionOr (listHead results) "") "(result :tool search :ok false") "First batch result must report its missing handler") (assert (stringContains? (optionOr (listHead results) "") "Missing handler: search") "First batch error must name missing handler") (assert (stringContains? (optionOr (listHead (optionOr (listTail results) (list))) "") "(result :tool fetch :ok false") "Second batch result must report its missing handler") true)

fn runTests -> Bool
  (do (assert (testFormatToolDef) "test-format-tool-def must pass") (assert (testParseInvocation) "test-parse-invocation must pass") (assert (testValidateInvocation) "test-validate-invocation must pass") (assert (testUnknownHandler) "test-unknown-handler must pass") (assert (testDispatchError) "test-dispatch-error must pass") (assert (testDispatchBatch) "test-dispatch-batch must pass") true)
