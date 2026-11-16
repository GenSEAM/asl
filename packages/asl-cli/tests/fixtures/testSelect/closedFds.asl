(module testSelect/closedFds :x [runTests] :i [])

; (:m :ref TEST-RUNNER-SELECT :do "closes its stdout and stderr after one assertion and spins for 60 s, so the runner sees both pipes end while the binary runs on; the spin bounds the run should no wall limit fire")
fn spinUntil deadline: Int64 -> Bool
  (if (> (monotonicNs) deadline) true (spinUntil deadline))

fn ! testClosed -> Bool
  (do (assert (= (stringLength "c") 1) "before closing")
      (fdClose 1)
      (fdClose 2)
      (spinUntil (+ (monotonicNs) 60000000000)))

fn ! runTests -> Bool
  (testClosed)
