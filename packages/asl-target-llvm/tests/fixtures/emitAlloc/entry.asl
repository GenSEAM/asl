(module emitAllocEntry
  :x [main]
  :i [(asl-json/tests/jsonTest :a suite)])

fn ! main args: (List String) -> (Result Int64 String)
  (if (suite/runTests) (ok 0) (do (eprintln "ERR_TEST_FAILED: runTests returned false, not true") (ok 1)))
