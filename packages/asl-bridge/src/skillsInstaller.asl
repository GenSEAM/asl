(module asl-bridge/skillsInstaller
  :d "Pure AgentScript specification for skills installer bridge, manifest resolution, and YAML frontmatter validation."
  :x [SkillManifest
      makeSkillManifest
      validateSkillFrontmatter
      resolveSkillManifest
      isValidFrontmatterDesc?]
  :i [])

(dfs SkillManifest
  (:f name Str "Unique skill identifier name")
  (:f description Str "Human-readable description extracted from skill frontmatter")
  (:f path Str "Filesystem path to skill directory or SKILL.md")
  (:f verified Bool "Verification flag indicating valid skill structure and frontmatter"))

(df makeSkillManifest [(name Str) (description Str) (path Str) (verified Bool)] -> SkillManifest
  :d "Constructs a SkillManifest record with explicit metadata fields."
  (SkillManifest
    :name name
    :description description
    :path path
    :verified verified))

(df isValidFrontmatterDesc? [(rawText Str)] -> Bool
  :d "Ensures description in frontmatter doesn't use invalid unquoted colons."
  (if (string-contains? rawText "description: >-")
      true
      (if (string-contains? rawText "description: \"")
          true
          (if (string-contains? rawText "description: '")
              true
              (let [(lines (string-split rawText "\n"))
                    (descLines (filter (fn [(l Str)] -> Bool (string-starts-with? (string-trim l) "description:")) lines))]
                (mt (list-head descLines)
                  ((none) true)
                  ((some dl)
                   (let [(afterPrefix (option-or (string-slice dl 12 (string-length dl)) ""))]
                     (not (string-contains? afterPrefix ": "))))))))))

(df validateSkillFrontmatter [(rawText Str)] -> Bool
  :d "Validates that skill markdown content contains valid YAML frontmatter delimiters and required metadata."
  (and (string-starts-with? rawText "---")
       (and (string-contains? rawText "\n---")
            (and (or (string-contains? rawText "description:")
                     (string-contains? rawText "name:"))
                 (isValidFrontmatterDesc? rawText)))))

(df resolveSkillManifest [(skillName Str) (path Str)] -> SkillManifest
  :d "Resolves and constructs a SkillManifest record given a skill name identifier and directory path."
  (let [(valid (and (not (string-empty? skillName))
                    (not (string-empty? path))))
        (desc (if valid (str "Skill manifest for " skillName) ""))]
    (SkillManifest
      :name skillName
      :description desc
      :path path
      :verified valid)))
