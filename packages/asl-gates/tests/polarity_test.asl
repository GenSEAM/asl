(module asl-gates/tests/polarityTest
  :d "Pure AgentScript Dual-Polarity Gate 5 Unit Test Suite per D51, D77."
  :i [(polarity :a p)])

(df TestIsTestSymbolIdentification [] -> Unit
  (let [(t1 "test-tokenizer")
        (t2 "test_parser")
        (t3 "compiler-test")
        (t4 "TestPolaritySuite")
        (non1 "run-tests")
        (non2 "test-runner")
        (non3 "helper-function")]
    (assert (p/isTestSymbol? t1))
    (assert (p/isTestSymbol? t2))
    (assert (p/isTestSymbol? t3))
    (assert (p/isTestSymbol? t4))
    (refute (p/isTestSymbol? non1))
    (refute (p/isTestSymbol? non2))
    (refute (p/isTestSymbol? non3))))

(df TestNegativeAssertionDetection [] -> Unit
  (let [(neg1 "(refute (= x 10))")
        (neg2 "(assert-reject (run-op))")
        (neg3 "(assert (not (valid? item)))")
        (neg4 "(assert-nil result)")
        (pos1 "(assert (= x 10))")
        (pos2 "(let [(y 20)])")]
    (assert (p/isNegativeAssertion? neg1))
    (assert (p/isNegativeAssertion? neg2))
    (assert (p/isNegativeAssertion? neg3))
    (assert (p/isNegativeAssertion? neg4))
    (refute (p/isNegativeAssertion? pos1))
    (refute (p/isNegativeAssertion? pos2))))

(df TestAssertionCounting [] -> Unit
  (let [(body1 "(assert (= a 1)) (assert (> b 2)) (refute (= c 3))")
        (posC (p/countPositiveAssertions body1))
        (negC (p/countNegativeAssertions body1))]
    (assert (= posC 2))
    (assert (= negC 1))
    (refute (= posC 0))
    (refute (= negC 0))))

(df TestAuditTestPolarityStrict [] -> Unit
  (let [(dualBody "(assert (= x 1)) (refute (= x 2))")
        (posOnlyBody "(assert (= x 1)) (assert (> x 0))")
        (resDual (p/auditTestPolarity "test-dual" dualBody true 2))
        (resPos (p/auditTestPolarity "test-pos" posOnlyBody true 2))
        (resLenient (p/auditTestPolarity "test-lenient" posOnlyBody false 2))]
    (assert (.-qualified resDual))
    (assert (.-qualified resLenient))
    (refute (.-qualified resPos))
    (assert (= (.-posCount resDual) 1))
    (assert (= (.-negCount resDual) 1))))

(df TestCoverageSummaryCalculation [] -> Unit
  (let [(dualBody "(assert (= x 1)) (refute (= x 2))")
        (posOnlyBody "(assert (= x 1)) (assert (> x 0))")
        (r1 (p/auditTestPolarity "test1" dualBody true 2))
        (r2 (p/auditTestPolarity "test2" dualBody true 2))
        (r3 (p/auditTestPolarity "test3" posOnlyBody true 2))
        (sumPassing (p/summarizeCoverage (list r1 r2) 80))
        (sumFailing (p/summarizeCoverage (list r1 r2 r3) 80))]
    (assert (= (.-totalTests sumPassing) 2))
    (assert (= (.-qualifiedTests sumPassing) 2))
    (assert (= (.-coveragePct sumPassing) 100))
    (assert (.-passed sumPassing))
    (assert (= (.-totalTests sumFailing) 3))
    (assert (= (.-qualifiedTests sumFailing) 2))
    (assert (= (.-coveragePct sumFailing) 66))
    (refute (.-passed sumFailing))))
