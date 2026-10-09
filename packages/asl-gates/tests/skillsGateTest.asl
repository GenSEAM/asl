(module asl-gates/tests/skillsGateTest :x [testMakeSkill testVerifySkill testCleanLegacy testYamlDescription testParseFrontmatter testAsnSpec runTests] :i [(skillsGate :a sg)])

fn testMakeSkill -> Bool
  (let [(r (sg/makeSkillRecord "path/SKILL.md" "my-skill" "A description" true))] (do (assert (= r.path "path/SKILL.md") "path") (assert (= r.name "my-skill") "name") (assert (= r.description "A description") "description") (assert r.hasFrontmatter "hasFrontmatter") (assert r.isValid "isValid") true))

fn testVerifySkill -> Bool
  (let [(valid (sg/makeSkillRecord "p" "skill-name" "Valid description" true)) (noName (sg/makeSkillRecord "p" "" "desc" true)) (noDesc (sg/makeSkillRecord "p" "name" "" true)) (noFm (sg/makeSkillRecord "p" "name" "desc" false)) (legacy (sg/makeSkillRecord "p" "name" "old skyloom reference" true)) (legacyAlias (sg/makeSkillRecord "p" "name" "skyloom alias mapping" true)) (colonDesc (sg/makeSkillRecord "p" "name" "Triggers: unquoted" true)) (quotedDesc (sg/makeSkillRecord "p" "name" "\"Triggers: quoted\"" true)) (foldedDesc (sg/makeSkillRecord "p" "name" ">-" true))] (do (assert (sg/verifySkillRecord valid) "valid record passes") (assert (not (sg/verifySkillRecord noName)) "no name fails") (assert (not (sg/verifySkillRecord noDesc)) "no desc fails") (assert (not (sg/verifySkillRecord noFm)) "no frontmatter fails") (assert (not (sg/verifySkillRecord legacy)) "legacy skyloom without alias fails") (assert (sg/verifySkillRecord legacyAlias) "legacy skyloom with alias passes") (assert (not (sg/verifySkillRecord colonDesc)) "unquoted colon fails") (assert (sg/verifySkillRecord quotedDesc) "quoted colon passes") (assert (sg/verifySkillRecord foldedDesc) "folded scalar passes") true))

fn testCleanLegacy -> Bool
  (do (assert (sg/isCleanOfLegacy? "normal description") "normal passes") (assert (not (sg/isCleanOfLegacy? "old Skyloom reference")) "skyloom without alias fails") (assert (sg/isCleanOfLegacy? "skyloom alias mapping") "skyloom with alias passes") true)

fn testYamlDescription -> Bool
  (do (assert (sg/isValidYamlDescription? "plain text") "plain text passes") (assert (not (sg/isValidYamlDescription? "key: value")) "unquoted colon fails") (assert (sg/isValidYamlDescription? "\"key: value\"") "quoted colon passes") (assert (sg/isValidYamlDescription? "'key: value'") "single-quoted colon passes") (assert (sg/isValidYamlDescription? ">-") "folded scalar passes") true)

fn testParseFrontmatter -> Bool
  (let [(content "---\nname: my-skill\ndescription: A test skill\n---") (name (sg/parseFrontmatterField content "name: ")) (desc (sg/parseFrontmatterField content "description: ")) (missing (sg/parseFrontmatterField content "nonexistent: "))] (do (assert (= name "my-skill") "name extracted") (assert (= desc "A test skill") "description extracted") (assert (= missing "") "missing returns empty") true))

fn testAsnSpec -> Bool
  (let [(valid (sg/makeAsnSkillSpec "skill" "desc" 3 2)) (noName (sg/makeAsnSkillSpec "" "desc" 3 2)) (noDesc (sg/makeAsnSkillSpec "skill" "" 3 2)) (noRules (sg/makeAsnSkillSpec "skill" "desc" 0 2)) (noTools (sg/makeAsnSkillSpec "skill" "desc" 3 0))] (do (assert (sg/verifyAsnSkillSpec valid) "valid spec") (assert (not (sg/verifyAsnSkillSpec noName)) "no name spec fails") (assert (not (sg/verifyAsnSkillSpec noDesc)) "no desc spec fails") (assert (not (sg/verifyAsnSkillSpec noRules)) "no rules spec fails") (assert (not (sg/verifyAsnSkillSpec noTools)) "no tools spec fails") true))

fn runTests -> Bool
  (do (assert (testMakeSkill) "testMakeSkill") (assert (testVerifySkill) "testVerifySkill") (assert (testCleanLegacy) "testCleanLegacy") (assert (testYamlDescription) "testYamlDescription") (assert (testParseFrontmatter) "testParseFrontmatter") (assert (testAsnSpec) "testAsnSpec") true)
