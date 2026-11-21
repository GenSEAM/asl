(module asl/examples/tests/greetTest
  :x [runTests]
  :i [(asl/examples/greet :a g)])

fn runTests -> Bool
  (do
    (assert (= (g/greet "asl") "hello, asl") "greet")
    true)
