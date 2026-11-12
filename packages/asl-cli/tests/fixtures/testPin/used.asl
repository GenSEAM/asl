(module testPinFixture/used :x [helper] :i [(asl/packages/asl-cli/tests/fixtures/testPin/table :a tb)])

fn helper n: Int64 -> Int64
  (+ n (tb/dispatchByName "double" n))
