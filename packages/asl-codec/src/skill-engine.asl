(module asl-codec/skill-engine
  :d "Pure AgentScript Dual-Projection Compiler: ASN Skill Specifications to Production Markdown & Dense Agent Stubs."
  :x [SkillTool SkillRule SkillManifest
      make-tool make-rule make-skill
      emit-skill emit-stub calc-savings]
  :i [])

(dfs SkillTool
  (:f name Str "Tool identifier e.g. asl-intel-outline")
  (:f command Str "Terminal command invocation e.g. asl rpc (:batch (:out file))")
  (:f purpose Str "Brief description of command utility")
  (:f savings Str "Token reduction percentage e.g. 94%"))

(dfs SkillRule
  (:f rule-type Str "Rule kind: negative, mandatory, workflow")
  (:f text Str "Instruction rule text"))

(dfs SkillManifest
  (:f name Str "Skill unique identifier")
  (:f desc Str "Skill description for YAML frontmatter")
  (:f rules (List SkillRule) "Ordered list of invariants and negative constraints")
  (:f tools (List SkillTool) "List of native tools provided by skill")
  (:f targets (List Str) "Target assistant harnesses: claude-code, factory-droid, antigravity"))

(df make-tool [(name Str) (command Str) (purpose Str) (savings Str)] -> SkillTool
  :d "Constructs a SkillTool record."
  (SkillTool
    :name name
    :command command
    :purpose purpose
    :savings savings))

(df make-rule [(rule-type Str) (text Str)] -> SkillRule
  :d "Constructs a SkillRule record."
  (SkillRule
    :rule-type rule-type
    :text text))

(df make-skill [(name Str) (desc Str) (rules (List SkillRule)) (tools (List SkillTool)) (targets (List Str))] -> SkillManifest
  :d "Constructs a SkillManifest record."
  (SkillManifest
    :name name
    :desc desc
    :rules rules
    :tools tools
    :targets targets))

(df emit-skill [(skill SkillManifest)] -> Str
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
        (with-rules (foldl (fn [(acc Str) (r SkillRule)] -> Str
                             (str acc "- **[" (.-rule-type r) "]**: " (.-text r) "\n"))
                           head
                           (.-rules skill)))
        (with-tools-hdr (str with-rules "\n## Tool Suite Reference\n\n"
                             "| Command | Purpose | Token Savings |\n"
                             "| :--- | :--- | :--- |\n"))
        (with-tools (foldl (fn [(acc Str) (t SkillTool)] -> Str
                             (str acc "| `" (.-command t) "` | " (.-purpose t) " | **" (.-savings t) "** |\n"))
                           with-tools-hdr
                           (.-tools skill)))
        (with-targets-hdr (str with-tools "\n## Supported Agent Harnesses\n\n"))
        (final-md (foldl (fn [(acc Str) (tgt Str)] -> Str
                           (str acc "- `" tgt "`\n"))
                         with-targets-hdr
                         (.-targets skill)))]
    final-md))

(df emit-stub [(skill SkillManifest)] -> Str
  :d "Compiles an ASN SkillManifest into ultra-compact ASN stub for context-efficient agent injection."
  (let [(tools-count (string-from-int64 (list-length (.-tools skill))))
        (rules-count (string-from-int64 (list-length (.-rules skill))))]
    (str "(:skill-stub :name \"" (.-name skill) "\""
         " :rules-count " rules-count
         " :tools-count " tools-count
         " :desc \"" (.-desc skill) "\")")))

(df calc-savings [(skill SkillManifest)] -> F64
  :d "Calculates the token economy compression ratio between full Markdown and ASN stub."
  (let [(md (emit-skill skill))
        (stub (emit-stub skill))
        (md-len (string-length md))
        (stub-len (string-length stub))]
    (if (<= md-len 0)
        0.0
        (let [(diff (- md-len stub-len))]
          (if (<= diff 0)
              0.0
              (/ (* (float-from-int64 diff) 100.0) (float-from-int64 md-len)))))))
