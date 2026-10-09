(module test/testNoDoc :x [runTests] :i [])

fn runTests -> Bool
  (let [(_ (assert (= (stringLength "doc") 3) "clean test without doc"))]
    true)
