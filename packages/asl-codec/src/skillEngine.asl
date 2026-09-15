(module asl-codec/skillEngine
  :d "Pure AgentScript Dual-Projection Compiler: ASN Skill Specifications to Production Markdown & Dense Agent Stubs."
  :x [SkillTool SkillRule SkillManifest
      makeTool makeRule makeSkill
      emitSkill emitStub calcSavings]
  :i [])

(dfs SkillTool
  (:f name Str "Tool identifier e.g. asl-intel-outline")
  (:f command Str "Terminal command invocation e.g. asl rpc (:batch (:out file))")
  (:f purpose Str "Brief description of command utility")
  (:f savings Str "Token reduction percentage e.g. 94%"))

(dfs SkillRule
  (:f ruleType Str "Rule kind: negative, mandatory, workflow")
  (:f text Str "Instruction rule text"))

(dfs SkillManifest
  (:f name Str "Skill unique identifier")
  (:f desc Str "Skill description for YAML frontmatter")
  (:f rules (List SkillRule) "Ordered list of invariants and negative constraints")
  (:f tools (List SkillTool) "List of native tools provided by skill")
  (:f targets (List Str) "Target assistant harnesses: claude-code, factory-droid, antigravity"))

(df makeTool [(name Str) (command Str) (purpose Str) (savings Str)] -> SkillTool
  :d "Constructs a SkillTool record."
  (SkillTool
    :name name
    :command command
    :purpose purpose
    :savings savings))

(df makeRule [(ruleType Str) (text Str)] -> SkillRule
  :d "Constructs a SkillRule record."
  (SkillRule
    :ruleType ruleType
    :text text))

(df makeSkill [(name Str) (desc Str) (rules (List SkillRule)) (tools (List SkillTool)) (targets (List Str))] -> SkillManifest
  :d "Constructs a SkillManifest record."
  (SkillManifest
    :name name
    :desc desc
    :rules rules
    :tools tools
    :targets targets))

(df emitSkill [(skill SkillManifest)] -> Str
  :d "Compiles an ASN SkillManifest into published Markdown documentation with valid YAML frontmatter."
  (let [(head (str "---\n"
                   "name: " (.-name skill) "\n"
                   "description: >-\n"
                   "  " (.-desc skill) "\n"
                   "---\n\n"
                   "# " (.-name skill) ": Native Tooling & Verification Guide\n\n"
                   "> [!IMPORTANT]\n"
                   "> This skill is deterministically compiled from canonical ASN specification.\n\n"
                   "## Rules of Engagement & Invariants\n\n"))
        (withRules (foldl (fn [(acc Str) (r SkillRule)] -> Str
                             (str acc "- **[" (.-ruleType r) "]**: " (.-text r) "\n"))
                           head
                           (.-rules skill)))
        (withToolsHdr (str withRules "\n## Tool Suite Reference\n\n"
                             "| Command | Purpose | Token Savings |\n"
                             "| :--- | :--- | :--- |\n"))
        (withTools (foldl (fn [(acc Str) (t SkillTool)] -> Str
                             (str acc "| `" (.-command t) "` | " (.-purpose t) " | **" (.-savings t) "** |\n"))
                           withToolsHdr
                           (.-tools skill)))
        (withTargetsHdr (str withTools "\n## Supported Agent Harnesses\n\n"))
        (finalMd (foldl (fn [(acc Str) (tgt Str)] -> Str
                           (str acc "- `" tgt "`\n"))
                         withTargetsHdr
                         (.-targets skill)))]
    finalMd))

(df emitStub [(skill SkillManifest)] -> Str
  :d "Compiles an ASN SkillManifest into ultra-compact ASN stub for context-efficient agent injection."
  (let [(toolsCount (string-from-int64 (list-length (.-tools skill))))
        (rulesCount (string-from-int64 (list-length (.-rules skill))))]
    (str "(:skill-stub :name \"" (.-name skill) "\""
         " :rules-count " rulesCount
         " :tools-count " toolsCount
         " :desc \"" (.-desc skill) "\")")))

(df calcSavings [(skill SkillManifest)] -> F64
  :d "Calculates the token economy compression ratio between full Markdown and ASN stub."
  (let [(md (emitSkill skill))
        (stub (emitStub skill))
        (mdLen (string-length md))
        (stubLen (string-length stub))]
    (if (<= mdLen 0)
        0.0
        (let [(diff (- mdLen stubLen))]
          (if (<= diff 0)
              0.0
              (/ (* (float-from-int64 diff) 100.0) (float-from-int64 mdLen)))))))
