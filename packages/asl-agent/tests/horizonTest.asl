(module aslAgent/horizonTest :x [testHorizonDepthExpansion testHorizonBudgetBounding testHealthMatrixCycleDetection testHealthSummaryFormatting runTests] :i [(horizon :a hor)])

"run: (run-tests)"

fn testHorizonDepthExpansion -> Bool
  (let [(req0 (hor/makeHorizonRequest "policy/check" 0 500)) (res0 (hor/expandHorizon req0)) (req1 (hor/makeHorizonRequest "policy/check" 1 500)) (res1 (hor/expandHorizon req1))] (assert (= (listLength res0.interfaceStubs) 0) "depth 0 has 0 stubs") (assert (= (listLength res1.interfaceStubs) 2) "depth 1 has 2 stubs") true)

fn testHorizonBudgetBounding -> Bool
  (let [(req (hor/makeHorizonRequest "agent/step" 2 1000)) (res (hor/expandHorizon req))] (assert (<= res.tokensUsed 1000) "tokens used within budget") (assert (> res.tokensUsed 0) "tokens used is positive") true)

fn testHealthMatrixCycleDetection -> Bool
  (let [(mOk (hor/computeHealthMatrix (list "a" "b") false)) (mCyc (hor/computeHealthMatrix (list "a" "b") true))] (assert mOk.isHealthy "matrix without cycles is healthy") (assert (not mCyc.isHealthy) "matrix with cycles is unhealthy") (assert (= (listLength mCyc.cycles) 1) "matrix has 1 cycle") true)

fn testHealthSummaryFormatting -> Bool
  (let [(m (hor/computeHealthMatrix (list "a") false)) (summary (hor/formatHealthSummary m))] (assert (>= (stringLength summary) 15) "health summary length >= 15") (assert (not (stringContains? summary "unhealthy")) "healthy summary does not contain unhealthy") true)

fn runTests -> Bool
  (do (testHorizonDepthExpansion) (testHorizonBudgetBounding) (testHealthMatrixCycleDetection) (testHealthSummaryFormatting) true)
