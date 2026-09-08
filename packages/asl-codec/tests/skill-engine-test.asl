(module asl-codec/tests/skill-engine-test
  :d "Unit tests verifying ASN skill compilation, Markdown generation, and token compression."
  :x [run-skill-engine-tests run-tests]
  :i [(asl-codec/skill-engine :a se)])

(df run-skill-engine-tests [] -> Bool
  :d "Executes test assertions for skill-engine dual-projection compiler."
  (let [(t1 (se/make-tool "intel-outline" "asl intel outline <file>" "Extracts module AST skeleton" "94%"))
        (t2 (se/make-tool "intel-impact" "asl intel impact <symbol>" "Analyzes blast radius of changes" "88%"))
        (r1 (se/make-rule "negative" "Never call View on files >50 lines"))
        (r2 (se/make-rule "mandatory" "Verify changes with asl check and asl lint"))
        (skill (se/make-skill "asl-toolbelt"
                              "Universal ASL Code Intelligence: Triggers: \"where is X\", test: pass"
                              [r1 r2]
                              [t1 t2]
                              ["claude-code" "factory-droid" "antigravity"]))
        (md (se/emit-skill skill))
        (stub (se/emit-stub skill))
        (savings (se/calc-savings skill))]
    (assert (string-contains? md "name: asl-toolbelt") "md must contain skill name")
    (assert (string-contains? md "description: >-\n  Universal ASL Code Intelligence: Triggers: \"where is X\", test: pass") "md must contain description")
    (assert (string-contains? md "asl intel outline <file>") "md must contain tool trigger")
    (assert (string-contains? stub ":skill-stub") "stub must contain :skill-stub")
    (assert (> savings 50.0) "savings must exceed 50%")
    true))

(df run-tests [] -> Bool
  :d "Runs skill engine test suite"
  (do
    (assert (run-skill-engine-tests) "run-skill-engine-tests must pass")
    true))
