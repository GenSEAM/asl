(module testSelect/memHog :x [runTests] :i [])

; (:m :ref TEST-RUNNER-SELECT :do "grows a held string to 512 MB in steps, pausing between them so a sampling memory cap sees it, then returns; bounded by size, so without a cap it ends on its own")
fn grow s: String n: Int64 -> String
  (if (or (> (stringLength s) 536870912) (<= n 0))
    s
    (let [(next (str s s))
          (t0 (monotonicNs))
          (_ (spinUntil (+ t0 300000000)))]
      (grow next (- n 1))))

fn spinUntil deadline: Int64 -> Bool
  (if (> (monotonicNs) deadline) true (spinUntil deadline))

fn testGrow -> Bool
  (let [(held (grow (stringRepeat "m" 1048576) 10))]
    (do (assert (> (stringLength held) 1048576) "the string grew")
        true))

fn runTests -> Bool
  (testGrow)
