(module asl-bridge/skillsInstallerTest
  :d "Unit tests for skills installer bridge specification, manifest resolution, and frontmatter validation."
  :x [runTests
      testValidateFrontmatter
      testResolveManifest]
  :i [(skillsInstaller :a si)])

(df testValidateFrontmatter [] -> Bool
  :d "Verifies validate-skill-frontmatter correctly accepts valid YAML frontmatter and rejects invalid text."
  (let [(validMd (str "---\n"
                       "name: asl-toolbelt\n"
                       "description: Core ASL toolchain\n"
                       "---\n"
                       "# ASL Toolbelt\n"))
        (validFolded (str "---\n"
                          "name: asl-toolbelt\n"
                          "description: >-\n"
                          "  Universal ASL: Triggers: \"where is X\"\n"
                          "---\n"
                          "# ASL Toolbelt\n"))
        (validQuoted (str "---\n"
                          "name: asl-toolbelt\n"
                          "description: \"Universal ASL: Triggers: test\"\n"
                          "---\n"
                          "# ASL Toolbelt\n"))
        (invalidUnquotedColon (str "---\n"
                                     "name: asl-toolbelt\n"
                                     "description: Triggers: unquoted colon fails\n"
                                     "---\n"
                                     "# ASL Toolbelt\n"))
        (validNoName (str "---\n"
                            "description: Anonymous skill\n"
                            "---\n"
                            "# Docs\n"))
        (missingDelim (str "name: foo\n"
                            "description: bar\n"))
        (noDesc (str "---\n"
                      "other: value\n"
                      "---\n"))
        (emptyText "")]
    (assert (si/validateSkillFrontmatter validMd) "Valid md must pass")
    (assert (si/validateSkillFrontmatter validFolded) "Valid folded must pass")
    (assert (si/validateSkillFrontmatter validQuoted) "Valid quoted must pass")
    (assert (not (si/validateSkillFrontmatter invalidUnquotedColon)) "Unquoted colon must fail")
    (assert (si/validateSkillFrontmatter validNoName) "Valid no name must pass")
    (assert (not (si/validateSkillFrontmatter missingDelim)) "Missing delim must fail")
    (assert (not (si/validateSkillFrontmatter noDesc)) "No desc must fail")
    (assert (not (si/validateSkillFrontmatter emptyText)) "Empty text must fail")
    true))

(df testResolveManifest [] -> Bool
  :d "Verifies resolve-skill-manifest correctly constructs SkillManifest records."
  (let [(m1 (si/resolveSkillManifest "asl-intel" "/path/to/asl-intel"))
        (m2 (si/resolveSkillManifest "" ""))]
    (assert (= (.-name m1) "asl-intel") "m1 name must match")
    (assert (= (.-path m1) "/path/to/asl-intel") "m1 path must match")
    (assert (.-verified m1) "m1 must be verified")
    (assert (string-contains? (.-description m1) "asl-intel") "m1 description must contain name")
    (assert (not (.-verified m2)) "m2 must not be verified")
    true))

(df runTests [] -> Bool
  :d "Executes all skills installer test suites."
  (do
    (assert (testValidateFrontmatter) "test-validate-frontmatter must pass")
    (assert (testResolveManifest) "test-resolve-manifest must pass")
    true))
