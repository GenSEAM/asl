(module aslHarness/tieredEvaluatorTest :x [testTieredEvaluatorConstruction testAnalyzeComplexityMicro testAnalyzeComplexityHeavy testSelectExecutionTierAst testSelectExecutionTierWasmEscalation testManualTierOverride testRouteExecutionEndToEnd runTests] :i [(tieredEvaluator :a te)])

fn testTieredEvaluatorConstruction -> Bool
  (let [(ev (te/makeTieredEvaluator 500 1000))] (assert (= ev.nodeThreshold 500) "Node threshold must be 500") (assert (= ev.iterationThreshold 1000) "Iteration threshold must be 1000") (assert (= ev.forceTier "auto") "Default force tier must be auto") (assert (= ev.defaultTimeoutMs 5000) "Default timeout must be 5000ms") true)

fn testAnalyzeComplexityMicro -> Bool
  (let [(code "(+ 1 2)") (c (te/analyzeComplexity code))] (assert (= c.astNodeCount 1) "Micro expression has 1 open paren") (assert (= c.loopDepth 0) "Micro expression has 0 loop depth") (assert (not c.hasHeavyRecursion) "Micro expression has no recursion") (assert (> c.score 0) "Composite score must be positive") true)

fn testAnalyzeComplexityHeavy -> Bool
  (let [(code "(loop [i 0] (fibonacci i))") (c (te/analyzeComplexity code))] (assert c.hasHeavyRecursion "Must detect heavy recursion keyword") (assert (>= c.estimatedIterations 5000) "Estimated iterations must be >= 5000") (assert (>= c.score 200) "Composite score must account for loop depth") true)

fn testSelectExecutionTierAst -> Bool
  (let [(ev (te/makeTieredEvaluator 500 1000)) (c (te/ComplexityScore :astNodeCount 10 :loopDepth 0 :estimatedIterations 1 :hasHeavyRecursion false :score 10)) (dec (te/selectExecutionTier ev c))] (assert (not dec.requiresJit) "Micro script must not require JIT") (assert (stringContains? dec.reason "AST") "Routing reason must identify AST fast-path") (assert (= dec.complexity.score 10) "Complexity must be preserved") true)

fn testSelectExecutionTierWasmEscalation -> Bool
  (let [(ev (te/makeTieredEvaluator 500 1000)) (c (te/ComplexityScore :astNodeCount 600 :loopDepth 2 :estimatedIterations 2500 :hasHeavyRecursion true :score 1000)) (dec (te/selectExecutionTier ev c))] (assert dec.requiresJit "Heavy workload must trigger JIT") (assert (stringContains? dec.reason "WebAssembly") "Routing reason must cite WebAssembly JIT") (assert (= dec.complexity.score 1000) "Score must match") true)

fn testManualTierOverride -> Bool
  (let [(evWasm (te/TieredEvaluator :nodeThreshold 500 :iterationThreshold 1000 :forceTier "wasm" :defaultTimeoutMs 5000)) (evAst (te/TieredEvaluator :nodeThreshold 500 :iterationThreshold 1000 :forceTier "ast" :defaultTimeoutMs 5000)) (cMicro (te/ComplexityScore :astNodeCount 2 :loopDepth 0 :estimatedIterations 1 :hasHeavyRecursion false :score 2)) (cHeavy (te/ComplexityScore :astNodeCount 800 :loopDepth 2 :estimatedIterations 5000 :hasHeavyRecursion true :score 1200)) (decWasm (te/selectExecutionTier evWasm cMicro)) (decAst (te/selectExecutionTier evAst cHeavy))] (assert decWasm.requiresJit "Manual wasm override must require JIT") (assert (stringContains? decWasm.reason "forced WebAssembly") "Reason must note manual wasm override") (assert (not decAst.requiresJit) "Manual ast override must bypass JIT") (assert (stringContains? decAst.reason "forced AST") "Reason must note manual ast override") true)

fn testRouteExecutionEndToEnd -> Bool
  (let [(ev (te/makeTieredEvaluator 500 1000)) (outMicro (te/routeExecution ev "(+ 1 2)")) (outHeavy (te/routeExecution ev "(loop [i 0] (fibonacci 10))"))] (assert (= outMicro.status "ok") "Micro outcome must be ok") (assert (= outMicro.executionMs 1) "Micro outcome execution time must be 1ms") (assert (stringContains? outMicro.resultSummary "AST eval") "Summary must report AST eval") (assert (= outHeavy.status "ok") "Heavy outcome must be ok") (assert (= outHeavy.executionMs 12) "Heavy outcome execution time must be 12ms") (assert (stringContains? outHeavy.resultSummary "WebAssembly") "Summary must report WebAssembly") true)

fn runTests -> Bool
  (and (testTieredEvaluatorConstruction) (and (testAnalyzeComplexityMicro) (and (testAnalyzeComplexityHeavy) (and (testSelectExecutionTierAst) (and (testSelectExecutionTierWasmEscalation) (and (testManualTierOverride) (testRouteExecutionEndToEnd)))))))
