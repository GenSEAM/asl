(module aslHarness/tests/key_mapping_test :x [testKeyMapping runTests] :i [(keyMapping :a km)])

fn testKeyMapping -> Bool
  (do (assert (km/RunTests) "RunTests in key-mapping should pass") (refute (km/auditEmittedAsnKeys "(:record :exit-code 0)") "Rejects kebab-case") true)

fn runTests -> Bool
  (testKeyMapping)

