(module aslAgent/tests/revertTimeoutFloorTest
  :x [runTests]
  :i [(aslAgent/gateIntegrity :a gi)])

fn runTests -> Bool
  (do
    (assert (= (gi/revertTimeout 300) 900) "a 300 s gate timeout gives a revert run 900 s for the rebuild")
    (assert (= (gi/revertTimeout 1800) 1800) "a longer gate timeout is kept")
    (assert (= (gi/revertTimeout 1) 1) "a test-sized timeout under 60 s is kept as given")
    true)
