(module servedFixture/failingProbe :x [runTests] :i [])

fn runTests -> Bool
  (do (assert (= (stringLength "two") 2) "two has two letters")
      true)
