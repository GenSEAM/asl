(module aslHarness/m1BenchTest :x [testCreateModelArmBudgetLabel testStrictOfflineWebsearchDisabled testM1TelemetryComputation testEvaluateModelArms testFormatM1Report runM1BenchTests runTests] :i [(m1Bench :a mb)])

fn testCreateModelArmBudgetLabel -> Bool
  (let [(arm0 (mb/createModelArm "Qwen2.5-Coder-0.5B" 0)) (arm1000 (mb/createModelArm "Qwen2.5-Coder-7B" 1000))] (assert (= arm0.budgetLabel "Non-Thinking (0 tokens)") "arm0 budget label") (assert (= arm1000.budgetLabel "Thinking (1000 tokens)") "arm1000 budget label") (assert (not arm0.websearchEnabled) "arm0 websearch disabled") (assert (not arm1000.websearchEnabled) "arm1000 websearch disabled") true)

fn testStrictOfflineWebsearchDisabled -> Bool
  (let [(validArm (mb/createModelArm "Gemma-31B" 0)) (badArm (mb/ModelArm :modelName "Cheat" :thinkingTokens 0 :budgetLabel "" :websearchEnabled true)) (badRes (mb/evaluateModelArm badArm "SWE-001"))] (assert (mb/verifyOfflineIsolation validArm) "valid arm is isolated") (assert (not (mb/verifyOfflineIsolation badArm)) "bad arm is not isolated") (assert (not badRes.passed) "bad arm evaluation failed") true)

fn testM1TelemetryComputation -> Bool
  (let [(tel (mb/recordM1Telemetry 100 200 2000 4096 true))] (assert tel.offlineVerified "telemetry offline verified") (assert (= (float64ToInt64 tel.tokensPerSec) (some 100)) "100 tokens per sec") (assert (= tel.memoryPeakMb 4096) "memory peak is 4096") true)

fn testEvaluateModelArms -> Bool
  (let [(arm1 (mb/createModelArm "Qwen2.5-Coder-0.5B" 0)) (arm2 (mb/createModelArm "Qwen2.5-Coder-1.5B" 0)) (arm3 (mb/createModelArm "Qwen2.5-Coder-3B" 0)) (arm4 (mb/createModelArm "Qwen2.5-Coder-7B" 1000)) (arm5 (mb/createModelArm "Gemma-31B" 1000)) (res1 (mb/evaluateModelArm arm1 "task-1")) (res4 (mb/evaluateModelArm arm4 "task-4"))] (assert res1.passed "res1 passed") (assert res4.passed "res4 passed") (assert (> res4.testPassRate res1.testPassRate) "res4 pass rate > res1") true)

fn testFormatM1Report -> Bool
  (let [(arm1 (mb/createModelArm "Qwen2.5-Coder-0.5B" 0)) (arm2 (mb/createModelArm "Qwen2.5-Coder-7B" 1000)) (res1 (mb/evaluateModelArm arm1 "t1")) (res2 (mb/evaluateModelArm arm2 "t2")) (report (mb/generateM1MatrixReport (list res1 res2))) (formatted (mb/formatM1Report report))] (assert (= report.totalArms 2) "report total arms is 2") (assert (stringContains? formatted "Mac M1 LLM Benchmark Matrix") "report header present") (assert (stringContains? formatted "WebSearch: DISABLED") "websearch disabled text") (assert (stringContains? formatted "Non-Thinking (0 tokens)") "non-thinking text") (assert (stringContains? formatted "Thinking (1000 tokens)") "thinking text") true)

fn runM1BenchTests -> Bool
  (do (testCreateModelArmBudgetLabel) (testStrictOfflineWebsearchDisabled) (testM1TelemetryComputation) (testEvaluateModelArms) (testFormatM1Report) true)

fn runTests -> Bool
  (runM1BenchTests)
