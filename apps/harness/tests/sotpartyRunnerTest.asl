(module aslHarness/sotpartyRunnerTest :x [testSwe006TaskConstruction testAblationArmsSetup testExecutionNormalPass testCircuitBreakerTrip testParetoFrontierEvaluation testFormatParetoMatrix runTests] :i [(sotpartyRunner :a sot)])

fn testSwe006TaskConstruction -> Bool
  (let [(task (sot/makeSwe006SotTask))] (assert (= task.id "SWE-006") "Task ID must be SWE-006") (assert (= task.maxTokenCeiling 35000) "Circuit breaker ceiling must be 35000 tokens") (assert (= (listLength task.blastRadiusPackages) 3) "Must identify 3 blast radius packages") (assert (listContains? task.blastRadiusPackages "agent-core") "Must include agent-core") true)

fn testAblationArmsSetup -> Bool
  (let [(arms (sot/makeAblationArms)) (base (optionOr (listHead arms) (sot/AblationArm :name "" :withImpactAnalysis false :withCircuitBreaker false :withEgraphOptimization false))) (harness (optionOr (listHead (optionOr (listTail arms) (list))) (sot/AblationArm :name "" :withImpactAnalysis false :withCircuitBreaker false :withEgraphOptimization false)))] (assert (= (listLength arms) 2) "Must configure exactly 2 ablation arms") (assert (= base.name "Arm-Baseline") "First arm is Baseline") (assert (not base.withCircuitBreaker) "Baseline has no circuit breaker") (assert (= harness.name "Arm-AslHarness") "Second arm is ASL Harness") (assert harness.withCircuitBreaker "ASL Harness equips 35k circuit breaker") true)

fn testExecutionNormalPass -> Bool
  (let [(task (sot/makeSwe006SotTask)) (arms (sot/makeAblationArms)) (harness (optionOr (listHead (optionOr (listTail arms) (list))) (sot/AblationArm :name "" :withImpactAnalysis false :withCircuitBreaker false :withEgraphOptimization false))) (run (sot/executeSotpartyTask task harness 12000 true 0 450))] (assert run.resolved "Task must resolve successfully") (assert (not run.trippedBreaker) "Circuit breaker must not trip") (assert (= run.tokensConsumed 12000) "Tokens consumed must match 12000") (assert (= run.durationMs 450) "Duration must record 450ms") true)

fn testCircuitBreakerTrip -> Bool
  (let [(task (sot/makeSwe006SotTask)) (arms (sot/makeAblationArms)) (harness (optionOr (listHead (optionOr (listTail arms) (list))) (sot/AblationArm :name "" :withImpactAnalysis false :withCircuitBreaker false :withEgraphOptimization false))) (run (sot/executeSotpartyTask task harness 42000 true 2 1200))] (assert (not run.resolved) "Tripped run must not be marked resolved") (assert run.trippedBreaker "Circuit breaker must trip on 42000 tokens") (assert (= run.tokensConsumed 35000) "Tokens consumed capped at 35000 ceiling") true)

fn testParetoFrontierEvaluation -> Bool
  (let [(task (sot/makeSwe006SotTask)) (arms (sot/makeAblationArms)) (harness (optionOr (listHead (optionOr (listTail arms) (list))) (sot/AblationArm :name "" :withImpactAnalysis false :withCircuitBreaker false :withEgraphOptimization false))) (r1 (sot/executeSotpartyTask task harness 8000 true 0 300)) (r2 (sot/executeSotpartyTask task harness 12000 true 0 400)) (runs (list r1 r2)) (metric (sot/evaluateSotpartySuite harness runs))] (assert (= metric.solveRate 1.0) "Solve rate must be 1.0 for 2 passing runs") (assert (= metric.avgTokens 10000) "Average tokens must be 10000") (assert metric.paretoOptimal "Must be recognized as Pareto optimal") (assert (> metric.tokenCompactionRatio 3.0) "Token compaction ratio must exceed 3.0x") true)

fn testFormatParetoMatrix -> Bool
  (let [(task (sot/makeSwe006SotTask)) (arms (sot/makeAblationArms)) (harness (optionOr (listHead (optionOr (listTail arms) (list))) (sot/AblationArm :name "" :withImpactAnalysis false :withCircuitBreaker false :withEgraphOptimization false))) (r1 (sot/executeSotpartyTask task harness 10000 true 0 350)) (metric (sot/evaluateSotpartySuite harness (list r1))) (mat (sot/formatParetoMatrix (list metric)))] (assert (stringContains? mat ":pareto-matrix") "Matrix must contain header") (assert (stringContains? mat "Arm-AslHarness") "Matrix must include arm name") (assert (stringContains? mat ":pareto-optimal true") "Matrix must display pareto status") true)

fn runTests -> Bool
  (and (testSwe006TaskConstruction) (and (testAblationArmsSetup) (and (testExecutionNormalPass) (and (testCircuitBreakerTrip) (and (testParetoFrontierEvaluation) (testFormatParetoMatrix))))))
