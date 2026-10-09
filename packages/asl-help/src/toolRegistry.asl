(module asl-help/toolRegistry
  :x [canonicalTools catalogSize catalogDigest lookupTool formatCatalogSummary formatToolDeepByName helpTool!]
  :i [(toolDescriptor :a td)])

fn canonicalTools -> (List td/ToolDescriptor)
  (list
    (td/makeToolDescriptor
      "query"
      "vector semantic search AST"
      "(:query <text> [:scope <s>] [:limit <n>])"
      "Sub-15ms BM25 and cosine ranking across AST symbols and ledgers without loading whole files"
      (list "find" "orient" "research")
      (list
        (td/makeToolParameter "text" "Str" true "Symbol name or semantic query terms")
        (td/makeToolParameter "scope" "Keyword" false "Search partition (:workspace, :packages, :decisions, :tasks)")
        (td/makeToolParameter "limit" "I64" false "Max matched results, default 20"))
      "(:receipt :op \"query\" :status \"ok\" :results (...) :count <n>)"
      "Turn 0 exploration, locating definitions, finding identifier references"
      "Do not use when the exact file path and symbol are already known; use (:read) directly"
      (list ":ERR_EMPTY_QUERY" ":ERR_INVALID_SCOPE")
      "(:query \"assemblePackage\" :scope :packages :limit 10)")

    (td/makeToolDescriptor
      "read"
      "bounded AST slice retrieval"
      "(:read :file <path> [:symbol <s>] [:anchor <a>] [:limit <n>])"
      "Targeted code and AST slice reading bounded by symbol anchor"
      (list "read" "understand")
      (list
        (td/makeToolParameter "file" "Str" true "Path to target file")
        (td/makeToolParameter "symbol" "Str" false "AST function, schema, or type name to read")
        (td/makeToolParameter "anchor" "Str" false "Anchor text or symbol slice to match")
        (td/makeToolParameter "limit" "I64" false "Maximum line or entry count"))
      "(:receipt :op \"read\" :status \"ok\" :file <f> :lines <n> :content <text>)"
      "Inspecting target functions, schemas, or specific bounded slices"
      "Never request whole large files without a bound; line numbers without anchors forbidden"
      (list ":ERR_FILE_NOT_FOUND" ":ERR_SYMBOL_NOT_FOUND")
      "(:read :file \"asl/packages/asl-pack/src/packaging.asl\" :symbol \"assemblePackage\")")

    (td/makeToolDescriptor
      "edit"
      "stage atomic string replacement"
      "(:edit :file <path> :old <target> :new <replacement>)"
      "Virtual RAM buffer staging; isolated from disk until verified"
      (list "change" "implement")
      (list
        (td/makeToolParameter "file" "Str" true "Path to target file within declared :owns")
        (td/makeToolParameter "old" "Str" true "Exact matching target substring")
        (td/makeToolParameter "new" "Str" true "Replacement content"))
      "(:receipt :op \"edit\" :status \"ok\" :file <f> :staged true :bufferId <id>)"
      "Staging modifications in RAM VFS buffers before disk commit"
      "Do not use raw disk writes; all edits must be staged and reviewed via (:diff)"
      (list ":ERR_TARGET_NOT_FOUND" ":ERR_AMBIGUOUS_MATCH" ":ERR_OUTSIDE_OWNS")
      "(:edit :file \"src/main.asl\" :old \"let x = 1\" :new \"let x = 2\")")

    (td/makeToolDescriptor
      "diff"
      "inspect staged RAM diffs"
      "(:diff [:file <path>])"
      "Inspect pending modifications and unified diffs in memory prior to disk commit"
      (list "change" "verify")
      (list
        (td/makeToolParameter "file" "Str" false "Optional file filter"))
      "(:receipt :op \"diff\" :status \"ok\" :dirtyFiles (...) :diffs (...))"
      "Verifying staged edits before executing (:flush)"
      "Unnecessary when no buffers are staged"
      (list ":ERR_NO_DIRTY_BUFFERS")
      "(:diff)")

    (td/makeToolDescriptor
      "flush"
      "persist staged edits disk"
      "(:flush)"
      "Atomically persist staged modifications to disk (fsync + rename)"
      (list "change" "implement")
      (list)
      "(:receipt :op \"flush\" :status \"ok\" :flushedCount <n> :activeBuffers 0)"
      "Persisting verified in-memory edits to disk after checking syntax"
      "Never flush broken or unverified edits that fail delimiter checks"
      (list ":ERR_DISK_WRITE_FAILED" ":ERR_PERMISSION_DENIED")
      "(:flush)")

    (td/makeToolDescriptor
      "discard"
      "clear staged RAM buffers"
      "(:discard)"
      "Clear pending RAM modifications with zero disk side-effects"
      (list "recover" "rollback")
      (list)
      "(:receipt :op \"discard\" :status \"ok\" :discardedCount <n> :activeBuffers 0)"
      "Rolling back speculative or failing in-memory edits cleanly"
      "Do not discard if changes should be preserved"
      (list)
      "(:discard)")

    (td/makeToolDescriptor
      "tree"
      "render dense structural hierarchy"
      "(:tree [:path <path>] [:depth <n>])"
      "Structural hierarchy and package telemetry across codebase"
      (list "orient" "find")
      (list
        (td/makeToolParameter "path" "Str" false "Root directory, default '.'")
        (td/makeToolParameter "depth" "I64" false "Max traversal depth, default 3"))
      "(:receipt :op \"tree\" :status \"ok\" :path <p> :nodes (...))"
      "Navigating repository directory structure and package organization"
      "Unbounded traversals on deep vendor trees"
      (list ":ERR_DIR_NOT_FOUND")
      "(:tree :path \"asl/packages\" :depth 2)")

    (td/makeToolDescriptor
      "doc"
      "read section without disk"
      "(:doc :file <path> :section <title>)"
      "Extract markdown and doc sections directly from in-memory AST"
      (list "read" "understand")
      (list
        (td/makeToolParameter "file" "Str" true "Markdown or documentation file path")
        (td/makeToolParameter "section" "Str" true "Heading title to extract"))
      "(:receipt :op \"doc\" :status \"ok\" :file <f> :heading <h> :content <text>)"
      "Reading specifications, ADRs, or architectural guides by heading"
      "Reading non-markdown source code (use :read instead)"
      (list ":ERR_SECTION_NOT_FOUND")
      "(:doc :file \"AGENTS.md\" :section \"Core Affordances\")")

    (td/makeToolDescriptor
      "check"
      "verify delimiter & syntax integrity"
      "(:check [:file <path>])"
      "Formal Dyck-1 delimiter balance and compiler diagnostic validation"
      (list "verify")
      (list
        (td/makeToolParameter "file" "Str" false "Target file to verify, default asl/grammar/rules.asn"))
      "(:receipt :op \"check\" :status \"ok\" :file <f> :clean true)"
      "Verifying delimiter balance and syntax integrity before running tests"
      "Logic validation (use :test instead)"
      (list ":ERR_SYNTAX_ERROR" ":ERR_DELIMITER_MISMATCH")
      "(:check :file \"asl/packages/asl-pack/src/packaging.asl\")")

    (td/makeToolDescriptor
      "test"
      "execute assertions under verification"
      "(:test [:file <path>])"
      "Popperian gate execution with strictly positive assertion counts"
      (list "verify" "grade")
      (list
        (td/makeToolParameter "file" "Str" true "Path to test suite file"))
      "(:receipt :op \"test\" :status \"ok\" :file <f> :assertions <n> :refutations <m> :killedMutants <k>)"
      "Running unit and integration tests; verifying assertCount > 0"
      "Do not accept exit 0 without confirming positive assertCount"
      (list ":ERR_ASSERTION_FAILED" ":ERR_ZERO_ASSERTIONS" ":ERR_MUTANT_SURVIVED")
      "(:test :file \"asl/packages/asl-pack/tests/packagingTest.asl\")")

    (td/makeToolDescriptor
      "gate"
      "execute pure verification gate suite"
      "(:gate [:suite <name>] [:files (...)])"
      "Execute monorepo verification gates (1-7) across packages"
      (list "verify" "grade")
      (list
        (td/makeToolParameter "suite" "Keyword" false "Gate suite: :sevenGates, :consistency, :foreign")
        (td/makeToolParameter "files" "List Str" false "Optional file targets"))
      "(:receipt :op \"gate\" :status \"ok\" :total 7 :passed 7 :allClean true)"
      "Phase boundary audits and pre-commit verification"
      "Isolated single-function testing"
      (list ":ERR_GATE_FAILED")
      "(:gate :suite :sevenGates)")

    (td/makeToolDescriptor
      "doctor"
      "audit measured capabilities & invariants"
      "(:doctor)"
      "Audit physical capability measurements and refresh capabilities.lock"
      (list "orient" "observe")
      (list)
      "(:receipt :op \"doctor\" :status \"ok\" :capabilitiesLock \"updated\" :measuredStatus (...))"
      "Verifying environmental trust and determining working vs absent capabilities"
      "Inside active edit transactions"
      (list ":ERR_CAPABILITY_CONTRADICTION")
      "(:doctor)")

    (td/makeToolDescriptor
      "pack"
      "assemble & package target artifacts"
      "(:pack [:target <t>] [:profile <p>] [:variation <v>])"
      "Multi-platform packaging (macOS, Debian, Fedora, Windows, WASM) and dual-binary assembly"
      (list "plan" "implement")
      (list
        (td/makeToolParameter "target" "Keyword" false "Target OS: :macos, :debian, :fedora, :windows, :wasm")
        (td/makeToolParameter "profile" "Keyword" false "Distribution profile: :core, :full, :browser")
        (td/makeToolParameter "variation" "Str" false "Variation: 'debug' or 'release'"))
      "(:receipt :op \"pack\" :status \"ok\" :target <t> :profile <p> :output <path> :sha256 <hash>)"
      "Building and bundling release packages and distribution profiles"
      "Quick syntax checks"
      (list ":ERR_COMPILATION_FAILED" ":ERR_TARGET_UNSUPPORTED")
      "(:pack :target :macos :profile :full)")

    (td/makeToolDescriptor
      "consilium"
      "consult multi-LLM frontier council"
      "(:consilium :target <t> [:council (...)] [:threshold <n>])"
      "2-stage Popperian deliberation across Flagship Trio (gpt-6-astra, deepseek-v4.1-flash, glm-5.3)"
      (list "plan" "understand" "verify")
      (list
        (td/makeToolParameter "target" "Str" true "Target artifact, specification, or question")
        (td/makeToolParameter "council" "List Str" false "Model council, default Flagship Trio")
        (td/makeToolParameter "threshold" "Float" false "Consensus quorum threshold, default 0.75"))
      "(:receipt :op \"consilium\" :status \"ok\" :council (...) :consensusQuorum 0.75 :status :certified)"
      "Resolving architectural ambiguities, cross-cutting migrations, eliminating single-model bias"
      "Trivial local syntax edits or deterministic compiler checks"
      (list ":ERR_CONSENSUS_NOT_REACHED" ":ERR_MODEL_UNAVAILABLE")
      "(:consilium :target \"asl/packages/asl-ir/src/ir.asl\")")

    (td/makeToolDescriptor
      "lens"
      "discover & execute multi-lens audit probes"
      "(:lens [:target <t>] [:lenses (...)])"
      "Discover and launch parallel subagent audits with focused perspective attractors"
      (list "verify" "grade")
      (list
        (td/makeToolParameter "target" "Str" false "Target file, diff, or plan")
        (td/makeToolParameter "lenses" "List Str" false "Specific lens IDs to probe"))
      "(:receipt :op \"lens\" :status \"ok\" :activeLenses (...) :count <n>)"
      "Pre-commit and post-implementation multi-perspective vetting across all 10 lenses"
      "Running single unit tests"
      (list ":ERR_LENS_DEFECTS_FOUND")
      "(:lens :target \"asl/packages/asl-pack/src/packaging.asl\")")

    (td/makeToolDescriptor
      "note"
      "manage working memory & architectural findings"
      "(:note <:write|:query|:list> [:title <t>] [:content <c>])"
      "Record and query non-reconstructible working memory and architectural findings"
      (list "orient" "observe" "handoff")
      (list
        (td/makeToolParameter "action" "Keyword" true ":write, :query, or :list")
        (td/makeToolParameter "title" "Str" false "Note title")
        (td/makeToolParameter "content" "Str" false "Note content"))
      "(:receipt :op \"note\" :status \"ok\" :source \".asl/mem/notes.asn\" :active <n>)"
      "Recording architectural discoveries that would otherwise be lost across turns"
      "Do not record reconstructible data (git log, command output, file status)"
      (list ":ERR_RECONSTRUCTIBLE_REFUSED")
      "(:note :write :title \"packaging\" :content \"All emitters enforce pure Dyck-1\")")

    (td/makeToolDescriptor
      "where"
      "deliver situation slice & active invariants"
      "(:where [:situation <s>])"
      "Inspect current situation, active invariants (V0-V6, C1-C5), and recommended tools"
      (list "orient" "all")
      (list
        (td/makeToolParameter "situation" "Str" false "Optional situation: orient, find, read, understand, plan, change, verify, recover, handoff, observe"))
      "(:receipt :op \"where\" :status \"ok\" :situation <s> :invariants (...) :recommendedTools (...))"
      "Call before every mutation and after every gate to re-anchor situation and plan context"
      "Never bypass when off-plan or uncertain"
      (list ":ERR_UNKNOWN_SITUATION")
      "(:where :situation \"change\")")

    (td/makeToolDescriptor
      "tools"
      "query tool self-descriptions, signatures & situational contracts"
      "(:tools [:tool \"<name>\"])"
      "Two-tier tool introspection: compact catalog index (<= 250 tokens) or deep self-description"
      (list "orient" "all")
      (list
        (td/makeToolParameter "tool" "Str" false "Optional tool name for deep descriptor: query, read, edit, diff, flush, etc."))
      "(:receipt :op \"tools\" :status \"ok\" :catalogDigest \"sha256-...\" :catalog (...) | :tool (...))"
      "Discovering tool affordances, inspecting parameter contracts, and learning operational rules"
      "Do not poll in tight loops; query once and cache in memory"
      (list ":ERR_UNKNOWN_TOOL")
      "(:tools :tool \"query\")")

    (td/makeToolDescriptor
      "relay"
      "proxy relay & external agent gateway"
      "(:relay [:preset <p>] [:prompt <text>] [:worker <w>] [:mode <m>] [:temp <t>])"
      "Sovereign proxy relay dispatching queries to external LLMs, Frontier Council, or CLI agents"
      (list "orient" "plan" "verify" "implement")
      (list
        (td/makeToolParameter "preset" "Str" false "Preset: consilium, consult, audit, codex, claude, agy, delegation")
        (td/makeToolParameter "prompt" "Str" true "Query, specification path, or task instructions")
        (td/makeToolParameter "worker" "Str" false "Worker engine: agy, codex, claude, proxy")
        (td/makeToolParameter "mode" "Keyword" false "Execution character: :consult or :action")
        (td/makeToolParameter "temp" "Float" false "Sampling temperature override"))
      "(:receipt :op \"relay\" :status \"ok\" :preset <p> :character <c> :response <text>)"
      "External model consultation, cross-lab consensus deliberation, or delegating work to external CLI workers"
      "Local analytical inspections or static AST linting; use (:lens) for local multi-lens probes"
      (list ":ERR_PRESET_NOT_FOUND" ":ERR_WORKER_UNAVAILABLE")
      "(:relay :preset \"consult\" :prompt \"Explain Dyck-1 sound bracket matching\")")

    (td/makeToolDescriptor
      "mesh"
      "autonomous multi-agent mesh & shard daemon"
      "(:mesh [:action <a>] [:shard <s>] [:daemon <bool>])"
      "Universal Autonomous Agent Mesh: model-blind intent routing, 24/7 defect blackboard, and daemon orchestration"
      (list "orient" "plan" "verify" "all")
      (list
        (td/makeToolParameter "action" "Str" false "Action: status, sweep, worker, daemon, queue, blackboard")
        (td/makeToolParameter "shard" "Str" false "Target exploration shard: syntax, gates, foreign, consistency, invariants")
        (td/makeToolParameter "daemon" "Bool" false "True to run single-process continuous supervisor daemon"))
      "(:receipt :op \"mesh\" :status \"ok\" :shards <n> :defects <d> :daemon <state>)"
      "Autonomous 24/7 background inspection, blackboard gap tracking, and swarm deliberation"
      "Direct deterministic single-file checks; use (:check) or (:gate) for immediate local operations"
      (list ":ERR_SHARD_NOT_FOUND" ":ERR_DAEMON_CRASHED")
      "(:mesh :action \"status\")")

    (td/makeToolDescriptor
      "preflush"
      "in-engine RAM VFS pre-flush gate"
      "(:preflush [:file <path>] [:owns [...]] [:gates [...]] [:critic <:none|:advisory|:strict>])"
      "Validate staged RAM buffers for Dyck-1 balance, AST structure, and boundary confinement prior to disk commit"
      (list "verify" "implement" "change")
      (list
        (td/makeToolParameter "file" "Str" false "Optional file path to validate")
        (td/makeToolParameter "owns" "List" false "Declared write set boundary")
        (td/makeToolParameter "gates" "List" false "Executable verification gates to evaluate")
        (td/makeToolParameter "critic" "Keyword" false "Critic evaluation mode: :none, :advisory, :strict"))
      "(:receipt :op \"preflush\" :status \"ok\" :canFlush true :checksPassed [...])"
      "Mandatory pre-flush validation step before committing in-memory modifications to physical disk"
      "Do not use before edits are staged in RAM; use (:edit) first"
      (list ":ERR_SYNTAX_MALFORMATION" ":ERR_BOUNDARY_VIOLATION" ":ERR_GATE_FAILED")
      "(:preflush :file \"src/main.asl\" :critic :advisory)")

    (td/makeToolDescriptor
      "consult"
      "non-mutating consultative probe"
      "(:consult :prompt <p> [:target <t>] [:symbol <s>] [:role <r>] [:lens <l>])"
      "Query consultative critic or peer reviewer for non-mutating feedback on code, diffs, or invariants"
      (list "orient" "plan" "verify" "research")
      (list
        (td/makeToolParameter "prompt" "Str" true "Consultative question or review objective")
        (td/makeToolParameter "target" "Str" false "Target file or symbol anchor")
        (td/makeToolParameter "symbol" "Str" false "AST symbol identifier")
        (td/makeToolParameter "role" "Keyword" false "Semantic critic role (:falsifier, :shadowCritic, :planner)")
        (td/makeToolParameter "lens" "Keyword" false "Evaluation lens (:falsification, :concurrency, :invariants)"))
      "(:receipt :op \"consult\" :status \"ok\" :critic <c> :role <r> :verdict <v> :confidence <float>)"
      "Seeking external perspective, sanity checks, or adversarial refutations without altering state"
      "Do not use for code mutations or deterministic syntax checks; use (:preflush) or (:edit)"
      (list ":ERR_MISSING_ARG" ":ERR_CRITIC_FAILED")
      "(:consult :prompt \"Verify invariant preservation\" :target \"batch.asl#execute\" :role :falsifier)"))

fn catalogSize -> I64
  22

fn catalogDigest -> Str
  "d81-tools-v1-600-canonical"

fn lookupTool name: Str -> (Option td/ToolDescriptor)
  (if (stringEmpty? name)
    (none)
    (let [(tools (canonicalTools))]
      (fold (fn [(acc (Option td/ToolDescriptor)) (tool td/ToolDescriptor)] -> (Option td/ToolDescriptor)
              (if (some? acc)
                acc
                (if (= tool.name name)
                  (some tool)
                  (none))))
            (none)
            tools)))

fn formatCatalogSummary -> Str
  (let [(tools (canonicalTools))]
    (str "(:receipt :op \"tools\" :status \"ok\" :total " (stringFromInt64 (listLength tools)) " :catalogDigest \"" (catalogDigest) "\" :catalog ("
         (stringJoin (map (fn [(tool td/ToolDescriptor)] -> Str (td/formatToolCompact tool)) tools) " ")
         "))"))

fn formatToolDeepByName name: Str -> Str
  (let [(opt (lookupTool name))]
    (if (none? opt)
      (str "(:receipt :op \"tools\" :status \"error\" :code \":ERR_UNKNOWN_TOOL\" :message \"Unknown tool: " name "\")")
      (str "(:receipt :op \"tools\" :status \"ok\" :tool " (td/formatToolDeep (optionOr opt (td/makeToolDescriptor "" "" "" "" (list) (list) "" "" "" (list) ""))) ")")))

fn helpTool! name: Str -> Str
  (if (stringEmpty? name)
    (formatCatalogSummary)
    (formatToolDeepByName name))
