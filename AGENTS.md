<!-- ASL_TOOLBELT_START -->
# AgentScript (ASL) Universal Toolbelt

When `asl` is available on the host system, agents can execute high-speed, token-efficient workspace operations via `asl '(<form1> <form2> ...)'`:

- **Introspect Tool Schemas**: `asl '(:tools)'` — returns the authoritative machine-readable catalog of operational Pure-ASN S-expressions.
- **Fast Semantic & Symbol Search**: `asl '(:query "symbolName")'` — sub-15ms BM25 and symbol index search across the codebase.
- **Targeted Reading**: `asl '(:read :file "path/to/file.ext" :symbol "funcName")'` — bounded AST slice retrieval without whole-file dumping.
- **Safe Staged Editing**:
  - `asl '(:edit :file "path/to/file.ext" :old "exactOldString" :new "exactNewString")'` — stage changes in RAM VFS buffer.
  - `asl '(:diff)'` — inspect dirty RAM buffer diffs prior to disk commit.
  - `asl '(:flush)'` — atomically persist staged modifications to disk with fsync and rename.
  - `asl '(:discard)'` — clear all pending staged modifications without disk side effects.
- **Daemon & Process Supervision**: `asl '(:manage :action <:spawn|:poll|:tail|:kill|:list> :id "taskId" ...)'` (or alias `(:proc ...)`).
- **Multi-Lens Code Audit**: `asl '(:lens :file "path" :lenses ("invariants" "architecture"))'`
- **Web Distillation & Research**:
  - `asl '(:crawl :url "https://..." :distill :asn)'` — crawl and distill web DOM directly to dense ASN.
  - `asl '(:search :query "query" :limit 5)'` — cognitive web search.
  - `asl '(:research :topic "topic" :depth :deep)'` — web research through the gateway; `:depth` is `:flash`, `:deep` or `:exhaustive`.
- **Compound Batching**: Multiple forms execute concurrently in one roundtrip: `asl '(:query "foo") (:read :file "bar.ts")'`.

<!-- ASL_TOOLBELT_END -->

# ASL Engine Internal Operational Instructions

> [!NOTE]
> This guide covers ASL runtime internals. For the global autonomous agent teleological mandates, please refer to the root `/AGENTS.md` file.

> [!CAUTION]
> ### 🛑 Standalone ASL Repository Boundary & Workspace Isolation (CRITICAL)
> **The GitHub repository `git@github.com:GenSEAM/asl.git` is dedicated EXCLUSIVELY to the `asl` package.**
> 1. The root of `GenSEAM/asl` corresponds directly to this `asl/` directory (package.json, bin, grammar, packages, prelude, tools, web).
> 2. The local workspace is an un-pushed monorepo with zero remotes.
> 3. NEVER push the workspace monorepo or its parent tree to `GenSEAM/asl`. Only clean ASL package trees are published here.

> **Foundational Philosophy & Invariants**: All AI agents operating in this workspace MUST adhere strictly to [**`MANIFESTO.md`**](../MANIFESTO.md) and its 8 core pillars:
> 1. **LLM-Native Code Generation**: Homogeneous S-expression geometry, closed AST vocabulary, and balanced form semantics.
> 2. **Mathematical Optimality & Token Density**: Extreme BPE subtoken efficiency (<= 2 tokens per primitive) without lossy disemvoweling.
> 3. **Zero-Foreign-Code Invariant**: 100% pure AgentScript (.asl/.asn) in code packages. Zero Python/JS/TS/Rust/C in core logic.
> 4. **Dual-Projection Architecture**: Code is machine-native; human engineering operates via architecture DAGs, contracts, and falsifiable proofs.
> 5. **Atomic In-Memory Compound Tooling**: Mandatory pure-ASN S-expression execution via `asl '(:tools)'` and compound top-level batches with zero unvalidated shell commands.
> 6. **Multi-Runtime Orchestration**: AgentScript acts as the universal control plane coordinating Python AI/ML, Node.js/V8, Rust, C, WASM, and WebGPU via strict ASN stage contracts.
> 7. **Falsifiable Verification**: Zero vacuous passes, strict exit code validation, and separation of duties between authors and reviewers.

## 1. Core Technical Specifications
- Consult `AGENT_SPEC_CORE.md` as the normative language specification.
- Consult `ROADMAP.md` for current milestone status and active implementation goals.
- Maintain single-source-of-truth definitions in `prelude/prelude.json` for all closed vocabulary and projection tables.

## 2. Verification Toolchain & Continuous Audit Gates
Verify all changes using the native sovereign ASL CLI before committing:

```bash
asl gate
```

The verification suite evaluates seven gates:
1. **Manifest Integrity**: Validates package manifests and module structure across all packages.
2. **Structural Balance**: Verifies pure ASL syntax and S-expression form balance across all `.asl` files.
3. **Registry Grounding**: Verifies published benchmark claims against the benchmark registry.
4. **Pure AgentScript Implementation**: Confirms that code packages contain pure AgentScript modules.
5. **Native Test Execution**: Runs native ASL test suites across packages.
6. **ASN Grammar & Symbol Density**: Verifies symbol registries, token budget limits (<= 2 tokens under BPE), and unambiguous canonical naming.
7. **Modular Skills Freshness**: Confirms skill frontmatters, trigger descriptions, and protocol names are synchronized.

Individual module checks, dynamic execution, and tests can be run targeted:
```bash
asl lint <path-to-file.asl>           # AST delimiter balance & anti-pattern linter (asl check aliases to lint)
asl run <path-to-file.asl>            # In-memory AST tree-walking interpreter
asl run <path-to-file.asl> --wasm     # In-memory WebAssembly bytecode compilation & MicroVM execution
asl run <path-to-file.asl> --wat      # WebAssembly Text format emission
asl test [path-to-test.asl]          # Run native test suites
asl audit <path-to-file.asl>         # Run lint, test, and blast-radius impact analysis
```

## 3. Modern ASL v0.4+ Syntax & Pure Dyck-1 Form
AgentScript v0.4+ syntax rules:
- **Canonical Syntax (Storage & Wire Default)**:
  - Use modern syntax (`fn`, `schema`, `module`, `:d`, `:x`, `:i`, `:a`, `:f`, `:c`, `I64`, `F64`, `Str`, `Bool`, `Unit`) for files on disk, inter-agent message frames, and emitted artifacts. Legacy `(df ...)`, `(dfs ...)`, `(dfe ...)`, and `(mt ...)` are strictly forbidden.
  - Standard primitives adhere to a <= 2 token ceiling under BPE (`cl100k_base` and `o200k_base`), reducing context overhead by 50%–65% compared to JSON.
- **Pure Dyck-1 Homoiconic Form**:
  - All statements and definitions are balanced S-expressions.
  - Outlines and symbol navigation are queried dynamically via `asl '(:read ...)'` or `asl '(:query ...)'`.
- **Positional Aliasing**:
  - Short aliases resolve based on syntactic position as defined in `AGENT_SPEC_CORE.md` §2.1.
  - Record field keys preserve literal names (for example, `(P :x 1)` specifies a field named `:x`).
- **Comments as String Literal Notes**:
  - Express code comments as free-standing string literal notes placed at the top level or within declaration bodies.
  - Runtimes erase top-level notes during compilation while preserving multiline formatting.
- **Control-Flow Linearization**:
  - Keep nesting depth within 4 levels. Use early returns and concise local helper functions to maintain linear flow.

## 4. Pure-ASN Sovereign Agent Plane & Compound Tooling
All code exploration, reading, symbol queries, in-memory editing, diff inspection, daemon supervision, and verification MUST execute through pure-ASN S-expressions (`asl '(:op ...)'`) in single or compound top-level batches. Third-party agents interact exclusively via structured pure-ASL callable forms without raw shell string-blasting or unvalidated CLI pipelines.

### 4.1 Canonical Machine-Readable Tool Registry
Agents introspect active operational signatures at runtime via `asl '(:tools)'`:

```asn
(:tools :v 1 :substrate "ASL-Sovereign"
  (:op :tools :params [] :doc "Introspect active tool schema")
  (:op :manage :params [:action :id :cmd :lines :timeoutMs] :actions [:spawn :poll :tail :kill :list] :doc "Resident daemon process supervision, log spooling, and session lifecycle")
  (:op :proc :params [:action :id :cmd :lines :timeoutMs] :alias :manage :doc "Process supervision alias")
  (:op :lens :params [:file :target :lenses] :doc "Sovereign multi-lens audit returning structured ASN report")
  (:op :read :params [:file :symbol :anchor :limit] :doc "Bounded AST symbol and slice retrieval without integer line numbers")
  (:op :query :params [:text :scope :limit] :doc "Vector and semantic search across AST symbols and ledgers")
  (:op :edit :params [:file :old :new] :doc "Atomic string replacement staged in virtual RAM VFS buffer")
  (:op :diff :params [:file] :doc "Inspect dirty RAM VFS buffer modifications prior to disk flush")
  (:op :flush :params [] :doc "Atomically persist all staged RAM VFS modifications to disk")
  (:op :discard :params [] :doc "Clear all pending RAM VFS buffer modifications without disk side effects")
  (:op :check :params [:file] :doc "Verify Dyck-1 parenthesis balance, pure ASL syntax, and symbol resolution")
  (:op :test :params [:file] :doc "Execute falsifiable test suite via pure evaluator with strictly positive assertCount")
  (:op :audit :params [:subcmd] :subcmds [:consistency :gates :coupling :closure :foreign :steps] :doc "Run systemic monorepo audit across declared dimensions")
  (:op :crawl :params [:url :mode :distill] :doc "Crawl target web page and distill DOM to pure Dyck-1 ASN without noise")
  (:op :search :params [:query :limit] :doc "Cognitive web search with provider cascading and direct fallback")
  (:op :research :params [:topic :depth] :doc "Web research through the gateway; :verified only when facts with source urls pass verification")
  (:op :doctor :params [] :doc "Audit measured capabilities and substrate invariants")
  (:op :note :params [:action :kind :scope :date :claim] :doc "Record or query working memory observations in pure ASN"))
```

### 4.2 Compound In-Memory Batches & Zero-Line-Number Addressing
Pass multiple top-level forms in a single command. Forms execute concurrently in RAM VFS buffers:

```bash
asl '(:query :text "handleRequest") (:read :file "src/server.asl" :symbol "handleRequest") (:doctor)'
```

Zero-Line-Number Invariant: Code locations, slices, diffs, and receipts are addressed exclusively by path and symbol anchor (`:file ?f :symbol ?s :anchor ?a`). Integer line numbers are strictly excluded from agent commands and receipts.

### 4.3 Resident Daemon Process Supervision (`:manage`)
Agents supervise background commands and external processes via `:manage` (or `:proc`), eliminating dependence on host `manage_task`:
- `(:manage :action :spawn :id "<id>" :cmd "<command>")`: Spawns process asynchronously, tracking PID and spooling logs to `/tmp/asl-sessions/<id>.log`.
- `(:manage :action :poll :id "<id>")`: Polls active state (`:running`, `:completed`, `:failed`), exit code, and execution duration.
- `(:manage :action :tail :id "<id>" [:lines <n>])`: Streams tail of output log.
- `(:manage :action :kill :id "<id>")`: Terminates process group cleanly.
- `(:manage :action :list)`: Lists all active supervised sessions.

### 4.4 Failure Protocol & Atomic Recovery
- **RAM VFS Staging**: Modifying code stages edits in virtual RAM VFS (`:edit -> :diff -> :flush | :discard`). If an edit is erroneous, call `(:discard)` to roll back cleanly without leaving corrupted files on disk.
- **Edit Failure Recovery**: If `:edit` fails, do not blind-retry. Query the symbol via `(:read :file <path> :symbol <name>)` to observe the ground-truth code structure and anchor.
- **Circuit Breaker**: Capped at 3 identical failures (`:rule :id limitCycle`). Tripping forces phase transition or escalation.

## 5. Ecosystem & Multi-Package Architecture
- Code packages reside under `packages/` and are organized as self-contained ASL modules with a `manifest.asn` declaration.
- Maintain pure ASL implementations across all code packages.
- Ensure that all AST definitions and schemas in `grammar/` adhere to pure Dyck-1 homoiconicity and pass `./bin/asl check`.
- Ensure all public documentation examples fenced with ` ```agentscript ` or ` ```lisp ` parse cleanly, or annotate speculative snippets with `<!-- not-agentscript: reason -->`.

