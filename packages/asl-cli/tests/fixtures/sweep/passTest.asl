(module sweepFixture/passTest :x [runTests] :i [])

fn runTests -> Bool
  (do (assert (= (stringLength "four") 4) "four letters")
      (refute (= (stringLength "one") 2) "three letters")
      true)
