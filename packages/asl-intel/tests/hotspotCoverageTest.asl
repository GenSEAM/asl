(module aslIntel/tests/hotspotCoverageTest
  :x [testPlanCreation
      testCoverageRecording
      testGapAnalysisAndComparison
      testReportFormatting
      runTests]
  :i [(hotspotCoverage :a hc)])

"Verifies planned traversal DAG construction and target counting."
fn testPlanCreation -> Bool
  (let [(p0 (hc/createPlannedTraversal "plan-audit" "Remediation Audit Plan" 2000))
        (t1 (hc/createHotspotTarget "asl-engine:q" "asl/bin/asl-engine" "OP: q" 12 1 "Broken RPC redirect" 2))
        (t2 (hc/createHotspotTarget "asl-engine:engine" "asl/bin/asl-engine" "OP: engine" 15 1 "Mock responses in engine tiers" 2))
        (t3 (hc/createHotspotTarget "asl-engine:patch" "asl/bin/asl-engine" "OP: patch" 8 1 "Regex truncation bug" 2))
        (p1 (hc/planAddTarget p0 t1))
        (p2 (hc/planAddTarget p1 t2))
        (p3 (hc/planAddTarget p2 t3))]
    (assert (= (hc/planTargetCount p3) 3) "Planned targets count must be 3")
    (assert (= p3.totalBudget 2000) "Token budget must be 2000")
    (assert (stringContains? p3.title "Remediation") "Plan title must contain Remediation")
    true)

"Verifies actual inspection visit recording and token accumulation."
fn testCoverageRecording -> Bool
  (let [(c0 (hc/createActualCoverage "run-01" "session-test"))
        (v1 (hc/recordVisit "asl-engine:q" "asl/bin/asl-engine" 2 "verified" 1 150))
        (v2 (hc/recordVisit "asl-engine:engine" "asl/bin/asl-engine" 2 "verified" 2 250))
        (c1 (hc/coverageAddVisit c0 v1))
        (c2 (hc/coverageAddVisit c1 v2))]
    (assert (= (hc/coverageVisitCount c2) 2) "Coverage visits count must be 2")
    (assert (= c2.totalTokens 400) "Total tokens must be 400")
    (assert (hc/isTargetVisited? "asl-engine:q" c2.visits) "Target asl-engine:q must be visited")
    (assert (not (hc/isTargetVisited? "asl-engine:patch" c2.visits)) "Target asl-engine:patch must not be visited")
    true)

"Verifies planned versus actual traversal path gap and drift detection."
fn testGapAnalysisAndComparison -> Bool
  (let [(p0 (hc/createPlannedTraversal "plan-audit" "Full Remediation Audit" 5000))
        (t1 (hc/createHotspotTarget "asl-engine:q" "asl/bin/asl-engine" "q" 12 1 "Fix redirect" 2))
        (t2 (hc/createHotspotTarget "asl-engine:engine" "asl/bin/asl-engine" "engine" 15 1 "Fix mocks" 2))
        (t3 (hc/createHotspotTarget "asl-engine:patch" "asl/bin/asl-engine" "patch" 8 1 "Fix regex" 2))
        (t4 (hc/createHotspotTarget "intel:sym" "asl/bin/asl-engine" "sym" 20 1 "Real graph" 2))
        (t5 (hc/createHotspotTarget "agent:horizon" "asl/packages/asl-agent/src/horizon.asl" "horizon" 5 2 "Cleanup stubs" 1))
        (plan (hc/planAddTarget (hc/planAddTarget (hc/planAddTarget (hc/planAddTarget (hc/planAddTarget p0 t1) t2) t3) t4) t5))
        (c0 (hc/createActualCoverage "run-01" "session-test"))
        (v1 (hc/recordVisit "asl-engine:q" "asl/bin/asl-engine" 2 "verified" 1 150))
        (v2 (hc/recordVisit "asl-engine:engine" "asl/bin/asl-engine" 2 "verified" 2 200))
        (v3 (hc/recordVisit "asl-engine:patch" "asl/bin/asl-engine" 1 "gap" 1 100))
        (v4 (hc/recordVisit "unplanned:drift" "scratch/temp.asl" 1 "clean" 0 50))
        (cov (hc/coverageAddVisit (hc/coverageAddVisit (hc/coverageAddVisit (hc/coverageAddVisit c0 v1) v2) v3) v4))
        (comp (hc/compareTraversalPaths plan cov))]
    (assert (= comp.totalPlanned 5) "Total planned targets must be 5")
    (assert (= comp.totalVisited 4) "Total visits recorded must be 4")
    (assert (= comp.coveredCount 2) "Fully covered targets must be 2")
    (assert (= comp.gapCount 3) "Gap count must be 3 (1 degraded depth, 2 unvisited)")
    (assert (= comp.driftCount 1) "Drift count must be 1 for unplanned visit")
    (assert (= comp.coveragePct 40) "Coverage percentage must be 40%")
    (assert (not comp.isComplete) "Audit must not be complete while gaps remain")
    true)

"Verifies structured ASN report generation and Adjacency DSL graph rendering."
fn testReportFormatting -> Bool
  (let [(p0 (hc/createPlannedTraversal "plan-01" "Test Plan" 1000))
        (t1 (hc/createHotspotTarget "target-a" "fileA.asl" "symA" 5 1 "Test A" 2))
        (t2 (hc/createHotspotTarget "target-b" "fileB.asl" "symB" 10 1 "Test B" 2))
        (plan (hc/planAddTarget (hc/planAddTarget p0 t1) t2))
        (c0 (hc/createActualCoverage "run-test" "session-test"))
        (v1 (hc/recordVisit "target-a" "fileA.asl" 2 "verified" 0 100))
        (cov (hc/coverageAddVisit c0 v1))
        (comp (hc/compareTraversalPaths plan cov))
        (rep (hc/formatCoverageReport comp))
        (graph (hc/renderTraversalGraph plan cov))]
    (assert (stringContains? rep ":coverage-report") "Report must have :coverage-report header")
    (assert (stringContains? rep ":coverage-pct 50") "Report must reflect 50% coverage")
    (assert (stringContains? rep "target-b") "Report must cite unvisited target-b in gaps")
    (assert (stringContains? graph ":traversal-graph (plan-01 > target-a:covered target-b:gap)") "Graph must render Adjacency DSL with covered/gap status")
    true)

"Runs all hotspot coverage test suites."
fn runTests -> Bool
  (let [(t1 (testPlanCreation))
        (t2 (testCoverageRecording))
        (t3 (testGapAnalysisAndComparison))
        (t4 (testReportFormatting))] (and t1 (and t2 (and t3 t4))))
