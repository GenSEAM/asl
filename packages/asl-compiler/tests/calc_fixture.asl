(module asl-compiler/calc-fixture
  :d "Dynamic execution fixture returning 99 for evaluator engine verification."
  :x [calc-step main run-tests]
  :i [])

(df calc-step [(base Int64)] -> Int64
  (let [multiplier 2 offset 9]
    (+ (* base multiplier) offset)))

(df main [] -> Int64
  (calc-step 45))

(df run-tests [] -> Bool
  :d "Verifies dynamic calc fixture calculations."
  (do
    (assert (= (calc-step 45) 99) "calc-step 45 is 99")
    (assert (= (main) 99) "main is 99")
    true))
