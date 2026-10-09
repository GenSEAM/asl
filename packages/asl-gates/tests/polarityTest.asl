(module asl-gates/tests/polarityTest :x [testIsTestSymbolIdentification testNegativeAssertionDetection testAssertionCounting testAuditTestPolarityStrict testCoverageSummaryCalculation runTests] :i [(polarity :a p)])

fn testIsTestSymbolIdentification -> Unit
  (let [(t1 "test-tokenizer") (t2 "test_parser") (t3 "compiler-test") (t4 "TestPolaritySuite") (non1 "run-tests") (non2 "test-runner") (non3 "helper-function")] (assert (p/isTestSymbol? t1)) (assert (p/isTestSymbol? t2)) (assert (p/isTestSymbol? t3)) (assert (p/isTestSymbol? t4)) (refute (p/isTestSymbol? non1)) (refute (p/isTestSymbol? non2)) (refute (p/isTestSymbol? non3)))

fn testNegativeAssertionDetection -> Unit
  (let [(neg1 "(refute (= x 10))") (neg2 "(assert-reject (run-op))") (neg3 "(assert (not (valid? item)))") (neg4 "(assert-nil result)") (pos1 "(assert (= x 10))") (pos2 "(let [(y 20)])")] (assert (p/isNegativeAssertion? neg1)) (assert (p/isNegativeAssertion? neg2)) (assert (p/isNegativeAssertion? neg3)) (assert (p/isNegativeAssertion? neg4)) (refute (p/isNegativeAssertion? pos1)) (refute (p/isNegativeAssertion? pos2)))

fn testAssertionCounting -> Unit
  (let [(body1 "(assert (= a 1)) (assert (> b 2)) (refute (= c 3))") (posC (p/countPositiveAssertions body1)) (negC (p/countNegativeAssertions body1)) (strLiteralBody "(let [(x \"(refute false)\") (y \"(assert (= 1 1))\")] true)") (multiBody "(do (refute a) (refute b) (assert (= 1 1)) (assert (= 2 2)))")] (assert (= posC 2)) (assert (= negC 1)) (refute (= posC 0)) (refute (= negC 0)) (assert (= (p/countNegativeAssertions strLiteralBody) 0)) (assert (= (p/countPositiveAssertions strLiteralBody) 0)) (assert (= (p/countNegativeAssertions multiBody) 2)) (assert (= (p/countPositiveAssertions multiBody) 2)) (refute (> (p/countNegativeAssertions strLiteralBody) 0)) (refute (> (p/countPositiveAssertions strLiteralBody) 0)))

fn testAuditTestPolarityStrict -> Unit
  (let [(dualBody "(assert (= x 1)) (refute (= x 2))") (posOnlyBody "(assert (= x 1)) (assert (> x 0))") (resDual (p/auditTestPolarity "test-dual" dualBody true 2)) (resPos (p/auditTestPolarity "test-pos" posOnlyBody true 2)) (resLenient (p/auditTestPolarity "test-lenient" posOnlyBody false 2))] (assert resDual.qualified) (assert resLenient.qualified) (refute resPos.qualified) (assert (= resDual.posCount 1)) (assert (= resDual.negCount 1)))

fn testCoverageSummaryCalculation -> Unit
  (let [(dualBody "(assert (= x 1)) (refute (= x 2))") (posOnlyBody "(assert (= x 1)) (assert (> x 0))") (r1 (p/auditTestPolarity "test1" dualBody true 2)) (r2 (p/auditTestPolarity "test2" dualBody true 2)) (r3 (p/auditTestPolarity "test3" posOnlyBody true 2)) (sumPassing (p/summarizeCoverage (list r1 r2) 80)) (sumFailing (p/summarizeCoverage (list r1 r2 r3) 80))] (assert (= sumPassing.totalTests 2)) (assert (= sumPassing.qualifiedTests 2)) (assert (= sumPassing.coveragePct 100)) (assert sumPassing.passed) (assert (= sumFailing.totalTests 3)) (assert (= sumFailing.qualifiedTests 2)) (assert (= sumFailing.coveragePct 66)) (refute sumFailing.passed))

fn runTests -> Bool
  (do (testIsTestSymbolIdentification) (testNegativeAssertionDetection) (testAssertionCounting) (testAuditTestPolarityStrict) (testCoverageSummaryCalculation) true)
