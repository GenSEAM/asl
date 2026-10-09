(module asl-codegen/tests/fixtures/c99/sampleC99 :x [add multiply sampleOp] :i [])

fn add a: I64 b: I64 -> I64
  (+ a b)

fn multiply x: I64 y: I64 -> I64
  (* x y)

fn sampleOp p: I64 q: I64 r: I64 -> I64
  (+ (* p q) r)
