(module aslAgent/dispatchTest
  :x [testDispatchPreloadAndHealth!
      testDispatchKnowledgeAndIntent!
      testDispatchExecAndDeref!
      testDispatchPathPolicy!
      runTests]
  :i [(aslAgent/dispatch :a disp) (policy :a pol)])

fn ! testDispatchPreloadAndHealth! -> Bool
  (let [(rPre (disp/dispatchCanonicalTool! "eddie-preload" "src/app.asl" "" (pol/levelAuto)))
        (rHlth (disp/dispatchCanonicalTool! "eddie-health" "src/app.asl" "" (pol/levelAuto)))]
    (assert rPre.success "preload success")
    (assert (stringContains? rPre.output "fn src/app.asl") "preload routes to horizon expansion")
    (assert rHlth.success "health success")
    (assert (stringContains? rHlth.output "Health: HEALTHY") "health routes to health matrix")
    true)

fn ! testDispatchKnowledgeAndIntent! -> Bool
  (let [(rKn (disp/dispatchCanonicalTool! "knowledge-load" "zod@3" "export class Zod" (pol/levelAuto)))
        (rOff (disp/dispatchCanonicalTool! "knowledge-offload" "task-7" "summary" (pol/levelAuto)))
        (rInt (disp/dispatchCanonicalTool! "intent-record" "dec:001" "ASL Native" (pol/levelAuto)))
        (rQuery (disp/dispatchCanonicalTool! "intent-query" "dec:001" "depends" (pol/levelAuto)))
        (rPatch (disp/dispatchCanonicalTool! "ast-patch" "src/app.asl" "proposal" (pol/levelAuto)))
        (rTrace (disp/dispatchCanonicalTool! "trace-verify" "never-present-dispatch-fixture" "" (pol/levelAuto)))
        (rDeps (disp/dispatchCanonicalTool! "deps-resolve" "src/app.asl" "" (pol/levelAuto)))]
    (assert rKn.success "knowledge success")
    (assert (stringContains? rKn.output ":symbols-count 1") "knowledge routes to snapshot index")
    (assert rOff.success "knowledge offload success")
    (assert (stringContains? rOff.output ":notes-count 1") "knowledge offload routes to note snapshot")
    (assert rInt.success "intent success")
    (assert (stringContains? rInt.output "dec:001") "intent routes to intent record")
    (assert rQuery.success "intent query success")
    (assert (stringContains? rQuery.output "dec:001") "intent query routes to copilot query")
    (assert rPatch.success "AST patch proposal success")
    (assert (stringContains? rPatch.output "src/app.asl") "AST patch routes through proposal staging")
    (assert (not rTrace.success) "failed trace verification is unsuccessful")
    (assert (= rTrace.status "error") "failed trace verification reports error status")
    (assert (stringContains? rTrace.errorMsg "not verified:") "trace verification reports failed target")
    (assert (not rDeps.success) "unimplemented dependency route fails")
    (assert (stringContains? rDeps.errorMsg "Missing handler: deps-resolve") "unimplemented dependency route names missing handler")
    true)

fn ! testDispatchExecAndDeref! -> Bool
  (let [(rExec (disp/dispatchCanonicalTool! "exec-cmd" "echo ok" "" (pol/levelAuto)))
        (rPtr (disp/dispatchCanonicalTool! "ptr-deref" "b3-dom-01" "is_visible" (pol/levelAuto)))]
    (assert rExec.success "exec routes through supervisor")
    (assert (stringContains? rExec.output "exit 0") "supervisor returns command exit status")
    (assert rPtr.success "pointer routes through copilot dereference")
    (assert (stringContains? rPtr.output "b3-dom-01") "dereference result identifies pointer")
    true)

fn ! testDispatchPathPolicy! -> Bool
  (let [(rAbsAsk (disp/dispatchCanonicalTool! "eddie-preload" "/outside.asl" "" (pol/levelAsk)))
        (rAbsGuarded (disp/dispatchCanonicalTool! "eddie-preload" "/outside.asl" "" (pol/levelGuarded)))
        (rAbsAuto (disp/dispatchCanonicalTool! "eddie-preload" "/outside.asl" "" (pol/levelAuto)))
        (rEscAsk (disp/dispatchCanonicalTool! "eddie-preload" "src/../../outside.asl" "" (pol/levelAsk)))
        (rEscGuarded (disp/dispatchCanonicalTool! "eddie-preload" "src/../../outside.asl" "" (pol/levelGuarded)))
        (rEscAuto (disp/dispatchCanonicalTool! "eddie-preload" "src/../../outside.asl" "" (pol/levelAuto)))
        (rExecAsk (disp/dispatchCanonicalTool! "exec-cmd" "echo forbidden" "" (pol/levelAsk)))
        (rExecGuarded (disp/dispatchCanonicalTool! "exec-cmd" "echo forbidden" "" (pol/levelGuarded)))
        (rInRoot (disp/dispatchCanonicalTool! "eddie-preload" "src/../main.asl" "" (pol/levelAuto)))]
    (assert (not rAbsAsk.success) "absolute path denied at Ask")
    (assert (not rAbsGuarded.success) "absolute path denied at Guarded")
    (assert (not rAbsAuto.success) "absolute path denied at Auto")
    (assert (= rAbsAsk.status "denied") "absolute path reports denied at Ask")
    (assert (= rAbsGuarded.status "denied") "absolute path reports denied at Guarded")
    (assert (= rAbsAuto.status "denied") "absolute path reports denied at Auto")
    (assert (not rEscAsk.success) "traversal denied at Ask")
    (assert (not rEscGuarded.success) "traversal denied at Guarded")
    (assert (not rEscAuto.success) "traversal denied at Auto")
    (assert (= rEscAsk.status "denied") "traversal reports denied at Ask")
    (assert (= rEscGuarded.status "denied") "traversal reports denied at Guarded")
    (assert (= rEscAuto.status "denied") "traversal reports denied at Auto")
    (assert (= rExecAsk.status "denied") "shell execution denied at Ask")
    (assert (= rExecGuarded.status "denied") "shell execution denied at Guarded")
    (assert rInRoot.success "in-root parent traversal allowed")
    true)

fn ! runTests -> Bool
  (do
    (assert (testDispatchPreloadAndHealth!) "testDispatchPreloadAndHealth must pass")
    (assert (testDispatchKnowledgeAndIntent!) "testDispatchKnowledgeAndIntent must pass")
    (assert (testDispatchExecAndDeref!) "testDispatchExecAndDeref must pass")
    (assert (testDispatchPathPolicy!) "testDispatchPathPolicy must pass")
    true)
