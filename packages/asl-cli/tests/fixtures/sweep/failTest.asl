(module sweepFixture/failTest :x [runTests] :i [])

fn runTests -> Bool
  (do (assert (= (stringLength "four") 4) "first holds")
      (assert (= (stringLength "four") 5) "four letters make five")
      true)
