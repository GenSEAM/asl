(module asl-gates/test
  :d "Unit tests for pure AgentScript verification gate runners."
  :x [test-syntax-valid test-syntax-invalid test-foreign-ext test-grammar-gate test-skills-gate test-manifest-gate test-runner run-tests]
  :i [(gates :a g)
      (grammar-gate :a gg)
      (skills-gate :a sg)
      (manifest-gate :a mg)
      (runner :a rn)])

(df test-syntax-valid [] -> Bool
  :d "Verifies clean syntax passes gate parser check."
  (do
    (assert (g/verify-source-syntax "(module test/m :doc \"d\" :export [f]) (df f [(x Int64)] -> Int64 :doc \"f\" (+ x 1))") "valid syntax")
    true))

(df test-syntax-invalid [] -> Bool
  :d "Verifies invalid syntax is rejected by gate parser."
  (do
    (assert (not (g/verify-source-syntax "(module broken (:export unclosed")) "invalid syntax")
    true))

(df test-foreign-ext [] -> Bool
  :d "Verifies foreign extension rejection policy."
  (do
    (assert (not (g/verify-foreign-ext ".py")) "reject .py")
    (assert (not (g/verify-foreign-ext ".ts")) "reject .ts")
    (assert (not (g/verify-foreign-ext ".js")) "reject .js")
    (assert (not (g/verify-foreign-ext ".json")) "reject .json")
    (assert (g/verify-foreign-ext ".asl") "allow .asl")
    true))

(df test-grammar-gate [] -> Bool
  :d "Verifies ASN grammar token density audit."
  (let [(e1 (gg/make-symbol-entry "run" (gg/sym-fn) 1 false ""))
        (e2 (gg/make-symbol-entry "make-circuit" (gg/sym-fn) 2 true "Creates circuit"))
        (e3 (gg/make-symbol-entry "make-circuit-bad" (gg/sym-fn) 3 false ""))]
    (assert (gg/audit-symbol-density e1 1) "e1 density")
    (assert (gg/audit-symbol-density e2 1) "e2 density")
    (assert (not (gg/audit-symbol-density e3 1)) "e3 bad density")
    true))

(df test-skills-gate [] -> Bool
  :d "Verifies skills frontmatter parser and validation."
  (let [(valid-rec (sg/make-skill-record "skills/test/SKILL.md" "test-skill" "A test skill" true))
        (valid-folded (sg/make-skill-record "skills/test/SKILL.md" "test-skill" ">-" true))
        (valid-quoted (sg/make-skill-record "skills/test/SKILL.md" "test-skill" "\"Triggers: test\"" true))
        (invalid-unquoted-colon (sg/make-skill-record "skills/test/SKILL.md" "test-skill" "Triggers: unquoted colon fails" true))
        (invalid-rec (sg/make-skill-record "skills/test/SKILL.md" "" "No name" true))]
    (assert (sg/verify-skill-record valid-rec) "valid-rec")
    (assert (sg/verify-skill-record valid-folded) "valid-folded")
    (assert (sg/verify-skill-record valid-quoted) "valid-quoted")
    (assert (not (sg/verify-skill-record invalid-unquoted-colon)) "invalid-unquoted-colon")
    (assert (not (sg/verify-skill-record invalid-rec)) "invalid-rec")
    true))

(df test-manifest-gate [] -> Bool
  :d "Verifies package manifest structure verification."
  (let [(valid-m (mg/make-manifest-record "manifest.asn" "@genseam/asl-codec" "0.1.0" "src/codec.asl"))
        (invalid-m (mg/make-manifest-record "manifest.asn" "bad-name" "0.1.0" "src/codec.asl"))]
    (assert (mg/verify-manifest-record valid-m) "valid-m")
    (assert (not (mg/verify-manifest-record invalid-m)) "invalid-m")
    true))

(df test-runner [] -> Bool
  :d "Verifies 7-Gate orchestration runner."
  (let [(summary (rn/run-all-seven-gates 15 87 12 0 31 1638 13))]
    (assert (.-all-clean summary) "all-clean")
    (assert (= (.-passed-gates summary) 7) "7 gates passed")
    true))

(df run-tests [] -> Bool
  :d "Runs all pure ASL gate tests."
  (do
    (assert (test-syntax-valid) "test-syntax-valid must pass")
    (assert (test-syntax-invalid) "test-syntax-invalid must pass")
    (assert (test-foreign-ext) "test-foreign-ext must pass")
    (assert (test-grammar-gate) "test-grammar-gate must pass")
    (assert (test-skills-gate) "test-skills-gate must pass")
    (assert (test-manifest-gate) "test-manifest-gate must pass")
    (assert (test-runner) "test-runner must pass")
    true))
