(module asl-gates/tests/site_claims_test
  :d "Unit tests for pure AgentScript Site Claims Verification Gate under live disk grounding."
  :x [testKnownClaims testUnknownClaim testClaimsAudit testFullGrounding testDiskGroundingVerification runTests]
  :i [(siteClaims :a sc)])

(df testKnownClaims [] -> Bool
  :d "Verifies grounded claims pass lookup."
  (let [(registry (sc/standardClaims))]
    (assert (sc/isKnownMetric "57%–65%" registry) "metric 57-65%")
    (assert (sc/isKnownMetric "<100ms" registry) "metric <100ms")
    (assert (sc/isKnownMetric "24MB" registry) "metric 24MB")
    true))

(df testUnknownClaim [] -> Bool
  :d "Verifies ungrounded claims are rejected and grounded claims pass."
  (let [(registry (sc/standardClaims))]
    (assert (sc/isKnownMetric "24MB" registry) "known valid metric claim accepted")
    (assert (sc/isKnownMetric "0.038ms" registry) "known sub-millisecond metric claim accepted")
    (assert (not (sc/isKnownMetric "99.999% fake" registry)) "fake claim rejected")
    (assert (not (sc/isKnownMetric "" registry)) "empty claim string rejected")
    (assert (not (sc/isKnownMetric "bogus-throughput" registry)) "unregistered bogus metric rejected")
    (assert (not (.-grounded (sc/auditClaim "ungrounded-speedup" registry))) "audit claim of ungrounded metric must not be grounded")
    true))

(df testClaimsAudit [] -> Bool
  :d "Verifies run-claims-audit computes accurate report totals."
  (let [(registry (sc/standardClaims))
        (sample (list "57%–65%" "fake-claim"))
        (report (sc/runClaimsAudit sample registry))]
    (assert (= (.-total report) 2) "total 2")
    (assert (= (.-passed report) 1) "passed 1")
    (assert (= (.-failed report) 1) "failed 1")
    (assert (= (.-status report) "FAIL") "status FAIL")
    true))

(df testFullGrounding [] -> Bool
  :d "Verifies standard claims matrix is fully grounded and ungrounded audits fail."
  (let [(registry (sc/standardClaims))
        (goodReport (sc/runClaimsAudit registry registry))
        (badReport (sc/runClaimsAudit (list "fabricated-speedup" "invalid-metric") registry))]
    (assert (sc/verifyClaimsGrounding) "claims grounded")
    (assert (= (.-status goodReport) "PASS") "canonical claims audit report must pass")
    (assert (= (.-failed goodReport) 0) "canonical claims audit must have zero failures")
    (assert (not (= (.-status badReport) "PASS")) "ungrounded claims audit report must not pass")
    (assert (not (= (.-failed badReport) 0)) "ungrounded claims audit must have non-zero failure count")
    (assert (not (sc/isKnownMetric "fabricated-speedup" registry)) "invalid claim must not be in standard registry")
    true))

(df testDiskGroundingVerification [] -> Bool
  :d "Verifies verify-claims-grounding actively verifies against published_claims.asn on disk."
  (assert (sc/verifyClaimsGrounding) "verify-claims-grounding must return true on valid monorepo published claims")
  true)

(df runTests [] -> Bool
  :d "Runs all site claims tests."
  (do
    (assert (testKnownClaims) "test-known-claims must pass")
    (assert (testUnknownClaim) "test-unknown-claim must pass")
    (assert (testClaimsAudit) "test-claims-audit must pass")
    (assert (testFullGrounding) "test-full-grounding must pass")
    (assert (testDiskGroundingVerification) "test-disk-grounding-verification must pass")
    true))
