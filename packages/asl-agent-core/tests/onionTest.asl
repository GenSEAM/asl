(module aslAgentCore/test :x [runTests] :i [(core :a core) (onion :a on)])

fn extractIds items: (List on/Middleware) -> (List Str)
  (map (fn [(m on/Middleware)] -> Str m.id) items)

fn testPrioritySorting -> Bool
  (let [(mAudit (on/makeMiddleware "mw-audit" "Audit" (on/kindAudit) 500 (list) (list))) (mAuth (on/makeMiddleware "mw-auth" "Auth" (on/kindPreCall) 100 (list) (list))) (mSanitize (on/makeMiddleware "mw-sanitize" "Sanitize" (on/kindPostCall) 900 (list) (list))) (ids (extractIds (on/sortMiddlewares (list mAudit mAuth mSanitize))))] (assert (= (listLength ids) 3) "Must sort all 3 middlewares") (assert (= (optionOr (listGet ids 0) "") "mw-auth") "Lowest priority 100 must be first") (assert (= (optionOr (listGet ids 1) "") "mw-audit") "Medium priority 500 must be second") (assert (= (optionOr (listGet ids 2) "") "mw-sanitize") "Highest priority 900 must be third") true)

fn testDependencyOverride -> Bool
  (let [(mLogger (on/makeMiddleware "mw-logger" "Logger" (on/kindPreCall) 800 (list "mw-auth") (list))) (mAuth (on/makeMiddleware "mw-auth" "Auth" (on/kindPreCall) 100 (list) (list))) (mSanitize (on/makeMiddleware "mw-sanitize" "Sanitize" (on/kindPostCall) 900 (list) (list))) (ids (extractIds (on/sortMiddlewares (list mAuth mLogger mSanitize))))] (assert (= (listLength ids) 3) "Must sort all 3 middlewares") (assert (= (optionOr (listGet ids 0) "") "mw-logger") "mw-logger must precede mw-auth") (assert (= (optionOr (listGet ids 1) "") "mw-auth") "mw-auth must follow mw-logger") (assert (= (optionOr (listGet ids 2) "") "mw-sanitize") "mw-sanitize must be last") true)

fn testAfterDependency -> Bool
  (let [(mGate (on/makeMiddleware "mw-gate" "Gate" (on/kindFilter) 900 (list) (list))) (mCheck (on/makeMiddleware "mw-check" "Check" (on/kindPreCall) 100 (list) (list "mw-gate"))) (ids (extractIds (on/sortMiddlewares (list mCheck mGate))))] (assert (= (listLength ids) 2) "Must sort both middlewares") (assert (= (optionOr (listGet ids 0) "") "mw-gate") "mw-gate must precede mw-check") (assert (= (optionOr (listGet ids 1) "") "mw-check") "mw-check must follow mw-gate") true)

fn testFilterInterceptor -> Bool
  (let [(mw (on/makeMiddleware "mw-guard" "Guard" (on/kindFilter) 200 (list) (list))) (ctxSafe (on/makeOnionContext "C1" "agent-0" "search" "valid query")) (ctxBlock (on/makeOnionContext "C2" "agent-0" "delete" "blocked: destructive action"))] (let [(decSafe (on/executeMiddleware mw ctxSafe)) (decBlock (on/executeMiddleware mw ctxBlock))] (assert decSafe.proceed "Safe context must proceed") (assert (not decSafe.blocked) "Safe context must not be blocked") (assert (not decBlock.proceed) "Block context must not proceed") (assert decBlock.blocked "Block context must be blocked") (assert (stringContains? decBlock.reason "Blocked by filter") "Block reason must be set") true))

fn testMutationInterceptor -> Bool
  (let [(mw (on/makeMiddleware "mw-transform" "Transformer" (on/kindMutate) 300 (list) (list))) (ctx (on/makeOnionContext "C3" "agent-1" "transform" "data-raw")) (dec (on/executeMiddleware mw ctx))] (assert dec.proceed "Mutate middleware must proceed") (assert (= dec.context.payload "data-raw:mw-transform") "Payload must be transformed") true)

fn testAuditInterceptor -> Bool
  (let [(mw (on/makeMiddleware "mw-telemetry" "Telemetry" (on/kindAudit) 500 (list) (list))) (ctx (on/makeOnionContext "C4" "agent-2" "tool-test" "payload")) (dec (on/executeMiddleware mw ctx))] (assert dec.proceed "Audit middleware must proceed") (assert (not (listEmpty? dec.context.auditLog)) "Audit log must not be empty") true)

fn testFullOnionDispatch -> Bool
  (let [(mAuth (on/makeMiddleware "mw-auth" "Auth" (on/kindPreCall) 100 (list) (list))) (mFilter (on/makeMiddleware "mw-filter" "Filter" (on/kindFilter) 200 (list) (list))) (mMutate (on/makeMiddleware "mw-mutate" "Mutate" (on/kindMutate) 300 (list) (list))) (mAudit (on/makeMiddleware "mw-audit" "Audit" (on/kindAudit) 500 (list) (list))) (mPost (on/makeMiddleware "mw-post" "Post" (on/kindPostCall) 900 (list) (list))) (p0 (on/makePipeline)) (p1 (on/addMiddleware p0 mPost)) (p2 (on/addMiddleware p1 mAudit)) (p3 (on/addMiddleware p2 mMutate)) (p4 (on/addMiddleware p3 mFilter)) (p5 (on/addMiddleware p4 mAuth)) (ctx (on/makeOnionContext "C5" "agent-root" "exec" "command-line"))] (let [(dec (on/dispatchToolCall p5 ctx "execution-success-42"))] (assert dec.proceed "Pipeline dispatch must proceed") (assert (not dec.blocked) "Pipeline must not be blocked") (assert (= dec.context.payload "execution-success-42") "Payload must match execution output") (assert (= (listLength dec.context.auditLog) 6) "Audit log must contain 6 entries") true))

fn testCoreAgent -> Bool
  (let [(ctx0 (core/makeAgentContext "agent-alpha" "sess-99" "You are a helpful agent.")) (msg (core/makeMessage "user" "Hello AgentScript" "user-1")) (ctx1 (core/addMessage ctx0 msg)) (tool (core/makeToolDef "search" "Search engine" "(:q Str)")) (reg (core/registerTool (core/emptyRegistry "agent-alpha") tool))] (assert (= ctx1.agentId "agent-alpha") "Agent ID must match") (assert (= (listLength ctx1.messages) 1) "Messages list length must be 1") (assert (core/hasTool? reg "search") "Registry must have search tool") (assert (not (core/hasTool? reg "non-existent")) "Registry must not have non-existent tool") true)

fn testStepHook -> Bool
  (let [(mAbort (on/makeMiddleware "mw-abort" "Abort" (on/kindFilter) 900 (list) (list))) (mRetry (on/makeMiddleware "mw-retry" "Retry" (on/kindPostCall) 500 (list) (list))) (ctxAbort (on/makeStepContext "S1" "agent-0" 1 "abort" "abort")) (ctxRetry (on/makeStepContext "S2" "agent-0" 1 "retry" "retry")) (p0 (on/makePipeline)) (decAbort (on/dispatchStepHook (on/addMiddleware p0 mAbort) (on/kindFilter) ctxAbort)) (decRetry (on/dispatchStepHook (on/addMiddleware p0 mRetry) (on/kindPostCall) ctxRetry))] (assert (= decAbort.action "abort") "Filter middleware must result in abort") (assert (= decRetry.action "retry") "Post-call middleware must result in retry") true)

fn runTests -> Bool
  (and (testPrioritySorting) (and (testDependencyOverride) (and (testAfterDependency) (and (testFilterInterceptor) (and (testMutationInterceptor) (and (testAuditInterceptor) (and (testFullOnionDispatch) (and (testStepHook) (testCoreAgent)))))))))
