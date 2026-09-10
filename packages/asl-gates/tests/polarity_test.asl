(module asl-gates/tests/polarity-test
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
    (assert (p/is-test-symbol? t1))
    (assert (p/is-test-symbol? t2))
    (assert (p/is-test-symbol? t3))
    (assert (p/is-test-symbol? t4))
    (refute (p/is-test-symbol? non1))
    (refute (p/is-test-symbol? non2))
    (refute (p/is-test-symbol? non3))))

(df TestNegativeAssertionDetection [] -> Unit
  (let [(neg1 "(refute (= x 10))")
        (neg2 "(assert-reject (run-op))")
        (neg3 "(assert (not (valid? item)))")
        (neg4 "(assert-nil result)")
        (pos1 "(assert (= x 10))")
        (pos2 "(let [(y 20)])")]
    (assert (p/is-negative-assertion? neg1))
    (assert (p/is-negative-assertion? neg2))
    (assert (p/is-negative-assertion? neg3))
    (assert (p/is-negative-assertion? neg4))
    (refute (p/is-negative-assertion? pos1))
    (refute (p/is-negative-assertion? pos2))))

(df TestAssertionCounting [] -> Unit
  (let [(body1 "(assert (= a 1)) (assert (> b 2)) (refute (= c 3))")
        (pos-c (p/count-positive-assertions body1))
        (neg-c (p/count-negative-assertions body1))]
    (assert (= pos-c 2))
    (assert (= neg-c 1))
    (refute (= pos-c 0))
    (refute (= neg-c 0))))

(df TestAuditTestPolarityStrict [] -> Unit
  (let [(dual-body "(assert (= x 1)) (refute (= x 2))")
        (pos-only-body "(assert (= x 1)) (assert (> x 0))")
        (res-dual (p/audit-test-polarity "test-dual" dual-body true 2))
        (res-pos (p/audit-test-polarity "test-pos" pos-only-body true 2))
        (res-lenient (p/audit-test-polarity "test-lenient" pos-only-body false 2))]
    (assert (.-qualified res-dual))
    (assert (.-qualified res-lenient))
    (refute (.-qualified res-pos))
    (assert (= (.-pos-count res-dual) 1))
    (assert (= (.-neg-count res-dual) 1))))

(df TestCoverageSummaryCalculation [] -> Unit
  (let [(dual-body "(assert (= x 1)) (refute (= x 2))")
        (pos-only-body "(assert (= x 1)) (assert (> x 0))")
        (r1 (p/audit-test-polarity "test1" dual-body true 2))
        (r2 (p/audit-test-polarity "test2" dual-body true 2))
        (r3 (p/audit-test-polarity "test3" pos-only-body true 2))
        (sum-passing (p/summarize-coverage (list r1 r2) 80))
        (sum-failing (p/summarize-coverage (list r1 r2 r3) 80))]
    (assert (= (.-total-tests sum-passing) 2))
    (assert (= (.-qualified-tests sum-passing) 2))
    (assert (= (.-coverage-pct sum-passing) 100))
    (assert (.-passed sum-passing))
    (assert (= (.-total-tests sum-failing) 3))
    (assert (= (.-qualified-tests sum-failing) 2))
    (assert (= (.-coverage-pct sum-failing) 66))
    (refute (.-passed sum-failing))))
