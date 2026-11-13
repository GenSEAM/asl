(module testPinFixture/entry
  :x [main]
  :i [(asl/packages/asl-cli/tests/fixtures/testPin/used :a u) (asl/packages/asl-cli/tests/fixtures/testPin/cutOnly :a c) (asl/packages/asl-cli/tests/fixtures/testPin/shape :a sh)])

; (:m :ref PERF-CLI-REBUILD :do "a verb dispatcher shaped like native.asl: main reaches test! (a gate) which calls into used; run! is cut and is the only caller of cutOnly; leak! is reached and is not a gate, so a call from it to a cut name makes the walk an error")
fn ! test! p: sh/Point -> Int64
  (u/helper p.x)

fn ! run! n: Int64 -> Int64
  (c/only n)

fn ! dispatch! verb: String n: Int64 -> Int64
  (if (= verb "run") (run! n) (test! (sh/Point :x n)))

fn ! leak! n: Int64 -> Int64
  (run! n)

fn ! main args: (List String) -> (Result Int64 String)
  (ok (dispatch! (optionOr (listHead args) "test") 1))
