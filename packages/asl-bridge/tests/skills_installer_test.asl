(module asl-bridge/skills-installer-test
  :d "Unit tests for skills installer bridge specification, manifest resolution, and frontmatter validation."
  :x [run-tests
      test-validate-frontmatter
      test-resolve-manifest]
  :i [(skills-installer :a si)])

"run: (run-tests)"

(df test-validate-frontmatter [] -> Bool
  :d "Verifies validate-skill-frontmatter correctly accepts valid YAML frontmatter and rejects invalid text."
  (let [(valid-md (str "---\n"
                       "name: asl-toolbelt\n"
                       "description: Core ASL toolchain\n"
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
    (and (si/validate-skill-frontmatter valid-md)
         (and (si/validate-skill-frontmatter valid-no-name)
              (and (not (si/validate-skill-frontmatter missing-delim))
                   (and (not (si/validate-skill-frontmatter no-desc))
                        (not (si/validate-skill-frontmatter empty-text))))))))

(df test-resolve-manifest [] -> Bool
  :d "Verifies resolve-skill-manifest correctly constructs SkillManifest records."
  (let [(m1 (si/resolve-skill-manifest "asl-intel" "/path/to/asl-intel"))
        (m2 (si/resolve-skill-manifest "" ""))]
    (and (= (.-name m1) "asl-intel")
         (and (= (.-path m1) "/path/to/asl-intel")
              (and (.-verified m1)
                   (and (string-contains? (.-description m1) "asl-intel")
                        (not (.-verified m2))))))))

(df run-tests [] -> Bool
  :d "Executes all skills installer test suites."
  (let [(results (list (test-validate-frontmatter)
                       (test-resolve-manifest)))]
    (not (list-contains? results false))))
