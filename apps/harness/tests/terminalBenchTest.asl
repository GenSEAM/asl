(module aslHarness/tests/terminalBenchTest :x [testTerminalTaskCount testCategoryDistribution testFullTerminalTaskCount testFullCategoryDistribution testSuiteEvaluation! testReportFormatting! runTests] :i [(terminalBench :a tb)])

fn testTerminalTaskCount -> Bool
  (let [(tasks (tb/canonicalAstraHardTasks))] (assert (= (listLength tasks) 60) "challenge task count is 60") (assert (not (listEmpty? tasks)) "tasks not empty") true)

fn testCategoryDistribution -> Bool
  (let [(tasks (tb/canonicalAstraHardTasks)) (c1 (tb/filterTerminalCategory tasks "subshell-isolation")) (c2 (tb/filterTerminalCategory tasks "cross-compile")) (c3 (tb/filterTerminalCategory tasks "context-resilience")) (c4 (tb/filterTerminalCategory tasks "ast-refactor")) (c5 (tb/filterTerminalCategory tasks "env-bootstrap"))] (assert (= (listLength c1) 12) "c1 count is 12") (assert (= (listLength c2) 12) "c2 count is 12") (assert (= (listLength c3) 12) "c3 count is 12") (assert (= (listLength c4) 12) "c4 count is 12") (assert (= (listLength c5) 12) "c5 count is 12") true)

fn testFullTerminalTaskCount -> Bool
  (let [(tasks (tb/canonicalFullSuiteTasks))] (assert (= (listLength tasks) 150) "full task count is 150") (assert (not (listEmpty? tasks)) "tasks not empty") true)

fn testFullCategoryDistribution -> Bool
  (let [(tasks (tb/canonicalFullSuiteTasks)) (c1 (tb/filterTerminalCategory tasks "subshell-isolation")) (c2 (tb/filterTerminalCategory tasks "cross-compile")) (c3 (tb/filterTerminalCategory tasks "context-resilience")) (c4 (tb/filterTerminalCategory tasks "ast-refactor")) (c5 (tb/filterTerminalCategory tasks "env-bootstrap")) (c6 (tb/filterTerminalCategory tasks "stream-pipeline")) (c7 (tb/filterTerminalCategory tasks "system-net")) (c8 (tb/filterTerminalCategory tasks "git-vcs")) (c9 (tb/filterTerminalCategory tasks "build-packaging")) (c10 (tb/filterTerminalCategory tasks "sec-permissions")) (c11 (tb/filterTerminalCategory tasks "proc-analytics"))] (assert (= (listLength c1) 12) "full c1 count is 12") (assert (= (listLength c2) 12) "full c2 count is 12") (assert (= (listLength c3) 12) "full c3 count is 12") (assert (= (listLength c4) 12) "full c4 count is 12") (assert (= (listLength c5) 12) "full c5 count is 12") (assert (= (listLength c6) 15) "full c6 count is 15") (assert (= (listLength c7) 15) "full c7 count is 15") (assert (= (listLength c8) 15) "full c8 count is 15") (assert (= (listLength c9) 15) "full c9 count is 15") (assert (= (listLength c10) 15) "full c10 count is 15") (assert (= (listLength c11) 15) "full c11 count is 15") true)

fn testSuiteEvaluation! -> Bool
  (let [(tasks (tb/canonicalAstraHardTasks)) (rep (tb/evaluateTerminalSuite! tasks))] (assert (= rep.totalTasks 60) "total tasks is 60") (assert (= rep.passedCount 0) "passed count is 0 in sandbox") (assert (= rep.failedCount 60) "failed count is 60 in sandbox") (assert (> rep.tokenSavingsPct 70.0) "token savings > 70") true)

fn testReportFormatting! -> Bool
  (let [(tasks (tb/canonicalAstraHardTasks)) (rep (tb/evaluateTerminalSuite! tasks)) (formatted (tb/formatTerminalReport rep))] (assert (stringContains? formatted "TerminalBench-4-Astra-Hard-60") "contains suite name") (assert (stringContains? formatted ":total 60") "contains total 60") (assert (stringContains? formatted ":pass-rate-pct 0") "contains pass rate 0") true)

fn ! runTests -> Bool
  (do (testTerminalTaskCount) (testCategoryDistribution) (testFullTerminalTaskCount) (testFullCategoryDistribution) (testSuiteEvaluation!) (testReportFormatting!) true)
