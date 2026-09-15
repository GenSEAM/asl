(module asl-gates/test
  :d "Unit tests for pure AgentScript verification gate runners."
  :x [testSyntaxValid testSyntaxInvalid testForeignExt testGrammarGate testSkillsGate testManifestGate testRunner runTests]
  :i [(gates :a g)
      (grammarGate :a gg)
      (skillsGate :a sg)
      (manifestGate :a mg)
      (gateRunner :a rn)])

(df testSyntaxValid [] -> Bool
  :d "Verifies clean syntax passes gate parser check."
  (do
    (assert (g/verifySourceSyntax "(module test/m :doc \"d\" :export [f]) (df f [(x Int64)] -> Int64 :doc \"f\" (+ x 1))") "valid syntax")
    (assert (not (g/verifySourceSyntax "(module broken (:export unclosed")) "unclosed form syntax rejected")
    (assert (not (g/verifySourceSyntax "(df incomplete [(x Int64)] ->")) "incomplete function signature rejected")
    (assert (not (g/verifyForeignExt ".py")) "rejected gate condition for foreign python file")
    true))

(df testSyntaxInvalid [] -> Bool
  :d "Verifies invalid syntax and invalid gate conditions are rejected by gate parser."
  (do
    (assert (g/verifySourceSyntax "(module valid/m :doc \"doc\" :export [])") "valid minimal syntax accepted")
    (assert (g/verifyForeignExt ".asl") "accepted gate condition for valid asl extension")
    (assert (not (g/verifySourceSyntax "(module broken (:export unclosed")) "invalid syntax")
    (assert (not (g/verifySourceSyntax "((( unbalanced ((((" )) "unbalanced delimiters rejected")
    (assert (not (mg/verifyManifestRecord (mg/makeManifestRecord "manifest.asn" "asl-test" "" "src/main.asl"))) "missing manifest version field rejected")
    (assert (not (mg/verifyManifestRecord (mg/makeManifestRecord "manifest.asn" "asl-test" "0.1.0" ""))) "missing manifest entry field rejected")
    (assert (not (mg/verifyManifestRecord (mg/makeManifestRecord "manifest.asn" "@sigil-pkg" "0.1.0" "src/main.asl"))) "prohibited @ sigil package name rejected")
    true))

(df testForeignExt [] -> Bool
  :d "Verifies foreign extension rejection policy."
  (let [(foreign (g/findForeignFilesInPaths (list "foo.asl" "bar.asn" "doc.md" "script.rb" "binary.bin")))]
    (assert (not (g/verifyForeignExt ".py")) "reject .py")
    (assert (not (g/verifyForeignExt ".ts")) "reject .ts")
    (assert (not (g/verifyForeignExt ".js")) "reject .js")
    (assert (not (g/verifyForeignExt ".json")) "reject .json")
    (assert (g/verifyForeignExt ".asl") "allow .asl")
    (assert (= (list-length foreign) 2) "findForeignFilesInPaths returns 2 foreign files")
    (assert (list-contains? foreign "script.rb") "script.rb detected")
    (assert (list-contains? foreign "binary.bin") "binary.bin detected")
    true))

(df testGrammarGate [] -> Bool
  :d "Verifies ASN grammar token density audit."
  (let [(e1 (gg/makeSymbolEntry "run" (gg/symFn) 1 false ""))
        (e2 (gg/makeSymbolEntry "make-circuit" (gg/symFn) 2 true "Creates circuit"))
        (e3 (gg/makeSymbolEntry "make-circuit-bad" (gg/symFn) 3 false ""))]
    (assert (gg/auditSymbolDensity e1 1) "e1 density")
    (assert (gg/auditSymbolDensity e2 1) "e2 density")
    (assert (not (gg/auditSymbolDensity e3 1)) "e3 bad density")
    true))

(df testSkillsGate [] -> Bool
  :d "Verifies skills frontmatter parser and validation."
  (let [(validRec (sg/makeSkillRecord "skills/test/SKILL.md" "test-skill" "A test skill" true))
        (validFolded (sg/makeSkillRecord "skills/test/SKILL.md" "test-skill" ">-" true))
        (validQuoted (sg/makeSkillRecord "skills/test/SKILL.md" "test-skill" "\"Triggers: test\"" true))
        (invalidUnquotedColon (sg/makeSkillRecord "skills/test/SKILL.md" "test-skill" "Triggers: unquoted colon fails" true))
        (invalidRec (sg/makeSkillRecord "skills/test/SKILL.md" "" "No name" true))]
    (assert (sg/verifySkillRecord validRec) "valid-rec")
    (assert (sg/verifySkillRecord validFolded) "valid-folded")
    (assert (sg/verifySkillRecord validQuoted) "valid-quoted")
    (assert (not (sg/verifySkillRecord invalidUnquotedColon)) "invalid-unquoted-colon")
    (assert (not (sg/verifySkillRecord invalidRec)) "invalid-rec")
    true))

(df testManifestGate [] -> Bool
  :d "Verifies package manifest structure verification."
  (let [(validM (mg/makeManifestRecord "manifest.asn" "asl-codec" "0.1.0" "src/codec.asl"))
        (invalidM (mg/makeManifestRecord "manifest.asn" "@bad-sigil" "0.1.0" "src/codec.asl"))]
    (assert (mg/verifyManifestRecord validM) "valid-m")
    (assert (not (mg/verifyManifestRecord invalidM)) "invalid-m")
    true))

(df testRunner [] -> Bool
  :d "Verifies 7-Gate orchestration runner."
  (let [(summary (rn/runAllSevenGates 15 87 12 0 31 1638 13))]
    (assert (.-allClean summary) "all-clean")
    (assert (= (.-passedGates summary) 7) "7 gates passed")
    true))

(df ! testCollectDirectoryFiles [] -> Bool
  :d "Verifies collectDirectoryFiles excludes node_modules, dist, asl-quantum, and asl-arduino."
  (let [(files (g/collectDirectoryFiles "asl/packages/asl-gates"))]
    (do
      (assert (> (list-length files) 0) "should find files in asl-gates")
      (let [(badFound (fold (fn [(acc Bool) (f Str)] -> Bool
                              (or acc
                                  (or (string-contains? f "node_modules")
                                      (or (string-contains? f "dist")
                                          (or (string-contains? f "asl-quantum")
                                              (string-contains? f "asl-arduino"))))))
                            false
                            files))]
        (assert (not badFound) "no excluded directories found in output")
        true))))

(df ! testAuditPackageTreeZeroForeign [] -> Bool
  :d "Verifies auditPackageTreeZeroForeign correctly aggregates files and finds zero foreign extensions."
  (mt (g/auditPackageTreeZeroForeign (list "asl/packages/asl-gates/src"))
    ((ok cleanCount)
     (assert (> cleanCount 0) "should find clean files in src"))
    ((err violations)
     (assert false "should not find foreign files in src"))))

(df ! runTests [] -> Bool
  :d "Runs all pure ASL gate tests."
  (do
    (assert (testSyntaxValid) "test-syntax-valid must pass")
    (assert (testSyntaxInvalid) "test-syntax-invalid must pass")
    (assert (testForeignExt) "test-foreign-ext must pass")
    (assert (testGrammarGate) "test-grammar-gate must pass")
    (assert (testSkillsGate) "test-skills-gate must pass")
    (assert (testManifestGate) "test-manifest-gate must pass")
    (assert (testRunner) "test-runner must pass")
    (assert (testCollectDirectoryFiles) "test-collect-directory-files must pass")
    (assert (testAuditPackageTreeZeroForeign) "test-audit-package-tree-zero-foreign must pass")
    true))
