(module asl/tools/tests/fixtures/prepareAll/suiteD :x [runTests] :i [(asl/tools/tests/fixtures/prepareAll/helper :a h)])

fn ! runTests -> Bool
  (do (assert (= (h/hval 1) 8) "the shared helper answers") true)
