(module asl-target-py/tests/fixtures/pointClass
  :d "Localized Point schema fixture for Python dataclass target code emission."
  :x [Point]
  :i [])

(dfs Point
  (:f x I64 "x coordinate")
  (:f y I64 "y coordinate"))
