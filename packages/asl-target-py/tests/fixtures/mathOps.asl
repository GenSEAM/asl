(module asl-target-py/tests/fixtures/mathOps
  :d "Localized math operations fixture for Python typed function target code emission."
  :x [add mul compute-distance]
  :i [])

(df add [(a I64) (b I64)] -> I64
  :d "Adds two integers."
  (+ a b))

(df mul [(a I64) (b I64)] -> I64
  :d "Multiplies two integers."
  (* a b))

(df compute-distance [(x1 I64) (y1 I64) (x2 I64) (y2 I64)] -> I64
  :d "Computes Manhattan distance between two coordinates."
  (+ (- x2 x1) (- y2 y1)))
