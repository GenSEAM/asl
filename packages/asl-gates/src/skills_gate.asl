(module asl-gates/skills-gate
  :d "Pure AgentScript modular skills consistency and freshness verification gate."
  :x [SkillRecord make-skill-record parse-frontmatter-field verify-skill-record is-clean-of-legacy? is-valid-yaml-description?]
  :i [])

(dfs SkillRecord
  (:f path Str "Relative path to SKILL.md file")
  (:f name Str "Skill identifier extracted from YAML frontmatter")
  (:f description Str "Trigger description extracted from frontmatter")
  (:f has-frontmatter Bool "True if enclosed between '---' markers")
  (:f is-valid Bool "True if all required fields and anti-patterns pass"))

(df make-skill-record [(path Str) (name Str) (desc Str) (has-fm Bool)] -> SkillRecord
  (let [(valid (and has-fm (and (> (string-length name) 0) (> (string-length desc) 0))))]
    (SkillRecord
      :path path
      :name name
      :description desc
      :has-frontmatter has-fm
      :is-valid valid)))

(df parse-frontmatter-field [(content Str) (prefix Str)] -> Str
  :d "Extracts single line value following a given field prefix in frontmatter."
  (let [(lines (string-split content "\n"))
        (matched (filter (fn [(line Str)] -> Bool (string-starts-with? (string-trim line) prefix)) lines))]
    (mt (list-head matched)
      ((none) "")
      ((some l)
       (let [(trimmed (string-trim l))
             (val (option-or (string-slice trimmed (string-length prefix) (string-length trimmed)) ""))]
         (string-trim val))))))

(df is-clean-of-legacy? [(content Str)] -> Bool
  :d "Enforces clean modern naming: flags legacy skyloom references without alias tag."
  (let [(lower (string-to-lowercase content))]
    (if (string-contains? lower "skyloom")
        (string-contains? lower "alias")
        true)))

(df is-valid-yaml-description? [(desc Str)] -> Bool
  :d "Enforces valid YAML syntax: plain scalars containing colons are rejected unless quoted or folded."
  (if (or (string-starts-with? desc ">-")
          (or (string-starts-with? desc "\"")
              (string-starts-with? desc "'")))
      true
      (not (string-contains? desc ": "))))

(df verify-skill-record [(record SkillRecord)] -> Bool
  :d "Validates skill record integrity."
  (and (.-has-frontmatter record)
       (and (.-is-valid record)
            (and (is-clean-of-legacy? (.-description record))
                 (is-valid-yaml-description? (.-description record))))))
