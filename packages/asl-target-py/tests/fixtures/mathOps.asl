(module asl-target-py/tests/fixtures/mathOps :x [add mul compute-distance] :i [])

fn add a: I64 b: I64 -> I64
  (+ a b)

fn mul a: I64 b: I64 -> I64
  (* a b)

fn compute-distance x1: I64 y1: I64 x2: I64 y2: I64 -> I64
  (+ (- x2 x1) (- y2 y1))
