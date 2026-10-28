(module asl-gates/tests/polarityAssertionCountTest :x [testStringLiteralAssertionIgnored testMultipleAssertionsCountedCorrectly testDualPolarityRefutations runTests] :i [(asl-gates/polarity :a pol)])

fn testStringLiteralAssertionIgnored -> Bool
  (let [(codeWithRefuteInStr "(let [(x \"(refute false)\")] true)") (codeWithAssertInStr "(let [(x \"(assert (= a 1))\")] true)") (negCount (pol/countNegativeAssertions codeWithRefuteInStr)) (posCount (pol/countPositiveAssertions codeWithAssertInStr))] (assert (= negCount 0) "String literal containing (refute must not count as negative assertion") (assert (= posCount 0) "String literal containing (assert must not count as positive assertion") true)

fn testMultipleAssertionsCountedCorrectly -> Bool
  (let [(multiNeg "(do (refute a) (refute b))") (multiPos "(do (assert (= a 1)) (assert (= b 2)))") (negCount (pol/countNegativeAssertions multiNeg)) (posCount (pol/countPositiveAssertions multiPos))] (assert (= negCount 2) "Multiple refute invocations must count each occurrence") (assert (= posCount 2) "Multiple assert invocations must count each occurrence") true)

fn testDualPolarityRefutations -> Bool
  (let [(strRefute "(let [(x \"(refute false)\")] true)") (strAssert "(let [(x \"(assert (= 1 1))\")] true)")] (refute (> (pol/countNegativeAssertions strRefute) 0) "Refute that string literal qualifies as negative assertion") (refute (> (pol/countPositiveAssertions strAssert) 0) "Refute that string literal qualifies as positive assertion") (refute (= (pol/countNegativeAssertions "(do (refute a) (refute b))") 1) "Refute that two refutes fold into one") (refute (= (pol/countPositiveAssertions "(do (assert (= a 1)) (assert (= b 2)))") 1) "Refute that two asserts fold into one") true)

fn runTests -> Bool
  (do (assert (testStringLiteralAssertionIgnored) "testStringLiteralAssertionIgnored must pass") (assert (testMultipleAssertionsCountedCorrectly) "testMultipleAssertionsCountedCorrectly must pass") (assert (testDualPolarityRefutations) "testDualPolarityRefutations must pass") true)
