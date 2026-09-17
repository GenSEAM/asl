(module asl-codegen/tests/fixtures/c99/sampleC99
  :d "Localized C99 sample fixture for C99 header and source code emission."
  :x [add multiply sampleOp]
  :i [])

(df add [(a I64) (b I64)] -> I64
  :d "Adds two 64-bit integers."
  (+ a b))

(df multiply [(x I64) (y I64)] -> I64
  :d "Multiplies two 64-bit integers."
  (* x y))

(df sampleOp [(p I64) (q I64) (r I64)] -> I64
  :d "Computes composite arithmetic operation for C99 translation."
  (+ (* p q) r))
