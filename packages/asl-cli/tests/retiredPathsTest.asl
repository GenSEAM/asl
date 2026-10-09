(module asl-cli/tests/retiredPathsTest
  :x [testRetiredPathsAbsent! runTests]
  :i [])

fn testRetiredPathsAbsent! -> Bool
  (do
    (assert (not (fileExists? "bin/lens")) "bin/lens must be retired and deleted")
    (refute (fileExists? "bin/consilium") "bin/consilium must be retired and deleted")
    (refute (fileExists? "bin/agent") "bin/agent must be retired and deleted")
    (refute (fileExists? "bin/asl-full") "bin/asl-full must be retired and deleted")
    true)

fn ! runTests -> Bool
  (testRetiredPathsAbsent!)
