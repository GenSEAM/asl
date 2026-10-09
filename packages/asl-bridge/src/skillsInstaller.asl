(module asl-bridge/skillsInstaller :x [SkillManifest makeSkillManifest validateSkillFrontmatter resolveSkillManifest isValidFrontmatterDesc?] :i [])

(schema SkillManifest (:f name Str) (:f description Str) (:f path Str) (:f verified Bool))

fn makeSkillManifest name: Str description: Str path: Str verified: Bool -> SkillManifest
  (SkillManifest :name name :description description :path path :verified verified)

fn isValidFrontmatterDesc? rawText: Str -> Bool
  (if (stringContains? rawText "description: >-") true (if (stringContains? rawText "description: \"") true (if (stringContains? rawText "description: '") true (let [(lines (stringSplit rawText "\n")) (descLines (filter (fn [(l Str)] -> Bool (stringStartsWith? (stringTrim l) "description:")) lines))] (mt (listHead descLines) ((none) true) ((some dl) (let [(afterPrefix (optionOr (stringSlice dl 12 (stringLength dl)) ""))] (not (stringContains? afterPrefix ": ")))))))))

fn validateSkillFrontmatter rawText: Str -> Bool
  (and (stringStartsWith? rawText "---") (and (stringContains? rawText "\n---") (and (or (stringContains? rawText "description:") (stringContains? rawText "name:")) (isValidFrontmatterDesc? rawText))))

fn resolveSkillManifest skillName: Str path: Str -> SkillManifest
  (let [(valid (and (not (stringEmpty? skillName)) (not (stringEmpty? path)))) (desc (if valid (str "Skill manifest for " skillName) ""))] (SkillManifest :name skillName :description desc :path path :verified valid))
