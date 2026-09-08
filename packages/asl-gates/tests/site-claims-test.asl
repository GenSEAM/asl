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
  :d "Verifies ungrounded claims are rejected."
  (let [(registry (sc/standard-claims))]
    (assert (not (sc/is-known-metric "99.999% fake" registry)) "fake claim rejected")
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
  :d "Verifies standard claims matrix is fully grounded."
  (do
    (assert (sc/verify-claims-grounding) "claims grounded")
    true))

(df run-tests [] -> Bool
  :d "Runs all site claims tests."
  (do
    (assert (test-known-claims) "test-known-claims must pass")
    (assert (test-unknown-claim) "test-unknown-claim must pass")
    (assert (test-claims-audit) "test-claims-audit must pass")
    (assert (test-full-grounding) "test-full-grounding must pass")
    true))
