(module asl-gates/tests/ruleCheckersGradingTest :x [testAuditC3CanonicalHomesEnforcement testAuditGradingPrefixContainment testAuditOutputTokenizedEvidence testAuditCheckScriptExistence testDualPolarityRefutations runTests] :i [(asl-gates/ruleCheckers :a rc)])

fn testAuditC3CanonicalHomesEnforcement -> Bool
  (let [(defs (list (list "myFn" "pkg-rogue"))) (allowlist (list)) (canonical (list (list "myFn" "pkg-home"))) (resBad (rc/auditC3Duplicates defs allowlist canonical)) (defsGood (list (list "myFn" "pkg-home"))) (resGood (rc/auditC3Duplicates defsGood allowlist canonical))] (assert (not resBad.passed) "Definition outside canonical home must fail auditC3Duplicates") (assert resGood.passed "Definition inside canonical home must pass auditC3Duplicates") true)

fn testAuditGradingPrefixContainment -> Bool
  (let [(authorPaths (list "src/foo/bar.asl")) (verifierPaths (list "src/foo")) (resOverlap (rc/auditGradingRule "author" "verifier" authorPaths verifierPaths))] (assert (not resOverlap.passed) "Prefix containment overlap must fail auditGradingRule") true)

fn testAuditOutputTokenizedEvidence -> Bool
  (let [(fakeEvidence (list "(:pathology test :linear 1)")) (resFake (rc/auditOutputRule fakeEvidence)) (realEvidence (list "(:path \"src/foo.asl\" :line 42)")) (resReal (rc/auditOutputRule realEvidence))] (assert (not resFake.passed) "Substring collisions like pathology must fail auditOutputRule") (assert resReal.passed "Proper tokenized :path and :line must pass auditOutputRule") true)

fn ! testAuditCheckScriptExistence -> Bool
  (let [(badScripts (list "scripts/nonexistent-verify-script-999.sh")) (resBad (rc/auditCheckScriptExistence badScripts)) (goodScripts (list "asl/packages/asl-gates/src/runnerMain.asl")) (resGood (rc/auditCheckScriptExistence goodScripts))] (assert (not resBad.passed) "Nonexistent verification script must fail auditCheckScriptExistence") (assert resGood.passed "Existing verification script must pass auditCheckScriptExistence") true)

fn testDualPolarityRefutations -> Bool
  (let [(resGrading (rc/auditGradingRule "author" "verifier" (list "src/foo/bar.asl") (list "src/foo"))) (resC3 (rc/auditC3Duplicates (list (list "sym" "wrong-pkg")) (list) (list (list "sym" "home-pkg")))) (resOutput (rc/auditOutputRule (list "(:pathology x :linear y)")))] (refute resGrading.passed "Refute that sub-directory overlap passes grading audit") (refute resC3.passed "Refute that non-canonical home passes C3 audit") (refute resOutput.passed "Refute that pseudo-substrings pass output audit") true)

fn ! runTests -> Bool
  (do (assert (testAuditC3CanonicalHomesEnforcement) "testAuditC3CanonicalHomesEnforcement must pass") (assert (testAuditGradingPrefixContainment) "testAuditGradingPrefixContainment must pass") (assert (testAuditOutputTokenizedEvidence) "testAuditOutputTokenizedEvidence must pass") (assert (testAuditCheckScriptExistence) "testAuditCheckScriptExistence must pass") (assert (testDualPolarityRefutations) "testDualPolarityRefutations must pass") true)
