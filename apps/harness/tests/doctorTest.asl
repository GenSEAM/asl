(module aslHarness/doctorTest :x [testPluginRegistryCreation TestDoctorCleanBaseline TestDoctorDetectToolCollision TestDoctorDetectMissingDependency TestDoctorDetectPromptContradiction TestDoctorLlmChainFastPathSkip TestDoctorLlmChainActivationOnIssues testFormatDoctorReport runDoctorTests runTests] :i [(plugin :a pl) (doctor :a doc) (config :a cfg)])

fn testPluginRegistryCreation -> Bool
  (let [(reg (pl/buildStandardHarnessPlugins)) (tools (pl/registryGetTools reg))] (assert (= reg.activeCount 5) "reg count is 5") (assert (pl/containsString? tools "intel-preload") "has intel-preload") (assert (pl/containsString? tools "audit-ast-mutation") "has audit-ast-mutation") (assert (pl/containsString? tools "extract-css-variables") "has extract-css-variables") (assert (pl/containsString? tools "scan-component-usages") "has scan-component-usages") (assert (pl/containsString? tools "run-sandboxed-script") "has run-sandboxed-script") true)

fn TestDoctorCleanBaseline -> Bool
  (let [(reg (pl/buildStandardHarnessPlugins)) (diag (doc/diagnoseAgentPlugins reg))] (assert diag.healthy "clean is healthy") (assert (= diag.healthScore 100) "health score is 100") (assert (= (listLength diag.collisions) 0) "0 collisions") (assert (= (listLength diag.contradictions) 0) "0 contradictions") (assert (= (listLength diag.missingDeps) 0) "0 missing deps") true)

fn TestDoctorDetectToolCollision -> Bool
  (let [(reg (pl/buildStandardHarnessPlugins)) (badPlugin (pl/createPlugin "custom-plugin" "Custom Duplicating Plugin" "1.0" 1 (pl/PluginCapability :providedTools (list "intel-preload") :systemPrompts (list) :hooks (list) :dependencies (list) :conflicts (list)))) (regWithCollision (pl/registryAdd reg badPlugin)) (diag (doc/diagnoseAgentPlugins regWithCollision))] (assert (not diag.healthy) "collision is not healthy") (assert (< diag.healthScore 100) "health score < 100") (assert (= (listLength diag.collisions) 1) "1 collision found") (let [(c (optionOr (listHead diag.collisions) (doc/ToolCollision :toolName "" :pluginA "" :pluginB "")))] (assert (= c.toolName "intel-preload") "collision tool is intel-preload")) true)

fn TestDoctorDetectMissingDependency -> Bool
  (let [(reg (pl/registryCreate)) (p (pl/createPlugin "consumer-plugin" "Needs Auth" "1.0" 1 (pl/PluginCapability :providedTools (list "do-something") :systemPrompts (list) :hooks (list) :dependencies (list "missing-auth-plugin") :conflicts (list)))) (regUnmet (pl/registryAdd reg p)) (diag (doc/diagnoseAgentPlugins regUnmet))] (assert (not diag.healthy) "missing dep is not healthy") (assert (= (listLength diag.missingDeps) 1) "1 missing dep found") true)

fn TestDoctorDetectPromptContradiction -> Bool
  (let [(reg (pl/registryCreate)) (p1 (pl/createPlugin "strict-planner" "Strict Planner" "1.0" 1 (pl/PluginCapability :providedTools (list "tool1") :systemPrompts (list "Never mutate files without plan registered.") :hooks (list) :dependencies (list) :conflicts (list)))) (p2 (pl/createPlugin "auto-patcher" "Auto Patcher" "1.0" 2 (pl/PluginCapability :providedTools (list "tool2") :systemPrompts (list "Auto-apply patches silently without waiting.") :hooks (list) :dependencies (list) :conflicts (list)))) (regConflict (pl/registryAdd (pl/registryAdd reg p1) p2)) (diag (doc/diagnoseAgentPlugins regConflict))] (assert (not diag.healthy) "contradiction is not healthy") (assert (> (listLength diag.contradictions) 0) "contradictions found") true)

fn TestDoctorLlmChainFastPathSkip -> Bool
  (let [(reg (pl/buildStandardHarnessPlugins)) (diag (doc/diagnoseAgentPlugins reg)) (after (doc/inspectWithLlm diag "gemma-31b"))] (assert after.healthy "fast path is healthy") (assert (not after.llmInspected) "llm was not inspected") true)

fn TestDoctorLlmChainActivationOnIssues -> Bool
  (let [(reg (pl/registryCreate)) (p1 (pl/createPlugin "p1" "P1" "1.0" 1 (pl/PluginCapability :providedTools (list "t1") :systemPrompts (list "Never mutate files without plan.") :hooks (list) :dependencies (list) :conflicts (list)))) (p2 (pl/createPlugin "p2" "P2" "1.0" 2 (pl/PluginCapability :providedTools (list "t1") :systemPrompts (list "Auto-apply patches silently.") :hooks (list) :dependencies (list) :conflicts (list)))) (regBad (pl/registryAdd (pl/registryAdd reg p1) p2)) (diag (doc/diagnoseAgentPlugins regBad)) (after (doc/inspectWithLlm diag "qwen-2.5-coder"))] (assert (not after.healthy) "issues not healthy") (assert after.llmInspected "llm was inspected") (assert (> (listLength after.remediations) 0) "remediations exist") true)

fn testFormatDoctorReport -> Bool
  (let [(reg (pl/buildStandardHarnessPlugins)) (diag (doc/diagnoseAgentPlugins reg)) (report (doc/formatDoctorReport diag))] (assert (stringContains? report "Agent Doctor Inspection Report") "report header present") (assert (stringContains? report "HEALTHY (100/100)") "healthy text present") true)

fn runDoctorTests -> Bool
  (do (testPluginRegistryCreation) (TestDoctorCleanBaseline) (TestDoctorDetectToolCollision) (TestDoctorDetectMissingDependency) (TestDoctorDetectPromptContradiction) (TestDoctorLlmChainFastPathSkip) (TestDoctorLlmChainActivationOnIssues) (testFormatDoctorReport) true)

fn runTests -> Bool
  (runDoctorTests)
