(module aslHarness/configPluginTest :x [testModelProfileRoundtrip testStorageConfigRoundtrip testHarnessConfigTree testHookPredicateEvaluation testPluginGuardEvaluation testCascadedConfigAst testMalformedAsnNodes runTests] :i [(config :a cfg) (plugin :a plug)])

fn testModelProfileRoundtrip -> Bool
  (let [(p0 (cfg/profileGemma31b)) (node (cfg/modelProfileToAsnNode p0)) (pOpt (cfg/modelProfileFromAsnNode node))] (do (assert (some? pOpt)) (mt pOpt ((some p1) (do (do (assert (= p1.name p0.name)) (assert (= p1.family p0.family)) (assert p1.strictFirewall) (assert p1.strictNormalizer) (assert p1.inMemoryRepl) (assert (= p1.maxTokens 8192)) (assert (not (= p1.maxTokens 0)))))) ((none) (assert false "p1 missing"))) true))

fn testStorageConfigRoundtrip -> Bool
  (let [(s0 (cfg/defaultStorageConfig "/Users/dev/workspace")) (node (cfg/storageConfigToAsnNode s0)) (sOpt (cfg/storageConfigFromAsnNode node))] (do (assert (some? sOpt)) (mt sOpt ((some s1) (do (do (assert (= s1.masterResearchRoot "/Users/dev/workspace/.research")) (assert (= s1.masterScratchRoot "/Users/dev/workspace/scratch")) (assert (= s1.worktreeScratchRoot "/Users/dev/workspace/.worktree-scratch")) (assert (= s1.localRepoRoot "/Users/dev/workspace")) (assert (not (stringEmpty? s1.localRepoRoot)))))) ((none) (assert false "s1 missing"))) true))

fn testHarnessConfigTree -> Bool
  (let [(tree (cfg/asnCtor "HarnessConfig" (list (cfg/AsnField :key ":firewall" :val (cfg/asnBool true)) (cfg/AsnField :key ":fsm-normalizer" :val (cfg/asnBool false)) (cfg/AsnField :key ":repl-in-memory" :val (cfg/asnBool false))))) (cfgOpt (cfg/harnessConfigFromAsnTree tree))] (do (assert (some? cfgOpt)) (mt cfgOpt ((some c) (do (do (assert (cfg/featureEnabled? c "firewall")) (assert (not (cfg/featureEnabled? c "fsm-normalizer"))) (assert (not (cfg/featureEnabled? c "repl-in-memory")))))) ((none) (assert false "c missing"))) true))

fn testHookPredicateEvaluation -> Bool
  (let [(predDeny (cfg/HookPredicate :hookType (cfg/hookPreCall) :name "guard-destructive-ops" :targetPattern "rm_rf" :actionOverride "deny")) (predAllow (cfg/HookPredicate :hookType (cfg/hookPreCall) :name "guard-read-ops" :targetPattern "read_file" :actionOverride "allow"))] (do (assert (cfg/evaluateHookPredicate predDeny "rm_rf" "guard")) (assert (not (cfg/evaluateHookPredicate predDeny "read_file" "guard"))) (assert (cfg/evaluateHookPredicate predAllow "read_file" "guard")) (assert (not (cfg/evaluateHookPredicate predAllow "write_file" "guard"))) true))

fn testPluginGuardEvaluation -> Bool
  (let [(predBlockTerminal (cfg/HookPredicate :hookType (cfg/hookPreCall) :name "block-shell-subprocesses" :targetPattern "exec_command" :actionOverride "deny")) (cap (plug/PluginCapability :providedTools (list "read_file" "exec_command") :systemPrompts (list "Enforce strict security boundaries.") :hooks (list (cfg/hookPreCall)) :dependencies (list) :conflicts (list) :predicates (list predBlockTerminal))) (plugin (plug/createPlugin "sec-guard" "Security Guard" "1.0.0" 1 cap))] (do (assert (not (plug/evaluatePluginGuards plugin (cfg/hookPreCall) "exec_command"))) (assert (plug/evaluatePluginGuards plugin (cfg/hookPreCall) "read_file")) (assert (plug/evaluatePluginGuards plugin (cfg/hookPostCall) "exec_command")) true))

fn testCascadedConfigAst -> Bool
  (let [(c0 (cfg/defaultHarnessConfig)) (c1 (cfg/resolveCascadedConfig c0 "(:fsm-normalizer false)" "" "(:repl-in-memory false)"))] (do (assert (not (cfg/featureEnabled? c1 "fsm-normalizer"))) (assert (cfg/featureEnabled? c1 "firewall")) (assert (not (cfg/featureEnabled? c1 "repl-in-memory"))) true))

fn testMalformedAsnNodes -> Bool
  (let [(malformed (cfg/asnNil)) (pRes (cfg/modelProfileFromAsnNode malformed)) (sRes (cfg/storageConfigFromAsnNode malformed)) (cRes (cfg/harnessConfigFromAsnTree malformed))] (do (assert (none? pRes)) (assert (none? sRes)) (assert (none? cRes)) (assert (not (some? pRes))) true))

fn runTests -> Bool
  (do (assert (testModelProfileRoundtrip)) (assert (testStorageConfigRoundtrip)) (assert (testHarnessConfigTree)) (assert (testHookPredicateEvaluation)) (assert (testPluginGuardEvaluation)) (assert (testCascadedConfigAst)) (assert (testMalformedAsnNodes)) true)
