(module asl-gates/tests/ruleCheckersTest :x [testMakeResult testAuditGrading testAuditConcepts testAuditOwnershipDisjointness testAuditHiddenTests testAuditBounded testAuditOutput testAuditRuntimeOnly testAuditC3 testAuditCheckScript testAuditD51 runTests] :i [(ruleCheckers :a rc)])

fn testMakeResult -> Bool
  (let [(r (rc/makeRuleCheckResult "id1" true "msg1"))] (do (assert (= r.ruleId "id1") "id") (assert r.passed "passed") (assert (= r.message "msg1") "msg") true))

fn testAuditGrading -> Bool
  (let [(same (rc/auditGradingRule "a" "a" (list "f1") (list "f2"))) (diff (rc/auditGradingRule "a" "b" (list "f1") (list "f2"))) (overlap (rc/auditGradingRule "a" "b" (list "f1") (list "f1"))) (prefixOverlap (rc/auditGradingRule "a" "b" (list "src/foo/bar.asl") (list "src/foo")))] (do (assert (not same.passed) "same roles fail") (assert diff.passed "diff roles ok") (assert (not overlap.passed) "overlap paths fail") (assert (not prefixOverlap.passed) "prefix overlap paths fail") true))

fn testAuditConcepts -> Bool
  (let [(valid (rc/auditConceptsRule (list "f1" "f2") (list "f1" "f2" "f3"))) (invalid (rc/auditConceptsRule (list "f1" "f2") (list "f1")))] (do (assert valid.passed "valid") (assert (not invalid.passed) "invalid") true))

fn testAuditOwnershipDisjointness -> Bool
  (let [(disjoint (rc/auditOwnershipDisjointness (list (list "src/a.asl" "src/b.asl") (list "src/c.asl") (list "tests/d.asl")))) (exact (rc/auditOwnershipDisjointness (list (list "src/a.asl") (list "src/c.asl") (list "src/b.asl" "src/a.asl")))) (prefix (rc/auditOwnershipDisjointness (list (list "src/foo") (list "src/foo/bar.asl")))) (siblingPrefix (rc/auditOwnershipDisjointness (list (list "src/foo") (list "src/foobar.asl")))) (sameTaskOnly (rc/auditOwnershipDisjointness (list (list "src/a.asl" "src/a.asl") (list "src/b.asl")))) (empty (rc/auditOwnershipDisjointness (list))) (laterPair (rc/auditOwnershipDisjointness (list (list "src/x.asl") (list "src/a.asl") (list "src/a.asl"))))] (do (assert disjoint.passed "disjoint owns pass") (assert (not exact.passed) "same path in two tasks fails") (assert (not prefix.passed) "directory owning a path of another task fails") (assert siblingPrefix.passed "string prefix that is not a path prefix passes") (assert sameTaskOnly.passed "repetition inside one task is not a cross-task collision") (assert empty.passed "no tasks pass") (assert (not laterPair.passed) "collision between two later tasks fails") (assert (= exact.ruleId "oneStep") "ruleId") true))

fn testAuditHiddenTests -> Bool
  (let [(valid (rc/auditHiddenTestsRule (list "src/foo.asl"))) (invalid (rc/auditHiddenTestsRule (list "tests/acceptance/bar.asl")))] (do (assert valid.passed "valid") (assert (not invalid.passed) "invalid") true))

fn testAuditBounded -> Bool
  (let [(valid (rc/auditBoundedRule (list "(:limit 10)" "(:limit 20)"))) (invalid (rc/auditBoundedRule (list "(:limit 10)" "no-limit")))] (do (assert valid.passed "valid") (assert (not invalid.passed) "invalid") true))

fn testAuditOutput -> Bool
  (let [(valid (rc/auditOutputRule (list "(:path p :line 1)"))) (invalid (rc/auditOutputRule (list "(:path p)"))) (invalid2 (rc/auditOutputRule (list "(:line 1)"))) (invalidSub (rc/auditOutputRule (list "(:pathology x :linear 1)")))] (do (assert valid.passed "valid") (assert (not invalid.passed) "invalid") (assert (not invalid2.passed) "invalid2") (assert (not invalidSub.passed) "invalid substring words") true))

fn testAuditRuntimeOnly -> Bool
  (let [(valid (rc/auditRuntimeOnlyRules (list ":id budget :runtimeOnlyReason" ":id edge :runtimeOnlyReason"))) (invalid (rc/auditRuntimeOnlyRules (list ":id budget :runtimeOnlyReason")))] (do (assert valid.passed "valid") (assert (not invalid.passed) "invalid") true))

fn testAuditC3 -> Bool
  (let [(valid (rc/auditC3Duplicates (list (list "s1" "a") (list "s2" "b" "c")) (list "s2") (list))) (invalid (rc/auditC3Duplicates (list (list "s1" "a" "b" "c")) (list "s2") (list))) (invalidHome (rc/auditC3Duplicates (list (list "s3" "wrong-pkg")) (list) (list (list "s3" "home-pkg")))) (validHome (rc/auditC3Duplicates (list (list "s3" "home-pkg")) (list) (list (list "s3" "home-pkg"))))] (do (assert valid.passed "valid") (assert (not invalid.passed) "invalid") (assert (not invalidHome.passed) "invalid home") (assert validHome.passed "valid home") true))

fn ! testAuditCheckScript -> Bool
  (let [(valid (rc/auditCheckScriptExistence (list "scripts/runGateTests.sh"))) (invalid (rc/auditCheckScriptExistence (list "scripts/ghost-script-xyz.sh")))] (do (assert valid.passed "valid script exists") (assert (not invalid.passed) "missing script fails") true))

fn testAuditD51 -> Bool
  (let [(valid (rc/auditD51Convergence "pkg1" (list "testFoo") (list) 90 80)) (invalidRatio (rc/auditD51Convergence "pkg1" (list "testFoo") (list) 70 80)) (invalidKebab (rc/auditD51Convergence "pkg1" (list "test-foo") (list) 90 85))] (do (assert valid.passed "valid") (assert (not invalidRatio.passed) "invalid ratio") (assert (not invalidKebab.passed) "invalid kebab") true))

fn ! runTests -> Bool
  (do (assert (testMakeResult) "testMakeResult") (assert (testAuditGrading) "testAuditGrading") (assert (testAuditConcepts) "testAuditConcepts") (assert (testAuditOwnershipDisjointness) "testAuditOwnershipDisjointness") (assert (testAuditHiddenTests) "testAuditHiddenTests") (assert (testAuditBounded) "testAuditBounded") (assert (testAuditOutput) "testAuditOutput") (assert (testAuditRuntimeOnly) "testAuditRuntimeOnly") (assert (testAuditC3) "testAuditC3") (assert (testAuditCheckScript) "testAuditCheckScript") (assert (testAuditD51) "testAuditD51") true)
