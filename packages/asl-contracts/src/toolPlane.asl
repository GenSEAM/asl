(module aslContracts/toolPlane :x [ToolSafety ToolDescriptor SecretRef ToolRunbook ToolScopeContext safetySafe safetyGuarded safetyDangerous makeSecretRef makeToolDescriptor makeRunbook makeScopeContext isToolInScope? isAgentAuthorized? isSafetyPermitted? maskToolSecrets validateToolDescriptor toolMemQuery toolMemEdit toolMemDiff toolMemFlush toolMemDiscard toolMemWrite toolMemDoc toolMemTree canonicalMemToolDescriptors] :i [])

(enum ToolSafety (:c safetySafe [] "Auto-run tool with zero mutation risk or isolated read-only sandbox") (:c safetyGuarded [] "Tool requires workspace sandbox boundary enforcement") (:c safetyDangerous [] "Destructive or privileged tool requiring operator confirmation"))

(schema SecretRef (:f key Str) (:f source Str) (:f ref Str) (:f fallback Str))

(schema ToolRunbook (:f id Str) (:f title Str) (:f steps (List Str)))

(schema ToolDescriptor (:f id Str) (:f name Str) (:f doc Str) (:f guidance Str) (:f scope (List Str)) (:f agents (List Str)) (:f safety ToolSafety) (:f cmd Str) (:f args (List Str)) (:f env (Map Str Str)) (:f secrets (List SecretRef)) (:f redacted Bool))

(schema ToolScopeContext (:f activeRepo Str) (:f agentRole Str) (:f safetyCeiling ToolSafety))

fn makeSecretRef key: Str source: Str ref: Str fallback: Str -> SecretRef
  (SecretRef :key key :source source :ref ref :fallback fallback)

fn makeRunbook id: Str title: Str steps: (List Str) -> ToolRunbook
  (ToolRunbook :id id :title title :steps steps)

fn makeToolDescriptor id: Str name: Str doc: Str guidance: Str scope: (List Str) agents: (List Str) safety: ToolSafety cmd: Str args: (List Str) env: (Map Str Str) secrets: (List SecretRef) -> ToolDescriptor
  (ToolDescriptor :id id :name name :doc doc :guidance guidance :scope scope :agents agents :safety safety :cmd cmd :args args :env env :secrets secrets :redacted false)

fn makeScopeContext activeRepo: Str agentRole: Str safetyCeiling: ToolSafety -> ToolScopeContext
  (ToolScopeContext :activeRepo activeRepo :agentRole agentRole :safetyCeiling safetyCeiling)

fn isToolInScope? tool: ToolDescriptor repo: Str -> Bool
  (let [(scopes tool.scope)] (or (listContains? scopes "*") (or (listContains? scopes "all") (fold (fn [(acc Bool) (s Str)] -> Bool (or acc (and (not (= s "")) (or (= repo s) (stringStartsWith? repo (str s "/")))))) false scopes))))

fn isAgentAuthorized? tool: ToolDescriptor role: Str -> Bool
  (let [(allowed tool.agents)] (or (listContains? allowed "*") (listContains? allowed role)))

fn isSafetyPermitted? tool: ToolDescriptor ceiling: ToolSafety -> Bool
  (mt tool.safety ((safetySafe) true) ((safetyGuarded) (mt ceiling ((safetySafe) false) (_ true))) ((safetyDangerous) (mt ceiling ((safetyDangerous) true) (_ false))))

fn maskToolSecrets tool: ToolDescriptor -> ToolDescriptor
  (let [(maskedEnv (mapEmpty))] (with tool :env maskedEnv :secrets (map (fn [(s SecretRef)] -> SecretRef (SecretRef :key s.key :source s.source :ref "***" :fallback "***")) tool.secrets) :redacted true))

fn validateToolDescriptor tool: ToolDescriptor -> Bool
  (and (not (= tool.id "")) (and (not (= tool.cmd "")) (and (> (listLength tool.scope) 0) (and (not (listContains? tool.scope "")) (and (not (= tool.name "")) (not (listContains? tool.agents "")))))))

fn toolMemQuery -> ToolDescriptor
  (makeToolDescriptor "mem.query" "mem.query" "vector semantic search AST" "Vector semantic search across AST docstrings, decisions, and codebase" (list "*") (list "*") (safetySafe) "asl" (list "mem" "query") (mapEmpty) (list))

fn toolMemEdit -> ToolDescriptor
  (makeToolDescriptor "mem.edit" "mem.edit" "stage atomic string replacement" "Stage in-memory atomic string replacement in RAM virtual file buffer" (list "*") (list "*") (safetyGuarded) "asl" (list "mem" "edit") (mapEmpty) (list))

fn toolMemDiff -> ToolDescriptor
  (makeToolDescriptor "mem.diff" "mem.diff" "inspect staged RAM diffs" "Inspect staged in-memory modifications and dirty buffers before disk write" (list "*") (list "*") (safetySafe) "asl" (list "mem" "diff") (mapEmpty) (list))

fn toolMemFlush -> ToolDescriptor
  (makeToolDescriptor "mem.flush" "mem.flush" "persist staged edits disk" "Atomically persist staged in-memory edits to the physical filesystem" (list "*") (list "*") (safetyGuarded) "asl" (list "mem" "flush") (mapEmpty) (list))

fn toolMemDiscard -> ToolDescriptor
  (makeToolDescriptor "mem.discard" "mem.discard" "clear staged RAM buffers" "Clear staged RAM modifications without modifying physical disk files" (list "*") (list "*") (safetyGuarded) "asl" (list "mem" "discard") (mapEmpty) (list))

fn toolMemWrite -> ToolDescriptor
  (makeToolDescriptor "mem.write" "mem.write" "append durable memory ledger" "Append structured memory record to canonical workspace ledgers" (list "*") (list "*") (safetyGuarded) "asl" (list "mem" "write") (mapEmpty) (list))

fn toolMemDoc -> ToolDescriptor
  (makeToolDescriptor "mem.doc" "mem.doc" "read section without disk" "Extract and read targeted documentation section without whole-file dump" (list "*") (list "*") (safetySafe) "asl" (list "mem" "doc") (mapEmpty) (list))

fn toolMemTree -> ToolDescriptor
  (makeToolDescriptor "mem.tree" "mem.tree" "render holistic hierarchy telemetry" "Render dense structural telemetry of multi-tier memory hierarchy across packages" (list "*") (list "*") (safetySafe) "asl" (list "mem" "tree") (mapEmpty) (list))

fn canonicalMemToolDescriptors -> (List ToolDescriptor)
  (list (toolMemQuery) (toolMemEdit) (toolMemDiff) (toolMemFlush) (toolMemDiscard) (toolMemWrite) (toolMemDoc) (toolMemTree))
