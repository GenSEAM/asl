(module aslHarness/sotpartyRunner :x [SotPartyTask AblationArm SotPartyRun ParetoMetric makeSwe006SotTask makeAblationArms executeSotpartyTask evaluateSotpartySuite formatParetoMatrix] :i [])

(schema SotPartyTask (:f id Str) (:f title Str) (:f blastRadiusPackages (List Str)) (:f maxTokenCeiling I64) (:f testCommand Str))

(schema AblationArm (:f name Str) (:f withImpactAnalysis Bool) (:f withCircuitBreaker Bool) (:f withEgraphOptimization Bool))

(schema SotPartyRun (:f taskId Str) (:f arm AblationArm) (:f resolved Bool) (:f tokensConsumed I64) (:f trippedBreaker Bool) (:f callerCyclesDetected I64) (:f durationMs I64))

(schema ParetoMetric (:f armName Str) (:f solveRate F64) (:f avgTokens I64) (:f paretoOptimal Bool) (:f tokenCompactionRatio F64))

fn makeSwe006SotTask -> SotPartyTask
  (SotPartyTask :id "SWE-006" :title "Cross-Package Blast Radius and Caller Cycle Migration" :blastRadiusPackages (list "agent-core" "mem" "harness") :maxTokenCeiling 35000 :testCommand "asl test harness/tests/coding-test.asl")

fn makeAblationArms -> (List AblationArm)
  (let [(armBase (AblationArm :name "Arm-Baseline" :withImpactAnalysis false :withCircuitBreaker false :withEgraphOptimization false)) (armHarness (AblationArm :name "Arm-AslHarness" :withImpactAnalysis true :withCircuitBreaker true :withEgraphOptimization true))] (list armBase armHarness))

fn executeSotpartyTask task: SotPartyTask arm: AblationArm tokens: I64 passed: Bool cycles: I64 latencyMs: I64 -> SotPartyRun
  (let [(ceiling task.maxTokenCeiling) (breakerActive arm.withCircuitBreaker) (tripped (and breakerActive (> tokens ceiling))) (finalTokens (if tripped ceiling tokens)) (finalResolved (if tripped false passed))] (SotPartyRun :taskId task.id :arm arm :resolved finalResolved :tokensConsumed finalTokens :trippedBreaker tripped :callerCyclesDetected cycles :durationMs latencyMs))

fn evaluateSotpartySuite arm: AblationArm runs: (List SotPartyRun) -> ParetoMetric
  (if (listEmpty? runs) (ParetoMetric :armName arm.name :solveRate 0.0 :avgTokens 0 :paretoOptimal false :tokenCompactionRatio 1.0) (let [(totalRuns (listLength runs)) (totalResolved (fold (fn [(acc I64) (r SotPartyRun)] -> I64 (if r.resolved (+ acc 1) acc)) 0 runs)) (totalTokens (fold (fn [(acc I64) (r SotPartyRun)] -> I64 (+ acc r.tokensConsumed)) 0 runs)) (avgTok (/ totalTokens totalRuns)) (solve (/ (int64ToFloat64 totalResolved) (int64ToFloat64 totalRuns))) (ratio (if (> avgTok 0) (/ 35000.0 (int64ToFloat64 avgTok)) 1.0)) (optimal (and (>= solve 0.8) (<= avgTok 15000)))] (ParetoMetric :armName arm.name :solveRate solve :avgTokens avgTok :paretoOptimal optimal :tokenCompactionRatio ratio)))

fn formatParetoMatrix metrics: (List ParetoMetric) -> Str
  (let [(rows (fold (fn [(acc Str) (m ParetoMetric)] -> Str (let [(entry (str "    (:row :arm \"" m.armName "\"" " :solve " (stringFromFloat64 m.solveRate) " :avg-tokens " (stringFromInt64 m.avgTokens) " :pareto-optimal " (if m.paretoOptimal "true" "false") " :compaction " (stringFromFloat64 m.tokenCompactionRatio) ")"))] (if (stringEmpty? acc) entry (str acc "\n" entry)))) "" metrics))] (str "(:pareto-matrix\n" rows "\n" "  )"))
