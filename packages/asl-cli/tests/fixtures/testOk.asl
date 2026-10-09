(module test/testOk :x [runTests] :i [])

fn runTests -> Bool
  (let [(_ (assert (= (stringLength "marker") 6) "marker passed"))]
    true)
