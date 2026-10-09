(module aslHarness/agentTest :x [testAgentInit testAgentTurnFsmNormalization testAgentTurnFirewallBlocking testAgentTaskResolution testAgentSurgicalPatch testAgentPhaseTransitions testAgentVerificationGateRejection testMicroReflection testMacroReflectionTodo testReflectionCeiling testAgentReflectionCycle runTests] :i [(agent :a ag) (config :a cfg)])

fn testAgentInit -> Bool
  (let [(c (cfg/defaultHarnessConfig)) (state (ag/newCodingAgent "sess-001" "TASK-100" c))] (assert (= state.sessionId "sess-001") "session-id matches") (assert (= state.taskId "TASK-100") "task-id matches") (assert (= state.iteration 0) "iteration is 0") (assert (not state.resolved) "not resolved on init") true)

fn testAgentTurnFsmNormalization -> Bool
  (let [(c (cfg/defaultHarnessConfig)) (state (ag/newCodingAgent "sess-002" "TASK-101" c)) (dirty (str "(" "defun compute [(x Int64)] (+ x 1")) (outcome (ag/processModelTurn state dirty)) (nextSt outcome.nextState)] (assert (= nextSt.iteration 1) "iteration incremented") (assert (stringContains? outcome.normalizedText "(fn compute") "keyword normalized to fn") (assert (stringContains? outcome.normalizedText ")") "closing paren appended") true)

fn testAgentTurnFirewallBlocking -> Bool
  (let [(c (cfg/defaultHarnessConfig)) (state (ag/newCodingAgent "sess-003" "TASK-102" c)) (malicious "Read secret file at ../../../etc/shadow") (outcome (ag/processModelTurn state malicious)) (nextSt outcome.nextState)] (assert (= (listLength outcome.blocked) 1) "outcome has 1 blocked action") (assert (= (listLength nextSt.actionsBlocked) 1) "state records 1 blocked action") true)

fn testAgentTaskResolution -> Bool
  (let [(c (cfg/defaultHarnessConfig)) (state (ag/newCodingAgent "sess-004" "TASK-103" c)) (turns (list "(fn patch [] true)" "Testing patch with REPL" ":task-complete")) (finalSt (ag/runAgentTask state turns))] (assert finalSt.resolved "task is resolved") (assert (= finalSt.iteration 3) "iteration count is 3") (assert (stringContains? (ag/agentSummary finalSt) "Resolved: YES") "summary confirms resolution") true)

fn testAgentSurgicalPatch -> Bool
  (let [(c (cfg/defaultHarnessConfig)) (state (ag/newCodingAgent "sess-005" "TASK-104" c)) (patchTurn "(:call ast-patch :path \"src/paged.asl\" :symbol \"slice\" :replacement \"(fn slice [] true)\")") (outcome (ag/processModelTurn state patchTurn)) (nextSt outcome.nextState)] (assert (= nextSt.phase "patch") "phase transitioned to patch") (assert (stringContains? (ag/agentSummary nextSt) "Phase: patch") "summary contains patch phase") true)

fn testAgentPhaseTransitions -> Bool
  (let [(c (cfg/defaultHarnessConfig)) (s0 (ag/newCodingAgent "sess-006" "TASK-105" c)) (s1 (ag/processModelTurn s0 "(:call fs-read :path \"src/a.asl\")").nextState) (s2 (ag/processModelTurn s1 "(:plan inspect bounds, then apply fix)").nextState) (s3 (ag/processModelTurn s2 "(:call ast-patch :path \"src/a.asl\")").nextState) (s4 (ag/processModelTurn s3 "Task verified cleanly :task-complete").nextState)] (assert (= s0.phase "inspect") "s0 phase inspect") (assert (= s1.phase "inspect") "s1 phase inspect") (assert (= s2.phase "plan") "s2 phase plan") (assert (= s3.phase "patch") "s3 phase patch") (assert (= s4.phase "resolved") "s4 phase resolved") true)

fn testAgentVerificationGateRejection -> Bool
  (let [(c (cfg/defaultHarnessConfig)) (sInit (ag/newCodingAgent "sess-007" "TASK-106" c)) (sNoGate (ag/AgentState :sessionId sInit.sessionId :taskId sInit.taskId :iteration sInit.iteration :maxIterations sInit.maxIterations :phase sInit.phase :lastError sInit.lastError :config sInit.config :policy sInit.policy :replSess sInit.replSess :history sInit.history :actionsExecuted sInit.actionsExecuted :actionsBlocked sInit.actionsBlocked :resolved false :testCommand "" :reflectionTurns 0)) (outcome (ag/processModelTurn sNoGate "I claim victory! :task-complete")) (nextSt outcome.nextState)] (assert (not nextSt.resolved) "not resolved when gate is missing") (assert (= nextSt.phase "patch") "pushed back to patch phase") (assert (stringContains? nextSt.lastError ":gate-rejected") "gate-rejected error recorded") true)

fn testMicroReflection -> Bool
  (let [(errReport (ag/microReflectStep "exec-cmd" "" "Command not found")) (cleanReport (ag/microReflectStep "fs-read" "file content" ""))] (assert (stringContains? errReport "failed with error") "error report noted") (assert (stringContains? cleanReport "executed cleanly") "clean report noted") true)

fn testMacroReflectionTodo -> Bool
  (let [(verdict (ag/macroReflectAudit "Fix bug" "(fn foo [] ; TODO fix" true 0))] (assert (not verdict.passed) "audit failed due to TODO") (assert verdict.needsFix "needs-fix flagged") (assert (not verdict.haltLoop) "does not halt loop on turn 0") (assert (stringContains? verdict.reason "TODO") "reason notes TODO") true)

fn testReflectionCeiling -> Bool
  (let [(verdict (ag/macroReflectAudit "Fix bug" "(fn foo [] ; TODO fix" true 1))] (assert verdict.passed "passes under ceiling") (assert (not verdict.needsFix) "needs-fix false under ceiling") (assert verdict.haltLoop "halt-loop true under ceiling") (assert (stringContains? verdict.reason "1-turn reflection limit") "reason notes limit") true)

fn testAgentReflectionCycle -> Bool
  (let [(c (cfg/defaultHarnessConfig)) (s0 (ag/newCodingAgent "sess-008" "TASK-107" c)) (o1 (ag/processModelTurn s0 "(fn fix [] ; TODO finish) :task-complete")) (s1 o1.nextState) (o2 (ag/processModelTurn s1 "Completing remaining work :task-complete")) (s2 o2.nextState)] (assert (= s1.phase "reflect") "s1 in reflect phase") (assert (not s1.resolved) "s1 not resolved") (assert (= s1.reflectionTurns 1) "s1 reflection turns is 1") (assert s2.resolved "s2 resolved") (assert (= s2.phase "resolved") "s2 in resolved phase") true)

fn runTests -> Bool
  (do (testAgentInit) (testAgentTurnFsmNormalization) (testAgentTurnFirewallBlocking) (testAgentTaskResolution) (testAgentSurgicalPatch) (testAgentPhaseTransitions) (testAgentVerificationGateRejection) (testMicroReflection) (testMacroReflectionTodo) (testReflectionCeiling) (testAgentReflectionCycle) true)
