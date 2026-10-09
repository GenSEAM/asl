(module aslHarness/tests/sweBenchTest :x [testTasks testTelemetry testMatrix testSixArmMatrix! testSwe006 runTests] :i [(sweBench :a swe)])

fn testTasks -> Bool
  (let [(tasks (swe/standardSweTasks))] (assert (= (listLength tasks) 6) "task count is 6") (assert (= (optionOr (listHead tasks) (swe/SweTask :id "" :title "" :description "" :targetFile "" :expectedDiffLines 0 :testCommand "")).id "SWE-001") "first task is SWE-001") true)

fn testTelemetry -> Bool
  (let [(r1 (swe/makeTelemetry "ASL Coding Harness" "SWE-001" true 1200 150 450 0.0004 0.75)) (r2 (swe/makeTelemetry "ASL Coding Harness" "SWE-002" true 1100 120 420 0.0003 0.80)) (row (swe/evaluateArmTelemetry (list r1 r2) "ASL Coding Harness")) (bs (swe/BenchmarkSuite :id "test" :name "name" :taskCount 2)) (rt (swe/RunTelemetry :armName "test" :taskId "task" :resolved true :timeMs 100 :promptTokens 10 :sampledTokens 10 :costUsd 0.1 :astDensity 0.5))] (assert (= row.armName "ASL Coding Harness") "arm name matches") (assert (= row.solveRate "100%") "solve rate is 100%") (assert (= row.tokenReduction "-68.4%") "token reduction is -68.4%") (assert (< row.totalCostUsd 0.01) "total cost < 0.01") (assert (= bs.id "test") "BenchmarkSuite id matches") (assert (= rt.armName "test") "RunTelemetry arm matches") (refute (= bs.id "wrong") "BenchmarkSuite refute wrong id") true)

fn testMatrix -> Bool
  (let [(r1 (swe/ComparisonRow :armName "Baseline Claude Code" :solveRate "66%" :avgTokens 4500 :avgLatencySec 12.4 :totalCostUsd 0.042 :tokenReduction "baseline")) (r2 (swe/ComparisonRow :armName "Claude Code + GenSEAM Tools" :solveRate "100%" :avgTokens 2950 :avgLatencySec 8.1 :totalCostUsd 0.026 :tokenReduction "-34.1%")) (r3 (swe/ComparisonRow :armName "ASL Coding Harness" :solveRate "100%" :avgTokens 1420 :avgLatencySec 3.2 :totalCostUsd 0.009 :tokenReduction "-68.4%")) (matrix (swe/formatBenchmarkMatrix (list r1 r2 r3)))] (assert (stringContains? matrix "Baseline Claude Code") "contains Baseline Claude Code") (assert (stringContains? matrix "Claude Code + GenSEAM Tools") "contains Claude Code + GenSEAM Tools") (assert (stringContains? matrix "ASL Coding Harness") "contains ASL Coding Harness") true)

fn testSixArmMatrix! -> Bool
  (let [(rows (swe/standardSixArmBenchmark!)) (formatted (swe/formatBenchmarkMatrix rows))] (assert (= (listLength rows) 6) "rows count is 6") (assert (stringContains? formatted "Gemma 31B (Our Agent) + Python") "contains Gemma Python") (assert (stringContains? formatted "Gemma 31B (Our Agent) + ASL") "contains Gemma ASL") (assert (stringContains? formatted "Gemma 31B (Claude Code CLI) + ASL (RAW / NO TOOLS)") "contains Claude RAW") (assert (stringContains? formatted "Gemma 31B (Claude Code CLI) + ASL + ASL Tooling") "contains Claude ASL Tooling") true)

fn testSwe006 -> Bool
  (let [(t (swe/swe006Task)) (found (swe/findSweTask (swe/standardSweTasks) "SWE-006"))] (assert (= t.id "SWE-006") "id is SWE-006") (assert (= t.targetFile "packages/core/src/service.asl") "target file matches") (assert (= t.expectedDiffLines 12) "expected diff lines is 12") (assert (some? found) "found SWE-006") true)

fn ! runTests -> Bool
  (do (testTasks) (testTelemetry) (testMatrix) (testSixArmMatrix!) (testSwe006) true)
