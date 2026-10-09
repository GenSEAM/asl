(module asl-transpile/tests/skillEngineTest :x [runSkillEngineTests runTests] :i [(asl-transpile/skillEngine :a se)])

fn runSkillEngineTests -> Bool
  (let [(t1 (se/makeTool "intel-outline" "asl intel outline <file>" "Extracts module AST skeleton" "94%")) (t2 (se/makeTool "intel-impact" "asl intel impact <symbol>" "Analyzes blast radius of changes" "88%")) (r1 (se/makeRule "negative" "Never call View on files >50 lines")) (r2 (se/makeRule "mandatory" "Verify changes with asl check and asl lint")) (skill (se/makeSkill "asl-toolbelt" "Universal ASL Code Intelligence: Triggers: \"where is X\", test: pass" (list r1 r2) (list t1 t2) (list "claude-code" "factory-droid" "antigravity"))) (md (se/emitSkill skill)) (stub (se/emitStub skill)) (savings (se/calcSavings skill))] (assert (stringContains? md "name: asl-toolbelt") "md must contain skill name") (assert (stringContains? md "description: >-\n  Universal ASL Code Intelligence: Triggers: \"where is X\", test: pass") "md must contain description") (assert (stringContains? md "asl intel outline <file>") "md must contain tool trigger") (assert (stringContains? stub ":skill-stub") "stub must contain :skill-stub") (assert (> savings 50.0) "savings must exceed 50%") true)

fn runTests -> Bool
  (do (assert (runSkillEngineTests) "run-skill-engine-tests must pass") true)
