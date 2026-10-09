(module aslHarness/tests/rejectTrackingTest :x [testRejectPasses testTrackingRecords runTests] :i [(testTracking :a tt)])

fn testRejectPasses -> Bool
  (let [(metrics (tt/makeTestRunMetrics 2 2 7 1 3 12.5 42.0))] (do (refute (= metrics.rejectionCount 0) "forbidden state was present") true))

fn testTrackingRecords -> Bool
  (let [(plan (tt/makeTestPlan "plan-1" (list "suite-a" "suite-b") true)) (metrics (tt/makeTestRunMetrics 2 2 7 1 3 12.5 42.0)) (record (tt/completeTestRun plan metrics true))] (do (assert (= record.plan.plannedCount 2) "planned count must equal test ID count") (assert (= record.metrics.startedCount 2) "started count must be retained") (assert (= record.metrics.rejectionCount 3) "reject count must be retained") (assert (= record.status "completed") "passing run must be completed") true))

fn runTests -> Bool
  (and (testRejectPasses) (testTrackingRecords))
