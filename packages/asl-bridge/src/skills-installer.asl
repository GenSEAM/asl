(module asl-bridge/skills-installer
  :d "Pure AgentScript specification for skills installer bridge, manifest resolution, and YAML frontmatter validation."
  :x [SkillManifest
      make-skill-manifest
      validate-skill-frontmatter
      resolve-skill-manifest
      is-valid-frontmatter-desc?]
  :i [])

(dfs SkillManifest
  (:f name Str "Unique skill identifier name")
  (:f description Str "Human-readable description extracted from skill frontmatter")
  (:f path Str "Filesystem path to skill directory or SKILL.md")
  (:f verified Bool "Verification flag indicating valid skill structure and frontmatter"))

(df make-skill-manifest [(name Str) (description Str) (path Str) (verified Bool)] -> SkillManifest
  :d "Constructs a SkillManifest record with explicit metadata fields."
  (SkillManifest
    :name name
    :description description
    :path path
    :verified verified))

(df is-valid-frontmatter-desc? [(raw-text Str)] -> Bool
  :d "Ensures description in frontmatter doesn't use invalid unquoted colons."
  (if (string-contains? raw-text "description: >-")
      true
      (if (string-contains? raw-text "description: \"")
          true
          (if (string-contains? raw-text "description: '")
              true
              (let [(lines (string-split raw-text "\n"))
                    (desc-lines (filter (fn [(l Str)] -> Bool (string-starts-with? (string-trim l) "description:")) lines))]
                (mt (list-head desc-lines)
                  ((none) true)
                  ((some dl)
                   (let [(after-prefix (option-or (string-slice dl 12 (string-length dl)) ""))]
                     (not (string-contains? after-prefix ": "))))))))))

(df validate-skill-frontmatter [(raw-text Str)] -> Bool
  :d "Validates that skill markdown content contains valid YAML frontmatter delimiters and required metadata."
  (and (string-starts-with? raw-text "---")
       (and (string-contains? raw-text "\n---")
            (and (or (string-contains? raw-text "description:")
                     (string-contains? raw-text "name:"))
                 (is-valid-frontmatter-desc? raw-text)))))

(df resolve-skill-manifest [(skill-name Str) (path Str)] -> SkillManifest
  :d "Resolves and constructs a SkillManifest record given a skill name identifier and directory path."
  (let [(valid (and (not (string-empty? skill-name))
                    (not (string-empty? path))))
        (desc (if valid (str "Skill manifest for " skill-name) ""))]
    (SkillManifest
      :name skill-name
      :description desc
      :path path
      :verified valid)))
