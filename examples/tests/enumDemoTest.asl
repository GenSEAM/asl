(module asl/examples/tests/enumDemoTest
  :x [runTests]
  :i [(asl/examples/enumDemo :a e)])

fn runTests -> Bool
  (do
    (assert (= (e/area (e/circle 2)) 12) "circle area")
    (assert (= (e/area (e/rect 2 3)) 6) "rect area")
    true)
