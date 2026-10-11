(module aslAgent/masterE2eTest :x [testE2eFeedbackAndVmmHydration testE2eOnionPipelineAndHorizon testE2eCanonicalDispatchAndSupervisor! testE2eSnapshotAndCliInference runTests] :i [(policy :a pol) (tui :a tui) (feedback :a fb) (aslAgentCore/onion :a on) (snapshot :a snap) (vmm :a vmm) (horizon :a hor) (supervisor :a sup) (copilot :a cop) (aslAgent/dispatch :a disp) (cli :a cli)])

fn testE2eFeedbackAndVmmHydration -> Bool
  (let [(rawPrompt "Please refactor src/db.asl to use transactions.") (refined (fb/refineUserPrompt rawPrompt (list "src/db.asl"))) (st0 (vmm/makeVmmState "Constitution: No foreign code" 4096)) (st1 (vmm/vmmLoadKnowledge st0 "sqlite3" "export function open()")) (st2 (vmm/vmmOffloadKnowledge st1 "sqlite3" "src/db.asl:10"))] (assert (not refined.isAmbiguous) "refined prompt is not ambiguous") (assert (= (mt (listGet st2.slots 2) ((some s) s)).tokens 0) "slot 2 tokens cleared") (assert (> (stringLength (mt (listGet st2.slots 1) ((some s) s)).payload) 0) "slot 1 receipt payload non-empty") true)

fn testE2eOnionPipelineAndHorizon -> Bool
  (let [(ctx (on/makeContext "read-file" "src/db.asl" "code content" 50 2000 (pol/levelAuto))) (pipe (on/makeLegacyPipeline ctx)) (res (on/executePipeline pipe)) (req (hor/makeHorizonRequest "db/open" 1 500)) (hRes (hor/expandHorizon req)) (matrix (hor/computeHealthMatrix (list "db") false))] (assert (= res.status "PROCEED") "status is PROCEED") (assert (<= hRes.tokensUsed 500) "tokens used within 500") (assert matrix.isHealthy "matrix is healthy") true)

fn testE2eCanonicalDispatchAndSupervisor! -> Bool
  (let [(r1 (disp/dispatchCanonicalTool! "eddie-preload" "src/db.asl" "" (pol/levelAuto))) (r2 (disp/dispatchCanonicalTool! "eddie-health" "src/db.asl" "" (pol/levelAuto))) (r3 (disp/dispatchCanonicalTool! "exec-cmd" "echo ok" "" (pol/levelAuto))) (r4 (disp/dispatchCanonicalTool! "ptr-deref" "b3-dom-01" "is_ready" (pol/levelAuto))) (cfg (sup/makeSupervisorConfig 10000 900000 true)) (supRes (sup/executeSupervised! "asl test db-test.asl" 1000 cfg))] (assert r1.success "dispatch preload success") (assert r2.success "dispatch health success") (assert r3.success "dispatch exec-cmd success") (assert r4.success "dispatch ptr-deref success") (assert (not supRes.isDeadlock) "supervised execution not deadlocked") true)

fn testE2eSnapshotAndCliInference -> Bool
  (let [(ent (snap/makeEntity "req:db-01" (snap/kindReq) "ACID transactions" "src/db.asl:1")) (graph (snap/makeGraph (list ent) "v1.0")) (serialized (snap/serializeGraph graph)) (infPlan (cli/getPhasedConfig (cli/phasePlan))) (infAst (cli/getPhasedConfig (cli/phaseAstPatch))) (help (cli/formatCliHelp))] (assert (>= (stringLength serialized) 20) "serialized graph length >= 20") (assert (= infPlan.thinkingBudget 2048) "plan thinking budget 2048") (assert (= infAst.thinkingBudget 0) "ast thinking budget 0") (assert (>= (stringLength help) 50) "cli help length >= 50") true)

fn ! runTests -> Bool
  (do (testE2eFeedbackAndVmmHydration) (testE2eOnionPipelineAndHorizon) (testE2eCanonicalDispatchAndSupervisor!) (testE2eSnapshotAndCliInference) true)
