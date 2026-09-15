(module asl-gates/tests/ruleCheckersTest
  :d "Unit tests for rule_checkers functionality."
  :x [testMakeResult testAuditGrading testAuditConcepts testAuditHiddenTests testAuditBounded testAuditOutput testAuditRuntimeOnly testAuditC3 testAuditCheckScript testAuditD51 runTests]
  :i [(ruleCheckers :a rc)])

(df testMakeResult [] -> Bool
  :d "Verifies makeRuleCheckResult functionality"
  (let [(r (rc/makeRuleCheckResult "id1" true "msg1"))]
    (do
      (assert (= (.-ruleId r) "id1") "id")
      (assert (.-passed r) "passed")
      (assert (= (.-message r) "msg1") "msg")
      true)))

(df testAuditGrading [] -> Bool
  :d "Verifies auditGradingRule functionality"
  (let [(same (rc/auditGradingRule "a" "a" (list "f1") (list "f2")))
        (diff (rc/auditGradingRule "a" "b" (list "f1") (list "f2")))
        (overlap (rc/auditGradingRule "a" "b" (list "f1") (list "f1")))
        (prefixOverlap (rc/auditGradingRule "a" "b" (list "src/foo/bar.asl") (list "src/foo")))]
    (do
      (assert (not (.-passed same)) "same roles fail")
      (assert (.-passed diff) "diff roles ok")
      (assert (not (.-passed overlap)) "overlap paths fail")
      (assert (not (.-passed prefixOverlap)) "prefix overlap paths fail")
      true)))

(df testAuditConcepts [] -> Bool
  :d "Verifies auditConceptsRule functionality"
  (let [(valid (rc/auditConceptsRule (list "f1" "f2") (list "f1" "f2" "f3")))
        (invalid (rc/auditConceptsRule (list "f1" "f2") (list "f1")))]
    (do
      (assert (.-passed valid) "valid")
      (assert (not (.-passed invalid)) "invalid")
      true)))

(df testAuditHiddenTests [] -> Bool
  :d "Verifies auditHiddenTestsRule functionality"
  (let [(valid (rc/auditHiddenTestsRule (list "src/foo.asl")))
        (invalid (rc/auditHiddenTestsRule (list "tests/acceptance/bar.asl")))]
    (do
      (assert (.-passed valid) "valid")
      (assert (not (.-passed invalid)) "invalid")
      true)))

(df testAuditBounded [] -> Bool
  :d "Verifies auditBoundedRule functionality"
  (let [(valid (rc/auditBoundedRule (list "(:limit 10)" "(:limit 20)")))
        (invalid (rc/auditBoundedRule (list "(:limit 10)" "no-limit")))]
    (do
      (assert (.-passed valid) "valid")
      (assert (not (.-passed invalid)) "invalid")
      true)))

(df testAuditOutput [] -> Bool
  :d "Verifies auditOutputRule functionality"
  (let [(valid (rc/auditOutputRule (list "(:path p :line 1)")))
        (invalid (rc/auditOutputRule (list "(:path p)")))
        (invalid2 (rc/auditOutputRule (list "(:line 1)")))
        (invalidSub (rc/auditOutputRule (list "(:pathology x :linear 1)")))]
    (do
      (assert (.-passed valid) "valid")
      (assert (not (.-passed invalid)) "invalid")
      (assert (not (.-passed invalid2)) "invalid2")
      (assert (not (.-passed invalidSub)) "invalid substring words")
      true)))

(df testAuditRuntimeOnly [] -> Bool
  :d "Verifies auditRuntimeOnlyRules functionality"
  (let [(valid (rc/auditRuntimeOnlyRules (list ":id budget :runtimeOnlyReason" ":id edge :runtimeOnlyReason")))
        (invalid (rc/auditRuntimeOnlyRules (list ":id budget :runtimeOnlyReason")))]
    (do
      (assert (.-passed valid) "valid")
      (assert (not (.-passed invalid)) "invalid")
      true)))

(df testAuditC3 [] -> Bool
  :d "Verifies auditC3Duplicates functionality"
  (let [(valid (rc/auditC3Duplicates (list (list "s1" "a") (list "s2" "b" "c")) (list "s2") (list)))
        (invalid (rc/auditC3Duplicates (list (list "s1" "a" "b" "c")) (list "s2") (list)))
        (invalidHome (rc/auditC3Duplicates (list (list "s3" "wrong-pkg")) (list) (list (list "s3" "home-pkg"))))
        (validHome (rc/auditC3Duplicates (list (list "s3" "home-pkg")) (list) (list (list "s3" "home-pkg"))))]
    (do
      (assert (.-passed valid) "valid")
      (assert (not (.-passed invalid)) "invalid")
      (assert (not (.-passed invalidHome)) "invalid home")
      (assert (.-passed validHome) "valid home")
      true)))

(df ! testAuditCheckScript [] -> Bool
  :d "Verifies auditCheckScriptExistence functionality"
  (let [(valid (rc/auditCheckScriptExistence (list "scripts/runGateTests.sh")))
        (invalid (rc/auditCheckScriptExistence (list "scripts/ghost-script-xyz.sh")))]
    (do
      (assert (.-passed valid) "valid script exists")
      (assert (not (.-passed invalid)) "missing script fails")
      true)))

(df testAuditD51 [] -> Bool
  :d "Verifies auditD51Convergence functionality"
  (let [(valid (rc/auditD51Convergence "pkg1" (list "testFoo") (list) 90 80))
        (invalidRatio (rc/auditD51Convergence "pkg1" (list "testFoo") (list) 70 80))
        (invalidKebab (rc/auditD51Convergence "pkg1" (list "test-foo") (list) 90 85))]
    (do
      (assert (.-passed valid) "valid")
      (assert (not (.-passed invalidRatio)) "invalid ratio")
      (assert (not (.-passed invalidKebab)) "invalid kebab")
      true)))

(df ! runTests [] -> Bool
  :d "Master test runner for rule checkers."
  (do
    (assert (testMakeResult) "testMakeResult")
    (assert (testAuditGrading) "testAuditGrading")
    (assert (testAuditConcepts) "testAuditConcepts")
    (assert (testAuditHiddenTests) "testAuditHiddenTests")
    (assert (testAuditBounded) "testAuditBounded")
    (assert (testAuditOutput) "testAuditOutput")
    (assert (testAuditRuntimeOnly) "testAuditRuntimeOnly")
    (assert (testAuditC3) "testAuditC3")
    (assert (testAuditCheckScript) "testAuditCheckScript")
    (assert (testAuditD51) "testAuditD51")
    true))
