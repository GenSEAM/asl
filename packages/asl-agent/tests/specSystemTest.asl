(module aslAgent/tests/specSystemTest
  :x [runTests]
  :i [(aslAgent/context :a ctx)])

fn runTests -> Bool
  (let [s (ctx/specCheckSystem)]
    (do
      (assert (stringContains? s "Do not fail a change for missing process evidence") "the grader is told process evidence is the harness's job")
      (assert (stringContains? s "commit message") "the commit line is named as a harness check")
      (assert (stringContains? s "(:verdict :met true)") "the reply shape is kept")
      true))
