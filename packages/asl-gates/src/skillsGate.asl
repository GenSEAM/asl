(module asl-gates/skillsGate :x [SkillRecord makeSkillRecord parseFrontmatterField verifySkillRecord isCleanOfLegacy? isValidYamlDescription? AsnSkillSpec makeAsnSkillSpec verifyAsnSkillSpec] :i [])

(schema AsnSkillSpec (:f name Str) (:f description Str) (:f rulesCount I64) (:f toolsCount I64))

fn makeAsnSkillSpec name: Str desc: Str rulesCnt: I64 toolsCnt: I64 -> AsnSkillSpec
  (AsnSkillSpec :name name :description desc :rulesCount rulesCnt :toolsCount toolsCnt)

fn verifyAsnSkillSpec spec: AsnSkillSpec -> Bool
  (and (> (stringLength spec.name) 0) (and (> (stringLength spec.description) 0) (and (> spec.rulesCount 0) (> spec.toolsCount 0))))

(schema SkillRecord (:f path Str) (:f name Str) (:f description Str) (:f hasFrontmatter Bool) (:f isValid Bool))

fn makeSkillRecord path: Str name: Str desc: Str hasFm: Bool -> SkillRecord
  (let [(valid (and hasFm (and (> (stringLength name) 0) (> (stringLength desc) 0))))] (SkillRecord :path path :name name :description desc :hasFrontmatter hasFm :isValid valid))

fn parseFrontmatterField content: Str prefix: Str -> Str
  (let [(lines (stringSplit content "\n")) (matched (filter (fn [(line Str)] -> Bool (stringStartsWith? (stringTrim line) prefix)) lines))] (mt (listHead matched) ((none) "") ((some l) (let [(trimmed (stringTrim l)) (val (optionOr (stringSlice trimmed (stringLength prefix) (stringLength trimmed)) ""))] (stringTrim val)))))

fn isCleanOfLegacy? content: Str -> Bool
  (let [(lower (stringLower content))] (if (stringContains? lower "skyloom") (stringContains? lower "alias") true))

fn isValidYamlDescription? desc: Str -> Bool
  (if (or (stringStartsWith? desc ">-") (or (stringStartsWith? desc "\"") (stringStartsWith? desc "'"))) true (not (stringContains? desc ": ")))

fn verifySkillRecord record: SkillRecord -> Bool
  (and record.hasFrontmatter (and record.isValid (and (isCleanOfLegacy? record.description) (isValidYamlDescription? record.description))))
