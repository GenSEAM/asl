(module asl/grammar/examples/tests/examplesTest
  :x [runTests]
  :i [(asl/grammar/examples/greeting :a g) (asl/grammar/examples/record :a r)])

fn ! runTests -> Bool
  (do
    (assert (= (g/describeShape (g/mkCircle 2)) "circle r=2") "describeShape renders a circle")
    (assert (= (g/describeShape (g/mkSquare 3)) "square side=3") "describeShape renders a square")
    (assert (= (g/greet "world") "Hello, world!") "greet formats a name")
    (assert (= (g/makeGreeting! "world") "Hello, world!") "a fn name! declaration still runs its pure body")
    (assert (= (r/describePoint (r/origin)) "(0,0)") "origin prints at the zero point")
    (assert (= (r/describePoint (r/moveBy (r/origin) 3 4)) "(3,4)") "moveBy returns a copy with both fields moved")
    true)
