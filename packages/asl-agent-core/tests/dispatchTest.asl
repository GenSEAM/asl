(module aslAgentCore/dispatchTest :x [runTests] :i [(dispatch :a disp) (protocol :a proto)])

fn testCanonicalEnumeration -> Bool
  (do (assert (disp/isCanonicalTool "eddie-preload") "canonical tools include eddie-preload") (assert (disp/isCanonicalTool "ast-patch") "canonical tools include ast-patch") (assert (disp/isCanonicalTool "eddie-health") "canonical tools include eddie-health") (assert (disp/isCanonicalTool "deps-resolve") "canonical tools include deps-resolve") (assert (disp/isCanonicalTool "knowledge-load") "canonical tools include knowledge-load") (assert (disp/isCanonicalTool "knowledge-offload") "canonical tools include knowledge-offload") (assert (disp/isCanonicalTool "intent-record") "canonical tools include intent-record") (assert (disp/isCanonicalTool "intent-query") "canonical tools include intent-query") (assert (disp/isCanonicalTool "trace-verify") "canonical tools include trace-verify") (assert (disp/isCanonicalTool "exec-cmd") "canonical tools include exec-cmd") (assert (disp/isCanonicalTool "ptr-deref") "canonical tools include ptr-deref") (assert (not (disp/isCanonicalTool "not-a-tool")) "unknown tool is not canonical") true)

fn ! testUnknownStatus! -> Bool
  (let [(r (disp/dispatchCanonicalToolWithRegistry! (disp/ToolRegistry :tools (list) :handlers (list)) "not-a-tool" "src/main.asl" "" true))] (assert (= r.status "unknown") "unknown tools report unknown") true)

fn ! testTraversalDenied! -> Bool
  (let [(r (disp/dispatchCanonicalToolWithRegistry! (disp/ToolRegistry :tools (list) :handlers (list)) "ast-patch" "src/../../outside" "" true))] (assert (= r.status "denied") "traversal is denied") (assert (not r.success) "denied traversal is not successful") (assert (= r.output "") "denied traversal has no output") true)

fn ! testDotThenTraversalDenied! -> Bool
  (let [(r (disp/dispatchCanonicalToolWithRegistry! (disp/ToolRegistry :tools (list) :handlers (list)) "ast-patch" "./../outside" "" true))] (assert (= r.status "denied") "dot segment before parent traversal remains denied") true)

fn ! testTraversalDeniedWithoutExecution! -> Bool
  (let [(r (disp/dispatchCanonicalToolWithRegistry! (disp/ToolRegistry :tools (list) :handlers (list)) "ast-patch" "src/../../outside" "" false))] (assert (= r.status "denied") "traversal remains denied when execution is disabled") (assert (not r.success) "disabled traversal is not successful") true)

fn ! testAbsolutePathDenied! -> Bool
  (let [(r (disp/dispatchCanonicalToolWithRegistry! (disp/ToolRegistry :tools (list) :handlers (list)) "ast-patch" "/tmp/outside" "" true))] (assert (= r.status "denied") "absolute targets are denied") (assert (not r.success) "absolute target is not successful") true)

fn ! testCanonicalSuccess! -> Bool
  (let [(reg (disp/registerHandler (disp/ToolRegistry :tools (list) :handlers (list)) "eddie-preload" knownHandler)) (r (disp/dispatchCanonicalToolWithRegistry! reg "eddie-preload" "src/main.asl" "payload" true))] (assert (= r.status "ok") "known canonical tool succeeds") (assert r.success "known canonical tool reports success") (assert (= r.output "handler-result") "canonical dispatch returns injected handler output") true)

fn ! testCanonicalError! -> Bool
  (let [(r (disp/dispatchCanonicalToolWithRegistry! (disp/ToolRegistry :tools (list) :handlers (list)) "eddie-preload" "" "payload" true))] (assert (= r.status "error") "missing canonical target reports error") (assert (not r.success) "missing target is not successful") (assert (= r.output "") "missing target has no output") true)

fn ! testCanonicalMissingHandler! -> Bool
  (let [(r (disp/dispatchCanonicalToolWithRegistry! (disp/ToolRegistry :tools (list) :handlers (list)) "eddie-preload" "src/main.asl" "" true))] (assert (= r.status "error") "canonical tool without an injected handler reports error") (assert (stringContains? r.errorMsg "Missing handler: eddie-preload") "canonical missing-handler error identifies the tool") true)

fn failingHandler inv: proto/ToolInvocation -> proto/ToolResult
  (proto/ToolResult :toolName inv.toolName :success false :output "ignored" :errorMsg "handler rejected request")

fn ! testFailedHandlerIsError! -> Bool
  (let [(reg (disp/registerHandler (disp/ToolRegistry :tools (list) :handlers (list)) "eddie-preload" failingHandler)) (r (disp/dispatchCanonicalToolWithRegistry! reg "eddie-preload" "src/main.asl" "payload" true))] (assert (= r.status "error") "failed canonical handler reports error") (assert (not r.success) "failed canonical handler is not successful") (assert (stringContains? r.errorMsg "handler rejected request") "failed canonical handler preserves its error") true)

fn ! testExecutionDenied! -> Bool
  (let [(r (disp/dispatchCanonicalToolWithRegistry! (disp/ToolRegistry :tools (list) :handlers (list)) "exec-cmd" "echo forbidden" "" false))] (assert (= r.status "denied") "execution without authorization reports denied") (assert (not r.success) "unauthorized execution is not successful") true)

fn ! testPolicyCompatibility! -> Bool
  (let [(r (disp/dispatchCanonicalTool! (disp/ToolRegistry :tools (list) :handlers (list)) "exec-cmd" "echo forbidden" "" (disp/autonomyGuarded)))] (assert (= r.status "denied") "non-auto autonomy denies command execution") (assert (not r.success) "denied command is not successful") true)

fn ! testTypedCanonicalStatuses! -> Bool
  (let [(reg (disp/ToolRegistry :tools (list) :handlers (list)))
        (unknown (disp/dispatchCanonicalTool! reg "not-a-tool" "src/main.asl" "" (disp/autonomyAuto)))
        (deniedAsk (disp/dispatchCanonicalTool! reg "ast-patch" "src/../../outside" "" (disp/autonomyAsk)))
        (deniedGuarded (disp/dispatchCanonicalTool! reg "ast-patch" "src/../../outside" "" (disp/autonomyGuarded)))
        (deniedAuto (disp/dispatchCanonicalTool! reg "ast-patch" "src/../../outside" "" (disp/autonomyAuto)))
        (emptyTarget (disp/dispatchCanonicalTool! reg "ast-patch" "" "" (disp/autonomyAuto)))]
    (assert (= unknown.status "unknown") "typed canonical API preserves unknown status")
    (assert (not unknown.success) "typed unknown tool is not successful")
    (assert (= deniedAsk.status "denied") "typed traversal denied at Ask")
    (assert (= deniedGuarded.status "denied") "typed traversal denied at Guarded")
    (assert (= deniedAuto.status "denied") "typed traversal denied at Auto")
    (assert (= emptyTarget.status "error") "typed empty target reports error")
    (assert (not emptyTarget.success) "typed empty target is not successful")
    true)

fn knownHandler inv: proto/ToolInvocation -> proto/ToolResult
  (proto/ToolResult :toolName inv.toolName :success true :output "handler-result" :errorMsg "")

fn ! testInRootParentTraversal! -> Bool
  (let [(reg (disp/registerHandler (disp/ToolRegistry :tools (list) :handlers (list)) "eddie-preload" knownHandler)) (r (disp/dispatchCanonicalToolWithRegistry! reg "eddie-preload" "src/../main.asl" "payload" true))] (assert (= r.status "ok") "in-root parent traversal is allowed") (assert r.success "in-root parent traversal succeeds through its registered handler") (assert (= r.output "handler-result") "in-root parent traversal invokes the registered handler") true)

fn testToolExecution -> Bool
  (let [(tool (proto/ToolDef :name "known" :doc "known test tool" :params (list))) (empty (disp/ToolRegistry :tools (list) :handlers (list))) (registered (disp/registerTool empty tool)) (reg (disp/registerHandler registered "known" knownHandler)) (out (disp/dispatchCall reg "(call :tool known)"))] (assert (stringContains? out "(result :tool known :ok true") "registered tool handler reports success") (assert (stringContains? out "handler-result") "dispatch call invokes the registered handler") true)

fn testMissingHandler -> Bool
  (let [(tool (proto/ToolDef :name "known" :doc "known test tool" :params (list))) (reg (disp/registerTool (disp/ToolRegistry :tools (list) :handlers (list)) tool)) (out (disp/dispatchCall reg "(call :tool known)"))] (assert (stringContains? out "(result :tool known :ok false") "known tool without a handler reports failure") (assert (stringContains? out "Missing handler: known") "unregistered tool handler reports its name") true)

fn ! testTwoHandlerRouting! -> Bool
  (let [(base (disp/ToolRegistry :tools (list) :handlers (list))) (reg (disp/registerHandler (disp/registerHandler base "eddie-preload" knownHandler) "ast-patch" failingHandler)) (a (disp/dispatchCanonicalToolWithRegistry! reg "eddie-preload" "src/main.asl" "payload" true)) (b (disp/dispatchCanonicalToolWithRegistry! reg "ast-patch" "src/main.asl" "payload" true))] (assert (= a.status "ok") "tail handler is selected by name") (assert (= a.output "handler-result") "named handler output is returned, not the head handler") (assert (= b.status "error") "head handler is selected by name") (assert (stringContains? b.errorMsg "handler rejected request") "head handler error is returned, not the tail handler") true)

fn ! runTests -> Bool
  (and (testCanonicalEnumeration) (and (testUnknownStatus!) (and (testTraversalDenied!) (and (testDotThenTraversalDenied!) (and (testTraversalDeniedWithoutExecution!) (and (testAbsolutePathDenied!) (and (testCanonicalSuccess!) (and (testCanonicalError!) (and (testCanonicalMissingHandler!) (and (testFailedHandlerIsError!) (and (testExecutionDenied!) (and (testPolicyCompatibility!) (and (testTypedCanonicalStatuses!) (and (testInRootParentTraversal!) (and (testToolExecution) (and (testMissingHandler) (testTwoHandlerRouting!)))))))))))))))))
