(module asl-gates/tests/site-claims-test
  :d "Unit tests for pure AgentScript Site Claims Verification Gate."
  :x [test-known-claims test-unknown-claim test-claims-audit test-full-grounding run-tests]
  :i [(site-claims :a sc)])

(df test-known-claims [] -> Bool
  :d "Verifies grounded claims pass lookup."
  (let [(registry (sc/standard-claims))]
    (assert (sc/is-known-metric "57%–65%" registry) "metric 57-65%")
    (assert (sc/is-known-metric "<100ms" registry) "metric <100ms")
    (assert (sc/is-known-metric "24MB" registry) "metric 24MB")
    true))

(df test-unknown-claim [] -> Bool
  :d "Verifies ungrounded claims are rejected and grounded claims pass."
  (let [(registry (sc/standard-claims))]
    (assert (sc/is-known-metric "24MB" registry) "known valid metric claim accepted")
    (assert (sc/is-known-metric "0.038ms" registry) "known sub-millisecond metric claim accepted")
    (assert (not (sc/is-known-metric "99.999% fake" registry)) "fake claim rejected")
    (assert (not (sc/is-known-metric "" registry)) "empty claim string rejected")
    (assert (not (sc/is-known-metric "bogus-throughput" registry)) "unregistered bogus metric rejected")
    (assert (not (.-grounded (sc/audit-claim "ungrounded-speedup" registry))) "audit claim of ungrounded metric must not be grounded")
    true))

(df test-claims-audit [] -> Bool
  :d "Verifies run-claims-audit computes accurate report totals."
  (let [(registry (sc/standard-claims))
        (sample (list "57%–65%" "fake-claim"))
        (report (sc/run-claims-audit sample registry))]
    (assert (= (.-total report) 2) "total 2")
    (assert (= (.-passed report) 1) "passed 1")
    (assert (= (.-failed report) 1) "failed 1")
    (assert (= (.-status report) "FAIL") "status FAIL")
    true))

(df test-full-grounding [] -> Bool
  :d "Verifies standard claims matrix is fully grounded and ungrounded audits fail."
  (let [(registry (sc/standard-claims))
        (good-report (sc/run-claims-audit registry registry))
        (bad-report (sc/run-claims-audit (list "fabricated-speedup" "invalid-metric") registry))]
    (assert (sc/verify-claims-grounding) "claims grounded")
    (assert (= (.-status good-report) "PASS") "canonical claims audit report must pass")
    (assert (= (.-failed good-report) 0) "canonical claims audit must have zero failures")
    (assert (not (= (.-status bad-report) "PASS")) "ungrounded claims audit report must not pass")
    (assert (not (= (.-failed bad-report) 0)) "ungrounded claims audit must have non-zero failure count")
    (assert (not (sc/is-known-metric "fabricated-speedup" registry)) "invalid claim must not be in standard registry")
    true))

(df run-tests [] -> Bool
  :d "Runs all site claims tests."
  (do
    (assert (test-known-claims) "test-known-claims must pass")
    (assert (test-unknown-claim) "test-unknown-claim must pass")
    (assert (test-claims-audit) "test-claims-audit must pass")
    (assert (test-full-grounding) "test-full-grounding must pass")
    true))
