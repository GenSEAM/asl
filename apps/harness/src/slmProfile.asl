(module aslHarness/slmProfile :x [SlmTool SlmRequest makeSlmEssentialTools filterToolSchema formatSlmRequest] :i [])

(schema SlmTool (:f name Str) (:f description Str) (:f parametersSummary Str))

(schema SlmRequest (:f model Str) (:f systemPrompt Str) (:f tools (List SlmTool)) (:f temperature F64) (:f maxTokens I64))

fn makeSlmEssentialTools -> (List SlmTool)
  (let [(tProbe (SlmTool :name "probe" :description "Inspect symbols, outlines, and file content" :parametersSummary "(:path Str [:symbol Str])")) (tPatch (SlmTool :name "patch" :description "Stage surgical in-memory AST or text replacements" :parametersSummary "(:path Str :old Str :new Str)")) (tGate (SlmTool :name "gate" :description "Run verification gate command or test suite" :parametersSummary "(:cmd Str)")) (tDone (SlmTool :name "done" :description "Declare task complete with physical receipt" :parametersSummary "(:receipt Str)"))] (list tProbe tPatch tGate tDone))

fn filterToolSchema tools: (List SlmTool) allowedNames: (List Str) -> (List SlmTool)
  (fold (fn [(acc (List SlmTool)) (t SlmTool)] -> (List SlmTool) (if (listContains? allowedNames t.name) (listAppend acc (list t)) acc)) (list) tools)

fn formatSlmRequest req: SlmRequest -> Str
  (let [(toolsList req.tools) (toolsFormatted (fold (fn [(acc Str) (t SlmTool)] -> Str (let [(line (str "    (:tool :name \"" t.name "\" :params \"" t.parametersSummary "\")"))] (if (stringEmpty? acc) line (str acc "\n" line)))) "" toolsList))] (str "(:slm-request\n" "  :model \"" req.model "\"\n" "  :system \"" req.systemPrompt "\"\n" "  :temperature " (stringFromFloat64 req.temperature) "\n" "  :max-tokens " (stringFromInt64 req.maxTokens) "\n" "  :tools [\n" toolsFormatted "\n" "  ])"))
