(module asl-target-wat/tests/fixtures/arithmetic
  :d "Localized arithmetic test fixture for WebAssembly Text target code emission."
  :x [add sub mul arithmeticOp]
  :i [])

(df add [(a I64) (b I64)] -> I64
  :d "Adds two 64-bit integers."
  (+ a b))

(df sub [(a I64) (b I64)] -> I64
  :d "Subtracts two 64-bit integers."
  (- a b))

(df mul [(a I64) (b I64)] -> I64
  :d "Multiplies two 64-bit integers."
  (* a b))

(df arithmeticOp [(x I64) (y I64) (z I64)] -> I64
  :d "Performs compound arithmetic expression with add, sub, and mul."
  (* (+ x y) (- y z)))
