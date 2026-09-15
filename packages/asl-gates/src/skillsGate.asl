(module asl-gates/skillsGate
  :d "Pure AgentScript modular skills consistency and freshness verification gate."
  :x [SkillRecord makeSkillRecord parseFrontmatterField verifySkillRecord isCleanOfLegacy? isValidYamlDescription?
      AsnSkillSpec makeAsnSkillSpec verifyAsnSkillSpec]
  :i [])

(dfs AsnSkillSpec
  (:f name Str "Skill identifier name")
  (:f description Str "Trigger description")
  (:f rulesCount I64 "Number of declared rules")
  (:f toolsCount I64 "Number of declared tools"))

(df makeAsnSkillSpec [(name Str) (desc Str) (rulesCnt I64) (toolsCnt I64)] -> AsnSkillSpec
  (AsnSkillSpec
    :name name
    :description desc
    :rulesCount rulesCnt
    :toolsCount toolsCnt))

(df verifyAsnSkillSpec [(spec AsnSkillSpec)] -> Bool
  :d "Validates that a co-located ASN skill spec has non-empty metadata, rules, and tools."
  (and (> (string-length (.-name spec)) 0)
       (and (> (string-length (.-description spec)) 0)
            (and (> (.-rulesCount spec) 0)
                 (> (.-toolsCount spec) 0)))))

(dfs SkillRecord
  (:f path Str "Relative path to SKILL.md file")
  (:f name Str "Skill identifier extracted from YAML frontmatter")
  (:f description Str "Trigger description extracted from frontmatter")
  (:f hasFrontmatter Bool "True if enclosed between '---' markers")
  (:f isValid Bool "True if all required fields and anti-patterns pass"))

(df makeSkillRecord [(path Str) (name Str) (desc Str) (hasFm Bool)] -> SkillRecord
  (let [(valid (and hasFm (and (> (string-length name) 0) (> (string-length desc) 0))))]
    (SkillRecord
      :path path
      :name name
      :description desc
      :hasFrontmatter hasFm
      :isValid valid)))

(df parseFrontmatterField [(content Str) (prefix Str)] -> Str
  :d "Extracts single line value following a given field prefix in frontmatter."
  (let [(lines (string-split content "\n"))
        (matched (filter (fn [(line Str)] -> Bool (string-starts-with? (string-trim line) prefix)) lines))]
    (mt (list-head matched)
      ((none) "")
      ((some l)
       (let [(trimmed (string-trim l))
             (val (option-or (string-slice trimmed (string-length prefix) (string-length trimmed)) ""))]
         (string-trim val))))))

(df isCleanOfLegacy? [(content Str)] -> Bool
  :d "Enforces clean modern naming: flags legacy skyloom references without alias tag."
  (let [(lower (string-lower content))]
    (if (string-contains? lower "skyloom")
        (string-contains? lower "alias")
        true)))

(df isValidYamlDescription? [(desc Str)] -> Bool
  :d "Enforces valid YAML syntax: plain scalars containing colons are rejected unless quoted or folded."
  (if (or (string-starts-with? desc ">-")
          (or (string-starts-with? desc "\"")
              (string-starts-with? desc "'")))
      true
      (not (string-contains? desc ": "))))

(df verifySkillRecord [(record SkillRecord)] -> Bool
  :d "Validates skill record integrity."
  (and (.-hasFrontmatter record)
       (and (.-isValid record)
            (and (isCleanOfLegacy? (.-description record))
                 (isValidYamlDescription? (.-description record))))))
