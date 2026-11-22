(module asl/examples/tests/recordDemoTest
  :x [runTests]
  :i [(asl/examples/recordDemo :a r)])

fn runTests -> Bool
  (let [(p (r/Point :x 1 :y 2))
        (q (r/moveRight p 3))]
    (assert (= q.x 4) "moveRight x")
    (assert (= q.y 2) "moveRight keeps y")
    true)
