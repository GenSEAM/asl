# Iteration Plan: asl-shrody-migration-v1 (Reconciled v2)

> **Source Repository Reference:** [`/Users/purplelephant/projects/shrody`](file:///Users/purplelephant/projects/shrody)  
> **Source Git Commit:** `main` @ `68414612635eee46705206760bdfb6fa619f6c68`  
> **Target Repository:** [`/Users/purplelephant/projects/asex`](file:///Users/purplelephant/projects/asex)  
> **Target Package:** `packages/asl-shrody/`  
> **Review Reference:** [`.plans/shrody-asl-migration/REVIEW.md`](file:///Users/purplelephant/projects/asex/.plans/shrody-asl-migration/REVIEW.md)  
> **Goal:** Migrate Shrody's voice and coding agent capabilities into modular, testable, sandboxed AgentScript (ASL) packages running on Wasm/FFI. Eliminate architectural debt: OOM memory crashes, multi-second process launch lag, permission prompt spam, and brittle heuristic routing.

---

## 1. Architectural Invariants

1. **Strict Memory & Isolation Ceiling (Anti-OOM):**  
   Standard research, errands, and question answering execute within pure ASL / Wasm isolates with a strict 16MB ceiling (`--memory 16`). External CLI agent processes (Node/V8/Chromium) are NEVER spawned for general non-dev tasks.
2. **Capability-Based Sandboxing (Zero-Spam Permissions):**  
   Workspace root directory, task git worktrees (`manifest.worktree_roots`), and sandbox `/tmp` are explicitly authorized via capability manifests. The agent never prompts the user for permission on pre-authorized directories. Path traversal outside sandbox is strictly denied.
3. **Formal AST Intent Triage (Multi-Query Invariant):**  
   Intent classification uses typed S-expression AST pattern matching. Port and preserve `@pcp:d-374e`: multi-aspect questions and non-dev requests within the same workspace are collapsed into single execution frames rather than spawned into redundant isolated tasks.
4. **Clean Host/Guest FFI Decoupling & Barge-In:**  
   Cognitive planning, ReAct loops, and triage remain pure ASL. Hardware-dependent audio I/O (CoreAudio PCM ring buffer), Piper TTS child processes, and conversational barge-in (`audio/interrupt`) are encapsulated as Host Capabilities accessed via `(host-call ...)`.
5. **Ecosystem Component Reuse (Ponytail / Anti-Overengineering):**  
   Leverage existing `@genseam/asl-toolcall` for dense S-expression tool calling (-76.5% tokens) and `@genseam/voice` for 16kHz PCM audio streaming rather than reinventing custom parsers.

---

## 2. Work Breakdown

### Item 1: Package Scaffolding & Host Capability FFI Bridge
- **Paths:**
  - `packages/asl-shrody/package.json`
  - `packages/asl-shrody/src/ffi.asl`
  - `packages/asl-shrody/bridges/host_bridge.js`
  - `packages/asl-shrody/test/ffi.test.js`
- **Specification:**
  - Declare internal dependencies: `@genseam/asl-toolcall` and `@genseam/voice`.
  - Define bidirectional FFI contract:
    `(df host-call [(capability Str) (action Str) (payload Str)] -> (Result Str Str))`
  - Support capabilities:
    - `fs`: `read`, `write`, `list`.
    - `exec`: sandboxed command execution with timeout.
    - `audio`: `speak`, `interrupt` (conversational barge-in cutoff), `vad_status`.
    - `llm`: `complete`, `stream`.
  - Implement zero-copy buffer transfer and timeout guards.
- **Verification Gate:**
  - `node --test packages/asl-shrody/test/ffi.test.js`
  - Verifies round-trip dispatch, `audio/interrupt` cancellation, error propagation, and zero memory leaks across 10,000 synthetic calls.

### Item 2: Sandboxed Capability Policy & Zero-Spam Permissions
- **Paths:**
  - `packages/asl-shrody/src/policy.asl`
  - `packages/asl-shrody/test/policy.test.js`
- **Specification:**
  - Capability policy module evaluating `(check-permission action path manifest) -> PermissionResult`.
  - Invariants:
    - Path within `manifest.workspace_root` -> `(allow-silent)`
    - Path within any `manifest.worktree_roots` -> `(allow-silent)`
    - Path within `manifest.temp_dir` (`/tmp/shrody/...`) -> `(allow-silent)`
    - Traversal (`../`, symlink escapes) or root system paths (`/etc`, `~/.ssh`) -> `(deny-strict "sandbox escape")`
- **Verification Gate:**
  - `node --test packages/asl-shrody/test/policy.test.js`
  - Verifies 100% pass on boundary tests: zero user prompts for workspace, worktrees, and `/tmp` writes; hard rejection on traversal attacks.

### Item 3: Formal Intent Triage & Multi-Query AST Matcher
- **Paths:**
  - `packages/asl-shrody/src/triage.asl`
  - `packages/asl-shrody/test/triage.test.js`
- **Specification:**
  - Implement deterministic intent parser in ASL:
    - `(df triage-request [(input Str) (workspace-context Workspace)] -> TriageDecision)`
  - Encodes rules from Shrody's `src/frontline.js` and `src/wiring.js`:
    - Dispatches to: `:dev` | `:non-dev` | `:question` | `:setup` | `:admin`.
    - Collapses multi-query questions into a single task frame (`@pcp:d-374e`).
    - Routes setup commands (`init`, `branch`, `clone`) to general workspace setup (`@pcp:d-1a1a`).
- **Verification Gate:**
  - `node --test packages/asl-shrody/test/triage.test.js`
  - Replays all 232 test vectors from Shrody's `test/frontline.test.js` and `src/benchcases.js`. 100% parity required.

### Item 4: Task Topology & Subtask DAG Scheduler
- **Paths:**
  - `packages/asl-shrody/src/dag.asl`
  - `packages/asl-shrody/test/dag.test.js`
- **Specification:**
  - Dependency graph data structures and cycle detection in pure ASL:
    - `(dfs TaskNode (:f id Str) (:f deps (List Str)) (:f status TaskStatus) (:f payload Str))`
    - `(df resolve-execution-order [(tasks (List TaskNode))] -> (Result (List (List Str)) Str))`
  - Cascading cancellation: when upstream task fails, dependent tasks transition to `CANCELLED_UPSTREAM`.
  - Emits topological execution waves (parallel batches of independent tasks).
- **Verification Gate:**
  - `node --test packages/asl-shrody/test/dag.test.js`
  - Verifies cycle detection, DAG topological linearization, and failure cascade propagation.

### Item 5: Native ReAct Micro-Harness (Memory & Latency Cure)
- **Paths:**
  - `packages/asl-shrody/src/harness.asl`
  - `packages/asl-shrody/test/harness.test.js`
- **Specification:**
  - Self-contained ReAct agent loop in ASL integrating `@genseam/asl-toolcall`:
    - Step 1: Assemble prompt with S-expression tool definitions.
    - Step 2: Call LLM via FFI `llm/complete`.
    - Step 3: Parse and validate tool call via `asl-toolcall`.
    - Step 4: Validate target paths against `policy.asl`.
    - Step 5: Execute tool via FFI `host-call`.
    - Step 6: Loop until `:final-answer` or step budget exhausted (max 10 steps).
- **Verification Gate:**
  - `node --test packages/asl-shrody/test/harness.test.js`
  - Validates end-to-end execution of 5 standard benchmark errands (file search, weather mock, text synthesis, data aggregation).
  - RSS memory ceiling check: <= 24MB peak memory.

### Item 6: Context Formatter & Token Economy Gate
- **Paths:**
  - `packages/asl-shrody/src/format.asl`
  - `packages/asl-shrody/bench/token_ceiling.js`
- **Specification:**
  - Encodes domain status (git status, task boards, active branches) into ASN tabular matrices (`([:id :status :summary] [...])`).
  - Measures token usage with `tiktoken` (`cl100k_base` and `o200k_base`) vs equivalent JSON.
- **Verification Gate:**
  - `node packages/asl-shrody/bench/token_ceiling.js --check`
  - Requires >= 60% token reduction over JSON Schema.

### Item 7: Comparative End-to-End Benchmark vs Shrody
- **Paths:**
  - `packages/asl-shrody/bench/compare_shrody.js`
- **Specification:**
  - Runs identical scenarios against Shrody (`/Users/purplelephant/projects/shrody`) and `asl-shrody`:
    - Scenario A: Trivial query ("Find weather forecast").
    - Scenario B: Multi-aspect query ("List active branches and summarize README").
    - Scenario C: Project search & read file errand.
  - Telemetry collected: Peak RSS (MB), cold start latency (ms), total tokens consumed, permission prompts count.
- **Verification Gate:**
  - Peak RSS reduction >= 90% (from ~1.2GB down to <50MB).
  - Cold start latency reduction >= 95% (from ~2500ms down to <100ms).
  - Zero permission prompts for authorized workspace operations.
  - Zero OOM crashes under 5 concurrent executions.

---

## 3. Acceptance Criteria

- [ ] All 7 work items have dedicated tests and pass 100%.
- [ ] No regression against the 232 test vectors ported from Shrody's `test/frontline.test.js`.
- [ ] Conversational barge-in (`audio/interrupt`) cuts audio latency to < 5ms.
- [ ] Zero interactive permission prompts for workspace root, worktrees, and `/tmp` paths.
- [ ] Peak memory during execution of errands is bounded to <= 24MB.
- [ ] Pre-commit validation in `asex` (`.venv/bin/python tools/validate.py`) passes cleanly.
