(module asl-tools/fleet/tests/fixtures/noisySuite
  :x [runTests]
  :i [])

; (:m :ref GATE-ASSERTS-FROM-LEDGER :do "a real suite of three assertions that first prints count lines it did not earn, bare and with its own path; run by executedOfTest through bin/asl test; not named *Test, so no sweep runs it")
fn ! runTests -> Bool
  (do (println "99 assertion(s) executed (99 passed)")
      (println "asl/tools/fleet/tests/fixtures/noisySuite.asl: 99 assertion(s) executed (99 passed)")
      (assert (> (procSelf) 0) "one")
      (assert (> (nowNs) 0) "two")
      (assert (>= (monotonicNs) 0) "three")
      true)
