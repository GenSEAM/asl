(module asl-target-go/tests/fixtures/calcFn :x [calc] :i [])

fn calc base: I64 multiplier: I64 offset: I64 -> I64
  (+ (* base multiplier) offset)
