(module aslBench/tasks/flakyFixture :x [SimulateFlakyRun IsOutcomePass? RunTests] :i [])

fn IsOutcomePass? runIndex: I64 -> Bool
  (= (mod runIndex 2) 0)

fn SimulateFlakyRun runIndex: I64 -> Str
  (if (IsOutcomePass? runIndex) "pass" "fail")

fn RunTests -> Bool
  (do (assert (= (SimulateFlakyRun 0) "pass") "Run 0 passes") (assert (= (SimulateFlakyRun 1) "fail") "Run 1 fails") (assert (= (SimulateFlakyRun 2) "pass") "Run 2 passes") true)
