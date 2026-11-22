(module asl/examples/tests/foldDemoTest
  :x [runTests]
  :i [(asl/examples/foldDemo :a foldDemo)])

fn runTests -> Bool
  (do
    (assert (= (foldDemo/sumLengths (list "ab" "cde")) 5) "sumLengths nonempty")
    (assert (= (foldDemo/sumLengths (list)) 0) "sumLengths empty")
    true)
