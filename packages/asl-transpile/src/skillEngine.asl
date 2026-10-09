(module asl-transpile/skillEngine :x [SkillTool SkillRule SkillManifest makeTool makeRule makeSkill emitSkill emitStub calcSavings] :i [])

(schema SkillTool (:f name Str) (:f command Str) (:f purpose Str) (:f savings Str))

(schema SkillRule (:f ruleType Str) (:f text Str))

(schema SkillManifest (:f name Str) (:f desc Str) (:f rules (List SkillRule)) (:f tools (List SkillTool)) (:f targets (List Str)))

fn makeTool name: Str command: Str purpose: Str savings: Str -> SkillTool
  (SkillTool :name name :command command :purpose purpose :savings savings)

fn makeRule ruleType: Str text: Str -> SkillRule
  (SkillRule :ruleType ruleType :text text)

fn makeSkill name: Str desc: Str rules: (List SkillRule) tools: (List SkillTool) targets: (List Str) -> SkillManifest
  (SkillManifest :name name :desc desc :rules rules :tools tools :targets targets)

fn emitSkill skill: SkillManifest -> Str
  (let [(head (str "---\n" "name: " skill.name "\n" "description: >-\n" "  " skill.desc "\n" "---\n\n" "# " skill.name ": Native Tooling & Verification Guide\n\n" "> [!IMPORTANT]\n" "> This skill is deterministically compiled from canonical ASN specification.\n\n" "## Rules of Engagement & Invariants\n\n")) (withRules (fold (fn [(acc Str) (r SkillRule)] -> Str (str acc "- **[" r.ruleType "]**: " r.text "\n")) head skill.rules)) (withToolsHdr (str withRules "\n## Tool Suite Reference\n\n" "| Command | Purpose | Token Savings |\n" "| :--- | :--- | :--- |\n")) (withTools (fold (fn [(acc Str) (t SkillTool)] -> Str (str acc "| `" t.command "` | " t.purpose " | **" t.savings "** |\n")) withToolsHdr skill.tools)) (withTargetsHdr (str withTools "\n## Supported Agent Harnesses\n\n")) (finalMd (fold (fn [(acc Str) (tgt Str)] -> Str (str acc "- `" tgt "`\n")) withTargetsHdr skill.targets))] finalMd)

fn emitStub skill: SkillManifest -> Str
  (let [(toolsCount (stringFromInt64 (listLength skill.tools))) (rulesCount (stringFromInt64 (listLength skill.rules)))] (str "(:skill-stub :name \"" skill.name "\"" " :rules-count " rulesCount " :tools-count " toolsCount " :desc \"" skill.desc "\")"))

fn calcSavings skill: SkillManifest -> F64
  (let [(md (emitSkill skill)) (stub (emitStub skill)) (mdLen (stringLength md)) (stubLen (stringLength stub))] (if (<= mdLen 0) 0.0 (let [(diff (- mdLen stubLen))] (if (<= diff 0) 0.0 (/ (* (int64ToFloat64 diff) 100.0) (int64ToFloat64 mdLen))))))
