(module asl-gates/tests/fixtures/hostlessProbe/alwaysPassTest
  :x [runTests]
  :i [])

fn ! runTests -> Bool
  (do (assert true "the hostless probe always passes") true)
