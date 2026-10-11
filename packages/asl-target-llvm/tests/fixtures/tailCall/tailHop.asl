(module asl-target-llvm/tests/fixtures/tailCall/tailHop
  :x [hop]
  :i [])

fn hop n: Int64 acc: (List Int64) k: (fn [Int64 (List Int64)] -> (List Int64)) -> (List Int64)
  (k n acc)
