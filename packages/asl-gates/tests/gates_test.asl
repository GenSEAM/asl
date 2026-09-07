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
  (g/verify-source-syntax "(module test/m :doc \"d\" :export [f]) (df f [(x Int64)] -> Int64 :doc \"f\" (+ x 1))"))

(df test-syntax-invalid [] -> Bool
  :d "Verifies invalid syntax is rejected by gate parser."
  (not (g/verify-source-syntax "(module broken (:export unclosed")))

(df test-foreign-ext [] -> Bool
  :d "Verifies foreign extension rejection policy."
  (and (not (g/verify-foreign-ext ".py"))
       (and (not (g/verify-foreign-ext ".ts"))
            (and (not (g/verify-foreign-ext ".js"))
                 (and (not (g/verify-foreign-ext ".json"))
                      (g/verify-foreign-ext ".asl"))))))

(df test-grammar-gate [] -> Bool
  :d "Verifies ASN grammar token density audit."
  (let [(e1 (gg/make-symbol-entry "run" (gg/sym-fn) 1 false ""))
        (e2 (gg/make-symbol-entry "make-circuit" (gg/sym-fn) 2 true "Creates circuit"))
        (e3 (gg/make-symbol-entry "make-circuit-bad" (gg/sym-fn) 3 false ""))]
    (and (gg/audit-symbol-density e1 1)
         (and (gg/audit-symbol-density e2 1)
              (not (gg/audit-symbol-density e3 1))))))

(df test-skills-gate [] -> Bool
  :d "Verifies skills frontmatter parser and validation."
  (let [(valid-rec (sg/make-skill-record "skills/test/SKILL.md" "test-skill" "A test skill" true))
        (valid-folded (sg/make-skill-record "skills/test/SKILL.md" "test-skill" ">-" true))
        (valid-quoted (sg/make-skill-record "skills/test/SKILL.md" "test-skill" "\"Triggers: test\"" true))
        (invalid-unquoted-colon (sg/make-skill-record "skills/test/SKILL.md" "test-skill" "Triggers: unquoted colon fails" true))
        (invalid-rec (sg/make-skill-record "skills/test/SKILL.md" "" "No name" true))]
    (and (sg/verify-skill-record valid-rec)
         (and (sg/verify-skill-record valid-folded)
              (and (sg/verify-skill-record valid-quoted)
                   (and (not (sg/verify-skill-record invalid-unquoted-colon))
                        (not (sg/verify-skill-record invalid-rec))))))))

(df test-manifest-gate [] -> Bool
  :d "Verifies package manifest structure verification."
  (let [(valid-m (mg/make-manifest-record "manifest.asn" "@genseam/asl-codec" "0.1.0" "src/codec.asl"))
        (invalid-m (mg/make-manifest-record "manifest.asn" "bad-name" "0.1.0" "src/codec.asl"))]
    (and (mg/verify-manifest-record valid-m)
         (not (mg/verify-manifest-record invalid-m)))))

(df test-runner [] -> Bool
  :d "Verifies 7-Gate orchestration runner."
  (let [(summary (rn/run-all-seven-gates 15 87 12 0 31 1638 13))]
    (and (.-all-clean summary)
         (= (.-passed-gates summary) 7))))

(df run-tests [] -> Bool
  :d "Runs all pure ASL gate tests."
  (and (test-syntax-valid)
       (and (test-syntax-invalid)
            (and (test-foreign-ext)
                 (and (test-grammar-gate)
                      (and (test-skills-gate)
                           (and (test-manifest-gate)
                                (test-runner))))))))

