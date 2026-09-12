(module asl-bench/tasks/flaky-fixture
  :d "Deliberately planted unstable fixture for flakiness and stability detection verification."
  :x [SimulateFlakyRun IsOutcomePass? RunTests]
  :i [])

(df IsOutcomePass? [(run-index I64)] -> Bool
  :d "Simulates fluctuating test outcome across runs"
  (= (mod run-index 2) 0))

(df SimulateFlakyRun [(run-index I64)] -> Str
  :d "Returns pass or fail status based on run index"
  (if (IsOutcomePass? run-index)
      "pass"
      "fail"))

(df RunTests [] -> Bool
  :d "Self-test verifying alternating flaky behavior"
  (do
    (assert (= (SimulateFlakyRun 0) "pass") "Run 0 passes")
    (assert (= (SimulateFlakyRun 1) "fail") "Run 1 fails")
    (assert (= (SimulateFlakyRun 2) "pass") "Run 2 passes")
    true))
