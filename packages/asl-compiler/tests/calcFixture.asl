(module asl-compiler/calcFixture :x [calcStep main runTests] :i [])

fn calcStep base: Int64 -> Int64
  (let [multiplier 2 offset 9] (+ (* base multiplier) offset))

fn main -> Int64
  (calcStep 45)

fn runTests -> Bool
  (do (assert (= (calcStep 45) 99) "calc-step 45 is 99") (assert (= (main) 99) "main is 99") true)
