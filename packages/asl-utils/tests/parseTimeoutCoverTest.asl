(module asl-utils/tests/parseTimeoutCoverTest
  :x [runTests]
  :i [(asl-utils/timeout :a t)])

fn testDecimal -> Bool
  (do (assert (= (t/parseTimeout "1.5") (some 1500)) (str "1.5 is 1500 ms: " (t/parseTimeout "1.5")))
      true)

fn testNegative -> Bool
  (do (assert (= (t/parseTimeout "-1") (none)) (str "-1 is none: " (t/parseTimeout "-1")))
      true)

fn testMalformed -> Bool
  (do (assert (= (t/parseTimeout "abc") (none)) (str "abc is none: " (t/parseTimeout "abc")))
      true)

fn ! runTests -> Bool
  (do (assert (testDecimal) "a decimal SECS is converted to milliseconds")
      (assert (testNegative) "a negative SECS is rejected")
      (assert (testMalformed) "a malformed SECS is rejected")
      true)
