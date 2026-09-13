(module asl-compiler/calcFixture
  :d "Dynamic execution fixture returning 99 for evaluator engine verification."
  :x [calcStep main runTests]
  :i [])

(df calcStep [(base Int64)] -> Int64
  (let [multiplier 2 offset 9]
    (+ (* base multiplier) offset)))

(df main [] -> Int64
  (calcStep 45))

(df runTests [] -> Bool
  :d "Verifies dynamic calc fixture calculations."
  (do
    (assert (= (calcStep 45) 99) "calc-step 45 is 99")
    (assert (= (main) 99) "main is 99")
    true))
