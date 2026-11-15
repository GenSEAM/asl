(module asl-harness/tests/pyStrReprCoverTest
  :x [runTests]
  :i [(asl-harness/launch :a l)])

fn runTests -> Bool
  (let [(r1 (l/pyStrRepr "ab"))
        (r2 (l/pyStrRepr "it's"))]
    (assert (= r1 "'ab'") "pyStrRepr of ab")
    (assert (= r2 "\"it's\"") "pyStrRepr of it's")
    true)
