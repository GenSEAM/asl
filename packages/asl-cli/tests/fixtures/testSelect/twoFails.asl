(module testSelect/twoFails :x [runTests] :i [])

fn testEarly -> Bool
  (do (assert (= (stringLength "ab") 3) "early breaks on purpose")
      (assert (= (stringLength "ab") 2) "early holds after")
      true)

fn testLate -> Bool
  (do (assert (= (stringLength "xy") 2) "late opens")
      (assert (= (stringLength "xy") 3) "late breaks on purpose")
      true)

fn testRefuted -> Bool
  (do (refute (= (stringLength "z") 1) "the refutation breaks on purpose")
      true)

fn runTests -> Bool
  (do (testEarly) (testLate) (testRefuted))
