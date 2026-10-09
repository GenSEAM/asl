(module aslAgent/test :x [testFastTriage testConsultAndRefine testPlanExecution testCircuitBreaker testVersionBanner runTests] :i [(eddie :a ed) (policy :a pol)])

fn testFastTriage -> Bool
  (let [(vHelp (ed/fastTriage "help")) (vCode (ed/fastTriage "refactor app"))] (assert (= vHelp (ed/consult)) "fast-triage help should yield consult") (assert (= vCode (ed/swarm)) "fast-triage code should yield swarm") true)

fn testConsultAndRefine -> Bool
  (let [(planAmbig (ed/consultAndRefine "help" true)) (planClear (ed/consultAndRefine "build compiler" false))] (assert planAmbig.followUpNeeded "ambiguous plan requires follow up") (assert (= planAmbig.taskId "addie-consult") "ambiguous task-id match") (assert (not planClear.followUpNeeded) "clear plan does not require follow up") (assert (= planClear.speculativeBranches 2) "clear plan speculative branches") true)

fn testPlanExecution -> Bool
  (let [(plan (ed/planExecution "task-001" "implement vector search"))] (assert (= plan.taskId "task-001") "task-id matches") (assert (= plan.circuitBreakerLimit 2) "circuit breaker limit") (assert (= (listLength plan.assignedAgents) 3) "three agents assigned") true)

fn testCircuitBreaker -> Bool
  (do (assert (ed/evaluateCircuitBreaker 2 2) "circuit breaker fires at threshold") (assert (ed/evaluateCircuitBreaker 3 2) "circuit breaker fires above threshold") (assert (not (ed/evaluateCircuitBreaker 1 2)) "circuit breaker open below threshold") true)

fn testVersionBanner -> Bool
  (do (assert (= (ed/addieVersion) "0.1.0") "addie-version is 0.1.0") (assert (= (ed/eddieVersion) "0.1.0") "eddie-version is 0.1.0") (assert (stringContains? (ed/addieBanner) "GSA (GenSEAM Agent)") "addie banner contains GSA") (assert (stringContains? (ed/eddieBanner) "GSA (GenSEAM Agent)") "eddie banner contains GSA") true)

fn testGsaRun! -> Bool
  (let [(out (ed/gsaRun! "Audit dependencies in /workspace/src/main.asl" "/tmp" (pol/levelAuto)))] (assert (stringContains? out "Session complete") "gsa-run should complete session") true)

fn testGsaVersion -> Bool
  (do (assert (= (ed/gsaVersion) "0.1.0") "gsa-version is 0.1.0") (assert (stringContains? (ed/gsaBanner) "GSA (GenSEAM Agent)") "gsa banner contains GSA") true)

fn testTaskTier -> Bool
  (let [(tier1 (ed/tier1)) (tier2 (ed/tier2))] (assert (= tier1 (ed/tier1)) "tier-1 matches") (assert (= tier2 (ed/tier2)) "tier-2 matches") true)

fn ! runTests -> Bool
  (do (assert (testFastTriage)) (assert (testConsultAndRefine)) (assert (testPlanExecution)) (assert (testCircuitBreaker)) (assert (testVersionBanner)) (assert (testGsaRun!)) (assert (testGsaVersion)) (assert (testTaskTier)) true)
