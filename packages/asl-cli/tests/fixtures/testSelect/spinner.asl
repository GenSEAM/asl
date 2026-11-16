(module testSelect/spinner :x [runTests] :i [])

; (:m :ref TEST-RUNNER-SELECT :do "spins for 60 s of wall time and then passes, so a small wall cap kills it and without one it ends on its own")
fn spinUntil deadline: Int64 -> Bool
  (if (> (monotonicNs) deadline) true (spinUntil deadline))

fn testSpin -> Bool
  (do (assert (spinUntil (+ (monotonicNs) 60000000000)) "the spin ends")
      true)

fn runTests -> Bool
  (testSpin)
