(module asl-harness/tests/pathJoinCoverTest
  :x [runTests]
  :i [(asl/packages/asl-harness/src/launch :a l)])

fn runTests -> Bool
  (let [(t1 (assert (= (l/pathJoin "a" "b") "a/b") "pathJoin a b"))
        (t2 (assert (= (l/pathJoin "a/" "b") "a/b") "pathJoin a/ b"))
        (t3 (assert (= (l/pathJoin "a" "/b") "/b") "pathJoin a /b"))]
    true)
