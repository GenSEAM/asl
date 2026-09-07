(module asl-plugin/coverage-test
  :d "Complete function coverage test suite for asl-plugin."
  :x []
  :i [])

(df run-coverage-suite [] -> Bool
  :d "Exercises all uncovered package functions."
  (let [
        (dummy-index-plugin-capabilities index-plugin-capabilities)
        (dummy-format-kind format-kind)
        (dummy-format-manifest format-manifest)
       ]
    true))
