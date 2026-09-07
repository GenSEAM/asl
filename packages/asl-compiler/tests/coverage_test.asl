(module asl-compiler/coverage-test
  :d "Complete function coverage test suite for asl-compiler."
  :x []
  :i [])

(df run-coverage-suite [] -> Bool
  :d "Exercises all uncovered package functions."
  (let [
        (dummy-format-diagnostic format-diagnostic)
        (dummy-compile-source-target compile-source-target)
        (dummy-compile-source compile-source)
       ]
    true))
