(module aslHarness/configTest :x [testDefaultConfig testToggleFeatures testPluginRegistration testExperimentalFlags testQwenProfile testWorktreeDetection testStorageRouting testCascadedConfig testCoverageConfig testDualHarnessProfiles testCoverageIntFallback runTests] :i [(config :a cfg)])

fn testDefaultConfig -> Bool
  (let [(c (cfg/defaultHarnessConfig)) (prof c.profile)] (assert (= prof.name "gemma-4-31b-it") "profile name gemma-4-31b-it") (assert prof.strictFirewall "strict firewall enabled") (assert prof.strictNormalizer "strict normalizer enabled") (assert prof.inMemoryRepl "in memory repl enabled") (assert (cfg/featureEnabled? c "firewall") "firewall feature enabled") (assert (cfg/featureEnabled? c "fsm-normalizer") "fsm-normalizer feature enabled") (assert (cfg/featureEnabled? c "repl-in-memory") "repl-in-memory feature enabled") (assert (cfg/featureEnabled? c "rpc-descriptions") "rpc descriptions enabled") (assert (not (cfg/featureEnabled? c "command-descriptions")) "command descriptions disabled") (assert (cfg/featureEnabled? c "rpc-only-tools") "rpc-only tools enabled") (assert (cfg/featureEnabled? c "batch-required") "batch required enabled") (assert (not (cfg/featureEnabled? c "non-existent-flag")) "non-existent flag disabled") true)

fn testToggleFeatures -> Bool
  (let [(c0 (cfg/defaultHarnessConfig)) (c1 (cfg/toggleFeature c0 "firewall" false)) (c2 (cfg/toggleFeature c1 "custom-lens" true))] (assert (cfg/featureEnabled? c0 "firewall") "c0 firewall enabled") (assert (not (cfg/featureEnabled? c1 "firewall")) "c1 firewall disabled") (assert (cfg/featureEnabled? c2 "custom-lens") "c2 custom-lens enabled") true)

fn testPluginRegistration -> Bool
  (let [(c0 (cfg/defaultHarnessConfig)) (p1 (cfg/makePlugin "plugin-custom-smt" "Custom SMT Guard" "1.0.0" true "SMT verification plugin")) (c1 (cfg/registerPlugin c0 p1)) (plugins c1.plugins) (p0 (optionOr (listHead plugins) (cfg/makePlugin "" "" "" false "")))] (assert (= (listLength plugins) 1) "one plugin registered") (assert (= p0.id "plugin-custom-smt") "plugin id matches") true)

fn testExperimentalFlags -> Bool
  (let [(c0 (cfg/defaultHarnessConfig)) (c1 (cfg/enableExperimental c0 "exp-speculative-tokens"))] (assert (not (cfg/experimentalEnabled? c0 "exp-speculative-tokens")) "c0 experimental disabled") (assert (cfg/experimentalEnabled? c1 "exp-speculative-tokens") "c1 experimental enabled") true)

fn testQwenProfile -> Bool
  (let [(p (cfg/profileQwen05b))] (assert (= p.name "qwen-2.5-0.5b") "qwen profile name") (assert (= p.family "qwen") "qwen family") (assert p.strictFirewall "qwen firewall") (assert p.strictNormalizer "qwen normalizer") (assert p.inMemoryRepl "qwen repl") (assert (= p.maxTokens 2048) "qwen max tokens") true)

fn testWorktreeDetection -> Bool
  (let [(mainKind (cfg/detectRepoKind "dir" "")) (wtContent "gitdir: /Users/dev/repo/.git/worktrees/feat-x") (subContent "gitdir: ../../.git/modules/submodule-a") (wtKind (cfg/detectRepoKind "file" wtContent)) (subKind (cfg/detectRepoKind "file" subContent)) (parsedWt (cfg/parseGitdirFile wtContent "/Users/dev/repo")) (wtInfo (cfg/detectWorktree "file" wtContent "/Users/dev/repo"))] (assert wtInfo.isWorktree "is worktree") (assert (= wtInfo.worktreeId "feat-x") "worktree id matches") (assert (some? parsedWt) "parsed-wt is some") true)

fn testStorageRouting -> Bool
  (let [(storage (cfg/defaultStorageConfig "/root/ws")) (resPath (cfg/routeStorageTarget ":research" "notes.md" storage)) (scratchPath (cfg/routeStorageTarget ":scratch" "temp.json" storage)) (wtScratch (cfg/routeStorageTarget ":worktree-scratch" "log.txt" storage))] (assert (= resPath "/root/ws/.research/notes.md") "research path routed") (assert (= scratchPath "/root/ws/scratch/temp.json") "scratch path routed") (assert (= wtScratch "/root/ws/.worktree-scratch/log.txt") "worktree scratch path routed") true)

fn testCascadedConfig -> Bool
  (let [(cfg0 (cfg/defaultHarnessConfig)) (cascaded (cfg/resolveCascadedConfig cfg0 "fsm-normalizer: false" "" "repl-in-memory: false"))] (assert (not (cfg/featureEnabled? cascaded "fsm-normalizer")) "fsm-normalizer disabled by cascade") (assert (cfg/featureEnabled? cascaded "firewall") "firewall remains enabled") (assert (not (cfg/featureEnabled? cascaded "repl-in-memory")) "repl-in-memory disabled by cascade") true)

fn testCoverageConfig -> Bool
  (let [(c (cfg/defaultHarnessConfig)) (cov c.coverage) (serialized (cfg/coverageConfigToAsnNode cov)) (parsed (cfg/coverageConfigFromAsnNode serialized))] (assert (= cov.desiredCoverage 80.0) "desired coverage is 80.0") (assert (= cov.minAssertionsPerTest 2) "min assertions per test is 2") (assert cov.discountZeroAsserts "discount zero asserts is true") (assert (some? parsed) "parsed coverage config is some") (mt parsed ((some p) (do (assert (= p.desiredCoverage 80.0) "parsed desired coverage matches") (assert (= p.minAssertionsPerTest 2) "parsed min assertions matches") (assert p.discountZeroAsserts "parsed discount zero asserts matches"))) ((none) (assert false "p missing"))) true)

fn testDualHarnessProfiles -> Bool
  (let [(bCfg (cfg/benchmarkHarnessConfig)) (pCfg (cfg/productionHarnessConfig)) (bGw (optionOr (mapGet bCfg.customSettings "gateway-url") "")) (pGw (optionOr (mapGet pCfg.customSettings "gateway-url") ""))] (assert (cfg/featureEnabled? bCfg "airgap") "benchmark airgap active") (assert (cfg/featureEnabled? bCfg "strict-falsification") "benchmark strict falsification active") (assert (cfg/featureEnabled? bCfg "ctrf-tracking") "benchmark ctrf tracking active") (assert (= bGw "http://127.0.0.1:8765/v1") "benchmark gateway is 127.0.0.1:8765") (assert (not (cfg/featureEnabled? pCfg "airgap")) "production airgap disabled") (assert (cfg/featureEnabled? pCfg "epistemic-cycle") "production epistemic cycle active") (assert (cfg/featureEnabled? pCfg "git-worktrees") "production git worktrees active") (assert (cfg/featureEnabled? pCfg "compiler-feedback") "production compiler feedback active") (assert (= pGw "http://127.0.0.1:8765/v1") "production gateway is 127.0.0.1:8765") true)

fn testCoverageIntFallback -> Bool
  (let [(bad (cfg/coverageConfigFromAsnNode (cfg/asnRec (list (cfg/AsnField :key ":desired" :val (cfg/asnInt "x7")))))) (good (cfg/coverageConfigFromAsnNode (cfg/asnRec (list (cfg/AsnField :key ":desired" :val (cfg/asnInt "75"))))))] (assert (mt bad ((some v) (= v.desiredCoverage 80.0)) ((none) false)) "an unparsable int :desired falls back to the default 80.0") (assert (mt good ((some v) (= v.desiredCoverage 75.0)) ((none) false)) "an int :desired 75 reads as 75.0") true)

fn runTests -> Bool
  (do (testDefaultConfig) (testToggleFeatures) (testPluginRegistration) (testExperimentalFlags) (testQwenProfile) (testWorktreeDetection) (testStorageRouting) (testCascadedConfig) (testCoverageConfig) (testCoverageIntFallback) (testDualHarnessProfiles) true)
