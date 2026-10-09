(module aslHarness/ablationTest :x [testAblationPreload testAblationHealth testAblationDeps testAblationFsm testAblationAstGate testAblationSanitizer testAblationPointer testAblationGateway testAblationDag testFullAblationReport runTests] :i [(ablation :a ab)])

fn testAblationPreload -> Bool
  (let [(m (ab/measurePreloadAblation))] (assert m.verifiedPass "preload ablation verified pass") (assert (stringContains? m.delta "-95.0%") "preload token advantage delta") (assert (> m.improvementFactor 10.0) "preload improvement factor > 10") true)

fn testAblationHealth -> Bool
  (let [(m (ab/measureHealthAblation))] (assert m.verifiedPass "health ablation verified pass") (assert (stringContains? m.delta "cycle prevention") "health delta contains cycle prevention") true)

fn testAblationDeps -> Bool
  (let [(m (ab/measureDepsAblation))] (assert m.verifiedPass "deps ablation verified pass") (assert (stringContains? m.delta "Zero API skew") "deps delta zero API skew") true)

fn testAblationFsm -> Bool
  (let [(m (ab/measureFsmAblation))] (assert m.verifiedPass "fsm ablation verified pass") (assert (stringContains? m.delta "valid execution") "fsm delta valid execution") true)

fn testAblationAstGate -> Bool
  (let [(m (ab/measureAstGateAblation))] (assert m.verifiedPass "ast gate ablation verified pass") (assert (stringContains? m.delta "test preservation") "ast gate delta test preservation") true)

fn testAblationSanitizer -> Bool
  (let [(m (ab/measureSanitizerAblation))] (assert m.verifiedPass "sanitizer ablation verified pass") (assert (stringContains? m.delta "-93.5%") "sanitizer delta -93.5%") true)

fn testAblationPointer -> Bool
  (let [(m (ab/measurePointerAblation))] (assert m.verifiedPass "pointer ablation verified pass") (assert (stringContains? m.delta "-99.3%") "pointer delta -99.3%") true)

fn testAblationGateway -> Bool
  (let [(m (ab/measureGatewayAblation))] (assert m.verifiedPass "gateway ablation verified pass") (assert (stringContains? m.delta "unverified task aborts") "gateway delta unverified task aborts") true)

fn testAblationDag -> Bool
  (let [(m (ab/measureDagAblation))] (assert m.verifiedPass "dag ablation verified pass") (assert (stringContains? m.delta "-90% wasted turns") "dag delta -90% wasted turns") true)

fn testFullAblationReport -> Bool
  (let [(rep (ab/runFullAblationSuite)) (md (ab/formatAblationMarkdown rep))] (assert (= (listLength rep.metrics) 9) "metrics length 9") (assert (= rep.totalRegressionsPrevented 9) "total regressions prevented 9") (assert (stringContains? md "Empirical Ablation Analysis") "report title") (assert (stringContains? md "Graph-Horizon Preload") "report preload") (assert (stringContains? md "Blackboard Task-Premise DAG") "report dag") (assert (stringContains? md "Overall Context Token Reduction") "report token reduction") true)

fn runTests -> Bool
  (do (testAblationPreload) (testAblationHealth) (testAblationDeps) (testAblationFsm) (testAblationAstGate) (testAblationSanitizer) (testAblationPointer) (testAblationGateway) (testAblationDag) (testFullAblationReport) true)
