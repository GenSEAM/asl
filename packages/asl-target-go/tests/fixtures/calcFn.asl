(module asl-target-go/tests/fixtures/calcFn
  :d "Localized typed calculation function fixture for Go target code emission."
  :x [calc]
  :i [])

(df calc [(base I64) (multiplier I64) (offset I64)] -> I64
  :d "Calculates scaled value with offset."
  (+ (* base multiplier) offset))
