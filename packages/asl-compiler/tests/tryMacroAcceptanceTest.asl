(module asl-compiler/tests/tryMacroAcceptanceTest
  :x [runTests RunTests testTryExpansion testTryInSourceLowering testDualPolarityRefutations]
  :i [(asl-compiler/tryMacro :a tm)])

fn testTryExpansion -> Bool
  (let [(expanded (tm/expandTryMacro "(parsePayload bytes)"))]
    (assert (stringContains? expanded "(match (parsePayload bytes)") "try lowers to pattern match")
    (refute (not (stringContains? expanded "(match (parsePayload bytes)")) "try lowering refutes missing match")
    (assert (stringContains? expanded "__try_val") "unwraps ok value")
    (assert (stringContains? expanded "__try_err") "propagates err on failure"))
  true

fn testTryInSourceLowering -> Bool
  (let [(code "fn handler sock: I64 -> (Result Str Str) (let [(hdr (try (readHeader sock)))] (ok hdr))")
        (lowered (tm/expandTryInSource code))]
    (assert (stringContains? lowered "(match (readHeader sock)") "source lowers nested try form")
    (refute (stringContains? lowered "(try ") "lowered source contains zero try keywords"))
  true

fn testDualPolarityRefutations -> Bool
  (let [(noTry "fn noop -> Bool true")
        (unchanged (tm/expandTryInSource noTry))]
    (assert (= unchanged noTry) "source without try is completely unchanged")
    (refute (!= unchanged noTry) "source without try refutes modification"))
  true

fn runTests -> Bool
  (do
    (assert (testTryExpansion) "testTryExpansion passed")
    (assert (testTryInSourceLowering) "testTryInSourceLowering passed")
    (assert (testDualPolarityRefutations) "testDualPolarityRefutations passed")
    true)

fn RunTests -> Bool
  (runTests)
