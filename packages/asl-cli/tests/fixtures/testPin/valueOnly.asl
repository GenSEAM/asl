(module testPinFixture/valueOnly :x [viaValue] :i [(asl/packages/asl-cli/tests/fixtures/testPin/deep :a dp)])

fn viaValue n: Int64 -> Int64
  (dp/deep n)
