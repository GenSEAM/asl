(module aslHarness/localExec :x [ExecutionTier L0Local tierLocalWasm tierLocalHost tierRemoteLlm RouteDecision shouldExecuteLocally routeAndExecute! formatSavingsReport] :i [(coding :a c)])

(enum ExecutionTier (:c L0Local [] "L0 Local Tier") (:c tierLocalWasm [] "Direct in-memory WebAssembly / runtime execution") (:c tierLocalHost [] "Direct OS process execution in isolated sandbox") (:c tierRemoteLlm [] "Delegation to remote model endpoint"))

(schema RouteDecision (:f toolName Str) (:f tier ExecutionTier) (:f estimatedSavingsTokens I64) (:f estimatedLatencyMs I64) (:f explanation Str))

fn shouldExecuteLocally toolName: Str -> Bool
  (or (= toolName "fs-read") (or (= toolName "fs-list") (or (= toolName "git-status") (or (= toolName "ast-search") (or (= toolName "ast-patch") (or (= toolName "str-replace") (or (= toolName "intel-preload") (or (= toolName "intel-impact") (or (= toolName "intel-health") (= toolName "deps-resolve"))))))))))

fn planRoute toolName: Str -> RouteDecision
  (if (shouldExecuteLocally toolName) (RouteDecision :toolName toolName :tier (tierLocalWasm) :estimatedSavingsTokens 650 :estimatedLatencyMs 2) (RouteDecision :toolName toolName :tier (tierRemoteLlm) :estimatedSavingsTokens 0 :estimatedLatencyMs 850))

fn routeAndExecute! call: c/ToolCall -> c/ToolResult
  (let [(name call.toolName)] (if (shouldExecuteLocally name) (c/executeBuiltinTool! call) (c/ToolResult :callId call.id :toolName name :success false :output "" :errorMsg "Tool requires remote LLM execution tier")))

fn formatSavingsReport routedCalls: I64 -> Str
  (let [(tokensSaved (* routedCalls 650))] (str "[LOCAL-EXEC] Local Execution: " (stringFromInt64 routedCalls) " tool call(s) executed locally. Saved ~" (stringFromInt64 tokensSaved) " tokens; ~95% latency reduction."))
