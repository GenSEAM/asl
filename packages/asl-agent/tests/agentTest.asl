(module aslAgent/agentTest :x [testAgentAutonomyLevels! testAgentTuiFoldingHistory! testEddieRunClarification! testEddieRunDirect! testEmptyGoalEdge testPolicySandbox testTriageCollapse testAgentReactStep! runTests] :i [(policy :a pol) (agent :a ag) (eddie :a eddie) (triage :a tr)])

fn testAgentAutonomyLevels! -> Bool
  (let [(m (pol/makeManifest "/workspace" (list) "/tmp" false)) (s0 (ag/makeAutonomySession "inspect" m (pol/levelAsk))) (r0 (ag/stepAgent! s0 "write" "/workspace/src/test.asl" "dummy")) (s1 (ag/makeAutonomySession "inspect" m (pol/levelGuarded))) (r1Read (ag/stepAgent! s1 "read" "/workspace/src/test.asl" "")) (r1Write (ag/stepAgent! r1Read.session "write" "/workspace/src/test.asl" "dummy")) (s2 (ag/makeAutonomySession "inspect" m (pol/levelAuto))) (r2Write (ag/stepAgent! s2 "write" "/workspace/src/test.asl" "dummy"))] (do (assert (stringStartsWith? r0.actionTaken "prompt:write") "c-agent-neg-001: L0 prompts for write") (assert (stringStartsWith? r1Read.actionTaken "executed:read") "c-agent-pos-002: L1 reads ok") (assert (stringStartsWith? r2Write.actionTaken "executed:write") "c-agent-pos-002: L2 auto write") (assert (not (stringStartsWith? r0.actionTaken "executed:write")) "c-agent-neg-001: L0 never auto writes") true))

fn testAgentTuiFoldingHistory! -> Bool
  (let [(m (pol/makeManifest "/workspace" (list) "/tmp" false)) (s (ag/makeAutonomySession "read main" m (pol/levelAuto))) (res (ag/stepAgent! s "read" "/workspace/src/main.asl" "")) (hist res.session.history)] (let [(hasFolded (not (listEmpty? (filter (fn [(x Str)] -> Bool (stringContains? x "[>] [read]")) hist))))] (do (assert hasFolded "c-agent-edge-002: folding history present") (assert (not (listEmpty? hist)) "c-agent-edge-002: history not empty") true)))

fn testEddieRunClarification! -> Bool
  (let [(out (eddie/eddieRun! "help" "/workspace" (pol/levelGuarded)))] (do (assert (stringContains? out "Need clarification") "c-agent-pos-001: clarification requested") (assert (stringContains? out "[1]") "c-agent-pos-001: option 1 rendered") (assert (not (stringContains? out "Fatal error")) "c-agent-neg-002: no fatal crash") true))

fn testEddieRunDirect! -> Bool
  (let [(out (eddie/eddieRun! "Audit dependencies in /workspace/src/main.asl" "/workspace" (pol/levelAuto)))] (do (assert (stringContains? out "Goal:") "c-agent-pos-001: goal displayed") (assert (stringContains? out "Session complete") "c-agent-pos-001: session completed") (assert (not (stringContains? out "panic")) "c-agent-neg-002: no panic") true))

fn testAddieRunDirect! -> Bool
  (let [(out (eddie/addieRun! "Audit dependencies in /workspace/src/main.asl" "/workspace" (pol/levelAuto)))] (do (assert (stringContains? out "Goal:") "c-agent-pos-001: goal displayed") (assert (stringContains? out "Session complete") "c-agent-pos-001: session completed") (assert (not (stringContains? out "unhandled exception")) "c-agent-neg-002: no exception") true))

fn testAddieVersion -> Bool
  (do (assert (= (eddie/addieVersion) "0.1.0") "c-agent-pos-003: addie version is 0.1.0") (assert (= (eddie/eddieVersion) "0.1.0") "c-agent-pos-003: eddie version is 0.1.0") (assert (not (= (eddie/addieVersion) "0.0.0")) "c-agent-neg-001: version not 0.0.0") true)

fn testEmptyGoalEdge -> Bool
  (let [(manifest (pol/makeManifest "/tmp" (list) "/tmp" false)) (sess (ag/makeAutonomySession "" manifest (pol/levelAuto)))] (assert (= sess.state.goal "") "c-agent-edge-001: handles empty goal") (assert (not sess.state.isTerminal) "c-agent-edge-001: not terminal") true)

fn testPolicySandbox -> Bool
  (let [(m (pol/makeManifest "/workspace" (list "/workspace/tree") "/tmp" false)) (p1 (pol/checkPermission "read" "/workspace/src/app.asl" m)) (p2 (pol/checkPermission "write" "/etc/passwd" m)) (p3 (pol/checkPermission "write" "/workspace/../escape" m))] (assert p1.allowed "read allowed") (assert (not p2.allowed) "passwd write blocked") (assert (not p3.allowed) "escape write blocked") true)

fn testTriageCollapse -> Bool
  (let [(ctx (tr/makeWorkspaceContext "asl" "/workspace" true (list "asl"))) (d1 (tr/triageRequest "fix and test and refactor core" ctx))] (assert (= d1.shape "single") "shape is single") (assert (= d1.kind "dev") "kind is dev") true)

fn testAgentReactStep! -> Bool
  (let [(m (pol/makeManifest "asl/packages/asl-agent" (list) "/tmp" false)) (sess (ag/makeAgentSession "inspect repo" m)) (res (ag/stepAgent! sess "read" "asl/packages/asl-agent/src/ffi.asl" "dummy payload"))] (let [(un (println (str "RES: " res.success " " res.actionTaken " " res.observation)))] (assert res.success "step-agent success") (assert (stringContains? res.observation "module aslAgent/ffi") "step-agent observation contains the file contents") true))

fn failHostCall! capability: Str action: Str target: Str -> (Result Str Str)
  (err "host operation failed")

fn testAgentHostFailure! -> Bool
  (let [(m (pol/makeManifest "asl/packages/asl-agent" (list) "/tmp" false)) (sess (ag/makeAgentSession "inspect repo" m)) (res (ag/stepAgentWithHostCall! sess "read" "asl/packages/asl-agent/src/ffi.asl" "" failHostCall!))] (do (assert (not res.success) "host failure reports unsuccessful step") (assert (stringContains? res.observation "host operation failed") "host failure is surfaced as observation") true))

fn testRunBoundedSession! -> Bool
  (let [(m (pol/makeManifest "/workspace" (list) "/tmp" false)) (sess (ag/makeAgentSession "inspect repo" m)) (res (ag/runBoundedSession! sess))] (assert res.state.isTerminal "run-bounded-session completes and sets terminal state") true)

fn ! runTests -> Bool
  (do (assert (testAgentAutonomyLevels!) "autonomy levels pass") (assert (testAgentTuiFoldingHistory!) "tui folding history pass") (assert (testEddieRunClarification!) "clarification pass") (assert (testEddieRunDirect!) "eddie direct pass") (assert (testAddieRunDirect!) "addie direct pass") (assert (testAddieVersion) "version pass") (assert (testEmptyGoalEdge) "empty goal edge pass") (assert (testPolicySandbox) "policy sandbox pass") (assert (testTriageCollapse) "triage collapse pass") (assert (testAgentReactStep!) "agent react step pass") (assert (testAgentHostFailure!) "agent host failure pass") (assert (testRunBoundedSession!) "agent bounded session pass") true)
