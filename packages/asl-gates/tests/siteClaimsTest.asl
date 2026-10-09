(module asl-gates/tests/siteClaimsTest :x [testKnownClaims testUnknownClaim testClaimsAudit testFullGrounding! testDiskGroundingVerification! runTests] :i [(siteClaims :a sc)])

fn testKnownClaims -> Bool
  (let [(registry (sc/standardClaims))] (assert (sc/isKnownMetric "57%-65%" registry) "metric 57-65%") (assert (sc/isKnownMetric "<100ms" registry) "metric <100ms") (assert (sc/isKnownMetric "24MB" registry) "metric 24MB") true)

fn testUnknownClaim -> Bool
  (let [(registry (sc/standardClaims))] (assert (sc/isKnownMetric "24MB" registry) "known valid metric claim accepted") (assert (sc/isKnownMetric "0.038ms" registry) "known sub-millisecond metric claim accepted") (assert (not (sc/isKnownMetric "99.999% fake" registry)) "fake claim rejected") (assert (not (sc/isKnownMetric "" registry)) "empty claim string rejected") (assert (not (sc/isKnownMetric "bogus-throughput" registry)) "unregistered bogus metric rejected") (assert (not (sc/auditClaim "ungrounded-speedup" registry).grounded) "audit claim of ungrounded metric must not be grounded") true)

fn testClaimsAudit -> Bool
  (let [(registry (sc/standardClaims)) (sample (list "57%-65%" "fake-claim")) (report (sc/runClaimsAudit sample registry))] (assert (= report.total 2) "total 2") (assert (= report.passed 1) "passed 1") (assert (= report.failed 1) "failed 1") (assert (= report.status "FAIL") "status FAIL") true)

fn testFullGrounding! -> Bool
  (let [(registry (sc/standardClaims)) (goodReport (sc/runClaimsAudit registry registry)) (badReport (sc/runClaimsAudit (list "fabricated-speedup" "invalid-metric") registry))] (assert (sc/verifyClaimsGrounding) "claims grounded") (assert (= goodReport.status "PASS") "canonical claims audit report must pass") (assert (= goodReport.failed 0) "canonical claims audit must have zero failures") (assert (not (= badReport.status "PASS")) "ungrounded claims audit report must not pass") (assert (not (= badReport.failed 0)) "ungrounded claims audit must have non-zero failure count") (assert (not (sc/isKnownMetric "fabricated-speedup" registry)) "invalid claim must not be in standard registry") true)

fn testDiskGroundingVerification! -> Bool
  (do (assert (sc/verifyClaimsGrounding) "verify-claims-grounding must return true on valid monorepo published claims") true)

fn ! runTests -> Bool
  (do (assert (testKnownClaims) "test-known-claims must pass") (assert (testUnknownClaim) "test-unknown-claim must pass") (assert (testClaimsAudit) "test-claims-audit must pass") (assert (testFullGrounding!) "test-full-grounding must pass") (assert (testDiskGroundingVerification!) "test-disk-grounding-verification must pass") true)
