(module asl-gates/tests/skillsGateTest
  :d "Comprehensive unit tests for skills_gate functionality."
  :x [testMakeSkill testVerifySkill testCleanLegacy testYamlDescription testParseFrontmatter testAsnSpec runTests]
  :i [(skillsGate :a sg)])

(df testMakeSkill [] -> Bool
  :d "Verifies makeSkillRecord construction"
  (let [(r (sg/makeSkillRecord "path/SKILL.md" "my-skill" "A description" true))]
    (do
      (assert (= (.-path r) "path/SKILL.md") "path")
      (assert (= (.-name r) "my-skill") "name")
      (assert (= (.-description r) "A description") "description")
      (assert (.-hasFrontmatter r) "hasFrontmatter")
      (assert (.-isValid r) "isValid")
      true)))

(df testVerifySkill [] -> Bool
  :d "Verifies verifySkillRecord for valid and invalid records"
  (let [(valid (sg/makeSkillRecord "p" "skill-name" "Valid description" true))
        (noName (sg/makeSkillRecord "p" "" "desc" true))
        (noDesc (sg/makeSkillRecord "p" "name" "" true))
        (noFm (sg/makeSkillRecord "p" "name" "desc" false))
        (legacy (sg/makeSkillRecord "p" "name" "old skyloom reference" true))
        (legacyAlias (sg/makeSkillRecord "p" "name" "skyloom alias mapping" true))
        (colonDesc (sg/makeSkillRecord "p" "name" "Triggers: unquoted" true))
        (quotedDesc (sg/makeSkillRecord "p" "name" "\"Triggers: quoted\"" true))
        (foldedDesc (sg/makeSkillRecord "p" "name" ">-" true))]
    (do
      (assert (sg/verifySkillRecord valid) "valid record passes")
      (assert (not (sg/verifySkillRecord noName)) "no name fails")
      (assert (not (sg/verifySkillRecord noDesc)) "no desc fails")
      (assert (not (sg/verifySkillRecord noFm)) "no frontmatter fails")
      (assert (not (sg/verifySkillRecord legacy)) "legacy skyloom without alias fails")
      (assert (sg/verifySkillRecord legacyAlias) "legacy skyloom with alias passes")
      (assert (not (sg/verifySkillRecord colonDesc)) "unquoted colon fails")
      (assert (sg/verifySkillRecord quotedDesc) "quoted colon passes")
      (assert (sg/verifySkillRecord foldedDesc) "folded scalar passes")
      true)))

(df testCleanLegacy [] -> Bool
  :d "Verifies isCleanOfLegacy? for various inputs"
  (do
    (assert (sg/isCleanOfLegacy? "normal description") "normal passes")
    (assert (not (sg/isCleanOfLegacy? "old Skyloom reference")) "skyloom without alias fails")
    (assert (sg/isCleanOfLegacy? "skyloom alias mapping") "skyloom with alias passes")
    true))

(df testYamlDescription [] -> Bool
  :d "Verifies isValidYamlDescription? for various inputs"
  (do
    (assert (sg/isValidYamlDescription? "plain text") "plain text passes")
    (assert (not (sg/isValidYamlDescription? "key: value")) "unquoted colon fails")
    (assert (sg/isValidYamlDescription? "\"key: value\"") "quoted colon passes")
    (assert (sg/isValidYamlDescription? "'key: value'") "single-quoted colon passes")
    (assert (sg/isValidYamlDescription? ">-") "folded scalar passes")
    true))

(df testParseFrontmatter [] -> Bool
  :d "Verifies parseFrontmatterField extraction"
  (let [(content "---\nname: my-skill\ndescription: A test skill\n---")
        (name (sg/parseFrontmatterField content "name: "))
        (desc (sg/parseFrontmatterField content "description: "))
        (missing (sg/parseFrontmatterField content "nonexistent: "))]
    (do
      (assert (= name "my-skill") "name extracted")
      (assert (= desc "A test skill") "description extracted")
      (assert (= missing "") "missing returns empty")
      true)))

(df testAsnSpec [] -> Bool
  :d "Verifies AsnSkillSpec construction and validation"
  (let [(valid (sg/makeAsnSkillSpec "skill" "desc" 3 2))
        (noName (sg/makeAsnSkillSpec "" "desc" 3 2))
        (noDesc (sg/makeAsnSkillSpec "skill" "" 3 2))
        (noRules (sg/makeAsnSkillSpec "skill" "desc" 0 2))
        (noTools (sg/makeAsnSkillSpec "skill" "desc" 3 0))]
    (do
      (assert (sg/verifyAsnSkillSpec valid) "valid spec")
      (assert (not (sg/verifyAsnSkillSpec noName)) "no name spec fails")
      (assert (not (sg/verifyAsnSkillSpec noDesc)) "no desc spec fails")
      (assert (not (sg/verifyAsnSkillSpec noRules)) "no rules spec fails")
      (assert (not (sg/verifyAsnSkillSpec noTools)) "no tools spec fails")
      true)))

(df runTests [] -> Bool
  :d "Master test runner for skills gate."
  (do
    (assert (testMakeSkill) "testMakeSkill")
    (assert (testVerifySkill) "testVerifySkill")
    (assert (testCleanLegacy) "testCleanLegacy")
    (assert (testYamlDescription) "testYamlDescription")
    (assert (testParseFrontmatter) "testParseFrontmatter")
    (assert (testAsnSpec) "testAsnSpec")
    true))
