(module asl/examples/tests/processDemoTest
  :x [runTests]
  :i [(asl/examples/processDemo :a p)])

fn ! runTests -> Bool
  (assert (= (p/echoOut "hi") "hi") "echoOut hi")
  true
