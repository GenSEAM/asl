(module aslHarness/testTracking :x [TestPlan TestRunMetrics TestRunRecord makeTestPlan makeTestRunMetrics completeTestRun])

(schema TestPlan (:f planId Str) (:f testIds (List Str)) (:f plannedCount I64) (:f metricsEnabled Bool))

(schema TestRunMetrics (:f startedCount I64) (:f completedCount I64) (:f assertionCount I64) (:f refutationCount I64) (:f rejectionCount I64) (:f elapsedMs F64) (:f rssMb F64))

(schema TestRunRecord (:f plan TestPlan) (:f metrics TestRunMetrics) (:f status Str))

fn makeTestPlan planId: Str testIds: (List Str) metricsEnabled: Bool -> TestPlan
  (TestPlan :planId planId :testIds testIds :plannedCount (listLength testIds) :metricsEnabled metricsEnabled)

fn makeTestRunMetrics started: I64 completed: I64 assertions: I64 refutations: I64 rejections: I64 elapsed: F64 rss: F64 -> TestRunMetrics
  (TestRunMetrics :startedCount started :completedCount completed :assertionCount assertions :refutationCount refutations :rejectionCount rejections :elapsedMs elapsed :rssMb rss)

fn completeTestRun plan: TestPlan metrics: TestRunMetrics passed: Bool -> TestRunRecord
  (TestRunRecord :plan plan :metrics metrics :status (if passed "completed" "failed"))
