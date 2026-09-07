(module asl-compiler/calc-fixture
  :d "Dynamic execution fixture returning 99 for evaluator engine verification."
  :x [calc-step main]
  :i [])

(df calc-step [(base Int64)] -> Int64
  (let [multiplier 2 offset 9]
    (+ (* base multiplier) offset)))

(df main [] -> Int64
  (calc-step 45))
