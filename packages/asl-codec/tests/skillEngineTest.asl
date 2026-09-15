(module asl-codec/tests/skillEngineTest
  :d "Unit tests verifying ASN skill compilation, Markdown generation, and token compression."
  :x [runSkillEngineTests runTests]
  :i [(asl-codec/skillEngine :a se)])

(df runSkillEngineTests [] -> Bool
  :d "Executes test assertions for skill-engine dual-projection compiler."
  (let [(t1 (se/makeTool "intel-outline" "asl intel outline <file>" "Extracts module AST skeleton" "94%"))
        (t2 (se/makeTool "intel-impact" "asl intel impact <symbol>" "Analyzes blast radius of changes" "88%"))
        (r1 (se/makeRule "negative" "Never call View on files >50 lines"))
        (r2 (se/makeRule "mandatory" "Verify changes with asl check and asl lint"))
        (skill (se/makeSkill "asl-toolbelt"
                              "Universal ASL Code Intelligence: Triggers: \"where is X\", test: pass"
                              [r1 r2]
                              [t1 t2]
                              ["claude-code" "factory-droid" "antigravity"]))
        (md (se/emitSkill skill))
        (stub (se/emitStub skill))
        (savings (se/calcSavings skill))]
    (assert (string-contains? md "name: asl-toolbelt") "md must contain skill name")
    (assert (string-contains? md "description: >-\n  Universal ASL Code Intelligence: Triggers: \"where is X\", test: pass") "md must contain description")
    (assert (string-contains? md "asl intel outline <file>") "md must contain tool trigger")
    (assert (string-contains? stub ":skill-stub") "stub must contain :skill-stub")
    (assert (> savings 50.0) "savings must exceed 50%")
    true))

(df runTests [] -> Bool
  :d "Runs skill engine test suite"
  (do
    (assert (runSkillEngineTests) "run-skill-engine-tests must pass")
    true))
