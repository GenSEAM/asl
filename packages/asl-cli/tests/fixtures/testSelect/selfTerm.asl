(module testSelect/selfTerm :x [runTests] :i [])

; (:m :ref TEST-RUNNER-SELECT :do "sends itself SIGTERM after one assertion, a signal no runner limit sends; the spin after it bounds the run should the signal not land")
fn spinUntil deadline: Int64 -> Bool
  (if (> (monotonicNs) deadline) true (spinUntil deadline))

fn ! testSignalled -> Bool
  (do (assert (= (stringLength "t") 1) "before the signal")
      (procKill (procSelf) "SIGTERM")
      (spinUntil (+ (monotonicNs) 10000000000)))

fn ! runTests -> Bool
  (testSignalled)
