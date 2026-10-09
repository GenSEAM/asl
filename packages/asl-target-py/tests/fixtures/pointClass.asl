(module asl-target-py/tests/fixtures/pointClass
  :x [Point]
  :i [])

(dfs Point
  (:f x I64)
  (:f y I64 "y coordinate"))
