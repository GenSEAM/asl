(module asl-runtime/tests/floatCoverTest
  :x [runTests]
  :i [(asl-runtime/float :a float)])

fn testRtParseF64Normal -> Bool
  (match (float/rtParseF64 "1.5") ((some v) (= v 1.5)) ((none) false))

fn testRtParseF64Empty -> Bool
  (match (float/rtParseF64 "") ((some v) false) ((none) true))

fn testRtParseF64Zero -> Bool
  (match (float/rtParseF64 "0") ((some v) (= v 0.0)) ((none) false))

fn testRtParseF64Max -> Bool
  (match (float/rtParseF64 "1.7976931348623157e308") ((some v) (= v 1.7976931348623157e308)) ((none) false))

fn testRtParseF64Error -> Bool
  (match (float/rtParseF64 "not-a-float") ((some v) false) ((none) true))

fn testRtParseF64Whitespace -> Bool
  (match (float/rtParseF64 "   ") ((some v) false) ((none) true))

fn ! runTests -> Bool
  (do
    (assert (testRtParseF64Normal) "normal case: 1.5")
    (assert (testRtParseF64Empty) "boundary: empty string")
    (assert (testRtParseF64Zero) "boundary: zero")
    (assert (testRtParseF64Max) "boundary: max double")
    (assert (testRtParseF64Error) "error: unparseable string")
    (assert (testRtParseF64Whitespace) "error: whitespace-only")
    true)
