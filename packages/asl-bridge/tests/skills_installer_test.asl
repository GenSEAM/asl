(module asl-bridge/skills-installer-test
  :d "Unit tests for skills installer bridge specification, manifest resolution, and frontmatter validation."
  :x [run-tests
      test-validate-frontmatter
      test-resolve-manifest]
  :i [(skills-installer :a si)])

(df test-validate-frontmatter [] -> Bool
  :d "Verifies validate-skill-frontmatter correctly accepts valid YAML frontmatter and rejects invalid text."
  (let [(valid-md (str "---\n"
                       "name: asl-toolbelt\n"
                       "description: Core ASL toolchain\n"
                       "---\n"
                       "# ASL Toolbelt\n"))
        (valid-folded (str "---\n"
                          "name: asl-toolbelt\n"
                          "description: >-\n"
                          "  Universal ASL: Triggers: \"where is X\"\n"
                          "---\n"
                          "# ASL Toolbelt\n"))
        (valid-quoted (str "---\n"
                          "name: asl-toolbelt\n"
                          "description: \"Universal ASL: Triggers: test\"\n"
                          "---\n"
                          "# ASL Toolbelt\n"))
        (invalid-unquoted-colon (str "---\n"
                                     "name: asl-toolbelt\n"
                                     "description: Triggers: unquoted colon fails\n"
                                     "---\n"
                                     "# ASL Toolbelt\n"))
        (valid-no-name (str "---\n"
                            "description: Anonymous skill\n"
                            "---\n"
                            "# Docs\n"))
        (missing-delim (str "name: foo\n"
                            "description: bar\n"))
        (no-desc (str "---\n"
                      "other: value\n"
                      "---\n"))
        (empty-text "")]
    (assert (si/validate-skill-frontmatter valid-md) "Valid md must pass")
    (assert (si/validate-skill-frontmatter valid-folded) "Valid folded must pass")
    (assert (si/validate-skill-frontmatter valid-quoted) "Valid quoted must pass")
    (assert (not (si/validate-skill-frontmatter invalid-unquoted-colon)) "Unquoted colon must fail")
    (assert (si/validate-skill-frontmatter valid-no-name) "Valid no name must pass")
    (assert (not (si/validate-skill-frontmatter missing-delim)) "Missing delim must fail")
    (assert (not (si/validate-skill-frontmatter no-desc)) "No desc must fail")
    (assert (not (si/validate-skill-frontmatter empty-text)) "Empty text must fail")
    true))

(df test-resolve-manifest [] -> Bool
  :d "Verifies resolve-skill-manifest correctly constructs SkillManifest records."
  (let [(m1 (si/resolve-skill-manifest "asl-intel" "/path/to/asl-intel"))
        (m2 (si/resolve-skill-manifest "" ""))]
    (assert (= (.-name m1) "asl-intel") "m1 name must match")
    (assert (= (.-path m1) "/path/to/asl-intel") "m1 path must match")
    (assert (.-verified m1) "m1 must be verified")
    (assert (string-contains? (.-description m1) "asl-intel") "m1 description must contain name")
    (assert (not (.-verified m2)) "m2 must not be verified")
    true))

(df run-tests [] -> Bool
  :d "Executes all skills installer test suites."
  (do
    (assert (test-validate-frontmatter) "test-validate-frontmatter must pass")
    (assert (test-resolve-manifest) "test-resolve-manifest must pass")
    true))
