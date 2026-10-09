(module aslAgent/dispatch :x [canonicalToolRegistry! dispatchCanonicalTool!] :i [(aslAgentCore/dispatch :a core) (aslAgentCore/protocol :a proto) (aslAgentCore/fastKnowledgeCache :a kc) (policy :a pol) (horizon :a hor) (copilot :a cop) (supervisor :a sup)])

fn arg inv: proto/ToolInvocation name: Str -> Str
  (mt (proto/getArgValue inv.args name) ((none) "") ((some value) value))

fn result inv: proto/ToolInvocation success: Bool output: Str errorMsg: Str -> proto/ToolResult
  (proto/ToolResult :toolName inv.toolName :success success :output output :errorMsg errorMsg)

fn ! routePreload! inv: proto/ToolInvocation -> proto/ToolResult
  (let [(target (arg inv "targetFile")) (expanded (hor/expandHorizon (hor/makeHorizonRequest target 0 500)))] (result inv true expanded.astBody ""))

fn ! routeHealth! inv: proto/ToolInvocation -> proto/ToolResult
  (let [(target (arg inv "targetFile")) (matrix (hor/computeHealthMatrix (list target) false))] (result inv true (hor/formatHealthSummary matrix) ""))

fn ! routePatch! inv: proto/ToolInvocation -> proto/ToolResult
  (result inv true (cop/stageProposal (cop/makeProposal "dispatch" (arg inv "targetFile") (arg inv "payload"))) "")

fn ! routeKnowledgeLoad! inv: proto/ToolInvocation -> proto/ToolResult
  (let [(snapshot (kc/knowledgeIndexSymbol (kc/knowledgeCacheCreate) (arg inv "targetFile") "" (arg inv "targetFile") (arg inv "payload") "symbol"))] (result inv true (kc/formatKnowledgeSnapshot snapshot) ""))

fn ! routeKnowledgeOffload! inv: proto/ToolInvocation -> proto/ToolResult
  (let [(note (str (arg inv "targetFile") ":" (arg inv "payload")))
        (snapshot (kc/knowledgeAddNote (kc/knowledgeCacheCreate) note))]
    (result inv true (kc/formatKnowledgeSnapshot snapshot) ""))

fn ! routeIntentRecord! inv: proto/ToolInvocation -> proto/ToolResult
  (result inv true (cop/intentRecord "intent" (arg inv "targetFile") (arg inv "payload") (arg inv "targetFile")) "")

fn ! routeIntentQuery! inv: proto/ToolInvocation -> proto/ToolResult
  (result inv true (cop/intentQuery (arg inv "targetFile") (arg inv "payload")) "")

fn ! routePointer! inv: proto/ToolInvocation -> proto/ToolResult
  (result inv true (cop/dereferencePointer! (cop/makePointer (arg inv "targetFile") (cop/ptrAst) "canonical pointer" "") (arg inv "payload")) "")

fn ! routeTrace! inv: proto/ToolInvocation -> proto/ToolResult
  (let [(target (arg inv "targetFile")) (verified (cop/traceVerify! target))]
    (if verified
      (result inv true (str "verified: " target) "")
      (result inv false "" (str "not verified: " target))))

fn ! routeExec! inv: proto/ToolInvocation -> proto/ToolResult
  (let [(receipt (sup/executeSupervised! (arg inv "targetFile") 0 (sup/makeSupervisorConfig 10000 900000 true)))]
    (if (= receipt.exitCode 0)
      (result inv true (str "exit 0: " receipt.lastOutput) "")
      (result inv false "" (str "exec-cmd failed: " receipt.lastOutput))))

fn ! canonicalToolRegistry! -> core/ToolRegistry
  (let [(empty (core/ToolRegistry :tools (list) :handlers (list)))
        (r1 (core/registerHandler empty "eddie-preload" routePreload!))
        (r2 (core/registerHandler r1 "eddie-health" routeHealth!))
        (r3 (core/registerHandler r2 "ast-patch" routePatch!))
        (r4 (core/registerHandler r3 "knowledge-load" routeKnowledgeLoad!))
        (r5 (core/registerHandler r4 "knowledge-offload" routeKnowledgeOffload!))
        (r6 (core/registerHandler r5 "intent-record" routeIntentRecord!))
        (r7 (core/registerHandler r6 "intent-query" routeIntentQuery!))
        (r8 (core/registerHandler r7 "ptr-deref" routePointer!))
        (r9 (core/registerHandler r8 "trace-verify" routeTrace!))]
    (core/registerHandler r9 "exec-cmd" routeExec!))

fn ! dispatchCanonicalTool! toolName: Str targetFile: Str payload: Str policyLevel: pol/AutonomyLevel -> core/DispatchResult
  (let [(autonomy (mt policyLevel ((pol/levelAsk) (core/autonomyAsk)) ((pol/levelGuarded) (core/autonomyGuarded)) ((pol/levelAuto) (core/autonomyAuto))))]
    (core/dispatchCanonicalTool! (canonicalToolRegistry!) toolName targetFile payload autonomy))
