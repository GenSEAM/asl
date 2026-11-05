(module asl-tools/fleet/tests/fixtures/threeAssertsSuite
  :x [runTests]
  :i [])

; (:m :ref GATE-ASSERTS-FROM-LEDGER :do "a real suite that executes exactly three assertions, run by executedOfTest through bin/asl test; not named *Test, so no sweep runs it")
fn ! runTests -> Bool
  (do (assert (> (procSelf) 0) "one")
      (assert (> (nowNs) 0) "two")
      (assert (>= (monotonicNs) 0) "three")
      true)
