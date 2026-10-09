(module asl-target-wat/tests/fixtures/arithmetic :x [add sub mul arithmeticOp] :i [])

fn add a: I64 b: I64 -> I64
  (+ a b)

fn sub a: I64 b: I64 -> I64
  (- a b)

fn mul a: I64 b: I64 -> I64
  (* a b)

fn arithmeticOp x: I64 y: I64 z: I64 -> I64
  (* (+ x y) (- y z))
