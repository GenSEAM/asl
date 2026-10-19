(module asl-gates/tests/fixtures/hostlessProbe/alwaysPassTest
  :x [runTests]
  :i [])

fn ! runTests -> Bool
  (do (assert (>= (monotonicNs) 0) "the hostless probe always passes") true)
