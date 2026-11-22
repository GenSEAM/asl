(module aslExamples/tests/optionDemoTest
  :x [runTests]
  :i [(aslExamples/optionDemo :a optionDemo)])

fn runTests -> Bool
  (do
    (assert (= (optionDemo/firstOr (list "a" "b") "z") "a") "firstOr some")
    (assert (= (optionDemo/firstOr (list) "z") "z") "firstOr none")
    true)
