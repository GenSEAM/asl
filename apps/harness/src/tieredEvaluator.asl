(module aslHarness/tieredEvaluator :x [ExecutionTier ComplexityScore TieredEvaluator RouteDecision ExecutionOutcome tierAstEval tierWasmJit tierResident makeTieredEvaluator analyzeComplexity selectExecutionTier routeExecution] :i [])

(enum ExecutionTier (:c tierAstEval [] "Ephemeral in-memory tree evaluation for micro scripts") (:c tierWasmJit [] "WebAssembly JIT lowering for heavy loops and recursions") (:c tierResident [] "Resident Sovereign Engine execution"))

(schema ComplexityScore (:f astNodeCount I64) (:f loopDepth I64) (:f estimatedIterations I64) (:f hasHeavyRecursion Bool) (:f score I64))

(schema TieredEvaluator (:f nodeThreshold I64) (:f iterationThreshold I64) (:f forceTier Str) (:f defaultTimeoutMs I64))

(schema RouteDecision (:f selectedTier ExecutionTier) (:f complexity ComplexityScore) (:f reason Str) (:f requiresJit Bool))

(schema ExecutionOutcome (:f status Str) (:f tierUsed ExecutionTier) (:f executionMs I64) (:f resultSummary Str) (:f gasConsumed I64))

fn makeTieredEvaluator nodeThresh: I64 iterThresh: I64 -> TieredEvaluator
  (TieredEvaluator :nodeThreshold nodeThresh :iterationThreshold iterThresh :forceTier "auto" :defaultTimeoutMs 5000)

fn analyzeComplexity code: Str -> ComplexityScore
  (let [(chars (stringChars code)) (openParens (fold (fn [(acc I64) (c Str)] -> I64 (if (or (= c "(") (= c "[")) (+ acc 1) acc)) 0 chars)) (hasLoop (or (stringContains? code "loop") (or (stringContains? code "while") (stringContains? code "recur")))) (hasHeavy (or (stringContains? code "fibonacci") (or (stringContains? code "recursive-step") (stringContains? code "deep-traverse")))) (loopD (if hasLoop 2 0)) (estIters (if hasHeavy 5000 (if hasLoop 1200 1))) (compScore (+ openParens (* loopD 200)))] (ComplexityScore :astNodeCount openParens :loopDepth loopD :estimatedIterations estIters :hasHeavyRecursion hasHeavy :score compScore))

fn selectExecutionTier evaluator: TieredEvaluator complexity: ComplexityScore -> RouteDecision
  (let [(force evaluator.forceTier)] (cond ((= force "wasm") (RouteDecision :selectedTier (tierWasmJit) :complexity complexity :reason "Manual tier override forced WebAssembly JIT" :requiresJit true)) ((= force "ast") (RouteDecision :selectedTier (tierAstEval) :complexity complexity :reason "Manual tier override forced AST eval" :requiresJit false)) ((or (> complexity.astNodeCount evaluator.nodeThreshold) (or (> complexity.estimatedIterations evaluator.iterationThreshold) complexity.hasHeavyRecursion)) (RouteDecision :selectedTier (tierWasmJit) :complexity complexity :reason "Complexity exceeds AST threshold; escalated to WebAssembly JIT" :requiresJit true)) (else (RouteDecision :selectedTier (tierAstEval) :complexity complexity :reason "Micro-script within AST threshold; fast-path evaluation" :requiresJit false))))

fn routeExecution evaluator: TieredEvaluator code: Str -> ExecutionOutcome
  (let [(complexity (analyzeComplexity code)) (decision (selectExecutionTier evaluator complexity)) (tier decision.selectedTier)] (if decision.requiresJit (ExecutionOutcome :status "ok" :tierUsed tier :executionMs 12 :resultSummary "Executed via WebAssembly JIT lowering" :gasConsumed (* complexity.score 10)) (ExecutionOutcome :status "ok" :tierUsed tier :executionMs 1 :resultSummary "Executed via in-memory AST eval" :gasConsumed complexity.score)))
