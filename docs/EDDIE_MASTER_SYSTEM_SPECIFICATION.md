# Master Engineering Specification: Autonomous Cognitive Agent EDDIE & Deterministic Execution Ecosystem
**Document ID:** SPEC-2026-EDDIE-SYSTEM-v3.0  
**Codename:** EDDIE (*Engine for Dynamic Decomposition, Intent-routing & Execution*)  
**Status:** Canonical Implementation Standard (Fully Reconciled & Gap-Free)  
**Workspace Base:** `/Users/purplelephant/projects/asex`  
**Target Packages:** `packages/eddie`, `packages/harness`, `packages/agent-core`, `packages/intel`, `packages/mem`, `packages/asl-gateway`, `packages/asl-lens`

---

## 1. System Philosophy & Fundamental Ontology

The architecture strictly separates the **stochastic semantic processor** from the **deterministic operating environment**.

```
+-------------------------------------------------------------------------------+
|                       SYSTEM ONTOLOGICAL DECOMPOSITION                        |
|                                                                               |
|  [ LLM Inference Engine ]  <--- Stochastic ALU / Probabilistic Next-Step CPU  |
|  [ Model Context Window ]  <--- Ephemeral Register Stack (Prompt VMM Cache)    |
|  [ L7 Gateway / Harness ]  <--- Deterministic Operating System (Process Mgr)   |
|  [ In-Memory Slab / Git ]  <--- Transactional Blackboard RAM & .eddie/ Store   |
|  [ Shadow Copilot ]        <--- Asynchronous Background Observer / Pre-tester  |
+-------------------------------------------------------------------------------+
```

### 1.1. Core Invariants
1. **Native Runtime Integration (Zero External MCP/PCP Dependencies):** EDDIE does not rely on third-party frameworks, Claude marketplace skills, or ambient host MCP servers. All cognitive routing, guardrails, and memory models are compiled directly into the AgentScript (ASL) runtime using composable onion middlewares (`agent-core/src/onion.asl`) and the internal event bus (`agent-core/src/core.asl`).
2. **Pluggable & Fully Toggleable:** All sub-systems (AST Gate, Intent Graph, Prompt VMM, Watchdog, Shadow Copilot) attach as modular middleware hooks and can be dynamically enabled/disabled at runtime via `HarnessConfig` (`config.asl`) with zero overhead when off.
3. **Git-Native Mergeable Textual Snapshots (`.eddie/`):** All persistent state, requirements, decisions, and intent linkages are serialized as line-oriented, sorted S-expression records (`.asn`). Parallel branches merge cleanly in GitHub via standard 3-way git merge without conflict.

---

## 2. Composable Onion Middleware & Event-Driven Pipeline

Every action emitted by EDDIE traverses an in-memory, topologically sorted onion pipeline:

```
        [ User Task / EventBus Message ]
                       │
                       ▼
 ┌───────────────────────────────────────────────────────────┐
 │ 1. mw-firewall: Path traversal & lease validation         │ (kind-filter)
 ├───────────────────────────────────────────────────────────┤
 │ 2. mw-vmm: Prompt VMM slot hydration & JIT knowledge page│ (kind-pre-call)
 ├───────────────────────────────────────────────────────────┤
 │ 3. mw-fsm: Single-pass grammar & delimiter normalizer     │ (kind-mutate)
 ├───────────────────────────────────────────────────────────┤
 │ 4. mw-ast-gate: Pre-execution AST verification            │ (kind-pre-call)
 ├───────────────────────────────────────────────────────────┤
 │      [ CORE EXECUTION PLANE: Tier-1 Wasm / Worktree ]     │
 ├───────────────────────────────────────────────────────────┤
 │ 5. mw-ast-diff: Post-execution AST delta audit (tests/inv)│ (kind-post-call)
 ├───────────────────────────────────────────────────────────┤
 │ 6. mw-sanitizer: Diagnostic trace compression (<300 tok) │ (kind-mutate)
 ├───────────────────────────────────────────────────────────┤
 │ 7. mw-intent: Atomic transaction commit to .eddie/ graph  │ (kind-audit)
 └───────────────────────────────────────────────────────────┘
                       │
                       ▼
          [ Internal EventBus Broadcast ]
```

---

## 3. Git-Mergeable Textual Snapshot Engine (`.eddie/`)

To eliminate database vendor locks and git merge collisions, state is serialized in line-oriented S-expressions:

```
.eddie/
├── config.asn            # Active model profile (Gemma 31B), feature flags, budgets
├── graph/
│   ├── usecases.asn      # Line-oriented acceptance criteria & E2E flows
│   ├── requirements.asn  # Functional & non-functional requirements
│   ├── decisions.asn     # Architectural decisions (ADRs) with rationale
│   ├── invariants.asn    # Immutable negative rules & safety ceilings
│   └── edges.asn         # Relational link tuples: (:edge :src "..." :dst "..." :rel :...)
├── state/
│   ├── dag.asn           # Active Task-Premise DAG G=(V,E,P,H)
│   └── falsified.asn     # Append-only blacklist of disproven hypotheses
└── staging/              # Non-blocking staging ground for Shadow Copilot proposals
```

### 3.1. Mergeability Invariants
* **One Entity / Edge Per Line:** Every record in `edges.asn` is a self-contained, alphabetically sorted S-expression:
  ```lisp
  (:edge :src "sym:store/dot" :dst "req:simd-vector" :rel :fulfills)
  (:edge :src "sym:paged/slab" :dst "dec:sq8-quant" :rel :governed-by)
  ```
* **Conflict-Free 3-Way Merge:** Additions from parallel branches append cleanly to separate lines. Standard git pull requests resolve merges automatically without human intervention.
* **Atomic Code-State Sync:** Source code modifications and `.eddie/` metadata updates are committed together in a single atomic Git commit.

---

## 4. Prompt VMM: Segmented Context Hygiene & Knowledge Lifecycle

The context window is treated as a deterministic virtual memory buffer with four dedicated slots:

```
+-------------------------------------------------------------------------------+
|                       PROMPT VMM CONTEXT SLOTS                                |
+-------------------------------------------------------------------------------+
| Slot 1: Immutable Invariants     | System constitution, root negative rules   |
| Slot 2: Semantic Receipts Ledger | 1-line cryptographic stubs of past turns   |
| Slot 3: Pinned Domain Slot (Paged| Ephemeral JIT library types / API specs    |
| Slot 4: Working Frame            | Active task, local AST slice being edited  |
+-------------------------------------------------------------------------------+
```

### 4.1. JIT Knowledge Lifecycle (Load -> Operate -> Offload)
1. **JIT Hydration:** When EDDIE touches an external library, `mw-vmm` loads an interface skeleton (~150 tokens) into Slot 3: `(knowledge-load :target "zod@3.22.4" :slot :pinned)`.
2. **Surgical Code Generation:** EDDIE edits code with verified type signatures.
3. **Atomic Offload & Receipt Minting:** `(knowledge-offload :slot :pinned :emit-receipt true)`. Slot 3 is cleared; a 12-token semantic receipt is appended to Slot 2:
   ```lisp
   (:receipt :target "zod@3.22.4" :action "validated-schema" :anchor "auth.asl:42")
   ```
4. **Token Savings:** Documentation never lingers across multi-turn sessions, cutting context token usage by 75–85%.

---

## 5. Codebase Intelligence & Graph-Horizon Paging

EDDIE navigates large codebases (100k+ LOC) through an adaptive 3-tier memory substrate:

```
+-------------------------------------------------------------------------------+
|                      3-TIER CODEBASE MEMORY SUBSTRATE                         |
+-------------------------------------------------------------------------------+
| TIER 1: MACRO-TOPOLOGY (100% Resident in RAM, ~200 KB)                        |
|  - Module DAG, import/export edges, BLAKE3 file hashes, cycle detector        |
+-------------------------------------------------------------------------------+
| TIER 2: MESO-SYMBOL GRAPH (LRU Paged Memory, ~2-6 MB)                         |
|  - Function signatures, record types, call graph (GraphNode / GraphEdge)      |
|  - Zero function bodies: exclusively typed interface stubs (Valid Stubs)     |
+-------------------------------------------------------------------------------+
| TIER 3: MICRO-AST SLICES (On-Demand JIT in Wasm Heap)                         |
|  - Source bodies of functions currently being inspected or patched            |
+-------------------------------------------------------------------------------+
```

### 5.1. Scoped Preloading ($H(m, k, B)$) & Health Matrix
* **Horizon Expansion (`intel/src/preload.asl`):** Preloads target symbol $m$ on depth $k$ under token ceiling $B$:
  * Depth 0: Full AST body.
  * Depth 1: Direct callers/callees interface stubs (signatures only, saving 78% tokens).
  * Depth 2: Transitive boundary module names and 1-line docstrings.
* **Instant Health Matrix (`intel/src/health.asl`):** Traverses the symbol graph in $<1$ ms:
  * Detects circular imports (3-state DFS).
  * Identifies high fan-in hotspots ($\text{InDegree} \ge 10$) to warn about blast radius.
  * Finds orphan exports ($\text{InDegree} = 0$, unused code).
  * Flags call-site arity and type mismatches before running compilers.

---

## 6. Feedback Process Supervisor & Watchdog Architecture

To eliminate deadlocks when running unit tests, scripts, or subagents:

```
        [ Command Spawning via Supervisor ]
                        │
                        ▼
 ┌─────────────────────────────────────────────────────────────┐
 │ 1. Non-Interactive Enforcement:                             │
 │    STDIN = /dev/null | CI=true | DEBIAN_FRONTEND=noninteract│
 └──────────────────────┬──────────────────────────────────────┘
                        │
                        ▼
 ┌─────────────────────────────────────────────────────────────┐
 │ 2. Sliding 10-Second Idle Watchdog:                         │
 │    Timer resets on every chunk of stdout/stderr             │
 └──────────────────────┬──────────────────────────────────────┘
                        │
          [ 10s of Zero Output Detected ]
                        │
                        ▼
 ┌─────────────────────────────────────────────────────────────┐
 │ 3. Process State Diagnostic:                                │
 │    • Check CPU activity via OS /proc or pid polling         │
 │    • If CPU == 0% & State == Sleep (Waiting for stdin):     │
 │        ==> INTERACTIVE DEADLOCK DETECTED                    │
 │    • Issue SIGINT -> 2s Grace -> Escalation to SIGKILL      │
 │    • Capture last 15 lines of output                        │
 │    • Emit structured ASN Deadlock Receipt                   │
 └─────────────────────────────────────────────────────────────┘
```

---

## 7. Multimodality & Perceptual Pointers

* **Vision Offloading:** Screenshots, DOM trees, and diagrams are BLAKE3-hashed and stored in blob storage. Context windows receive only compact Perceptual Pointers (`:ptr :id "b3-..." :kind @vision :summary "..." :bboxes [...]`).
* **Micro-Perception Subagents:** When deep visual inspection is needed, an ephemeral subagent examines the region in an isolated context and returns a verified scalar fact (`(:fact :key "button_aligned" :val true)`).
* **Real-Time Voice Streaming:** 16kHz PCM audio bridge with Voice Activity Detection (`voice/src/vad.asl`). Senses speech energy and triggers instant conversational barge-in interrupts.

---

## 8. Phased Inference Control & Telemetry Dashboard

### 8.1. Phased Inference Parameters

| Execution Phase | Thinking Budget | Temperature | Top-P | Top-K | Rationale |
|---|---|---|---|---|---|
| **INSPECT** | 0 tokens (Off) | 0.0 | 0.1 | 1 | Zero-latency, deterministic tool calls |
| **PLAN** | 2,048 - 4,096 | 0.2 | 0.8 | 40 | Deep architectural reasoning |
| **AST PATCH** | 0 tokens (Off) | 0.0 | 0.05 | 1 | Absolute determinism during code emission |
| **REASON / DEBUG**| 4,096 - 8,192 | 0.4 | 0.9 | 50 | Root-cause hypothesis search |

### 8.2. Multi-Dimensional Telemetry Metrics
* **Speed:** Time-To-First-Token (TTFT), Tokens-Per-Second (TPS), in-memory Wasm tool latency ($<0.05$ ms).
* **Cost & Cache:** Prompt/Completion tokens, RFC 8785 KV-Cache hit ratio (target: $\ge 90\%$), total USD expenditure.
* **Hallucinations Blocked:** TSH (Trie tool masking), TCH (FSM parameter repairs), AST Diffing rejections, quote LCS drops ($<0.95$).
* **Harness Health:** Wasm slab memory (MB / 16 MB), active subagent status, watchdog idle alerts.

---

## 9. Background Assistant / Shadow Copilot Architecture

A lightweight copilot (running on Gemma 31B/9B, DeepSeek Flash, or Gemini Flash) attaches to the internal event bus:

```
                       [ Internal EventBus (core.asl) ]
                                      │
               ┌──────────────────────┴──────────────────────┐
               ▼                                             ▼
  [ PRIMARY AGENT (EDDIE) ]                     [ SHADOW COPILOT ]
  • Executes task steps                         • Listens to events in background
  • Edits AST in memory                         • Extracts decisions & stages to .eddie/staging/
  • Runs verification gates                     • Pre-runs tests speculatively
                                                • Pre-warms dependency cache
                                                • Proactively advises user in TUI
                                                • Dynamically auto-tunes parameters
```

### 9.1. Concurrency & Non-Blocking Staging Model
To prevent lock contention or race conditions with EDDIE:
* **Read-Only Inspection:** Shadow Copilot holds read-only access to the primary working tree and symbol graph.
* **Staging Ground (`.eddie/staging/`):** Inferred decision records or suggested requirement updates are written to temporary staging files.
* **Atomic Merge-In:** EDDIE or the human operator confirms and commits staged records with an atomic CAS step, eliminating race conditions.

---

## 10. Native Tooling Interface for EDDIE

All tools execute natively within EDDIE's harness via in-memory WASI / Wasm3 or isolated Git worktrees:

```lisp
;; 1. Adaptive Preloading (intel/src/preload.asl)
(:tool :name "eddie-preload"
       :params [target:Str depth:I64 token-budget:I64]
       :doc "Loads scoped AST slice and interface stubs up to token ceiling.")

;; 2. In-Memory Surgical AST Mutation (harness/src/repl.asl)
(:tool :name "ast-patch"
       :params [path:Str symbol:Str replacement:Str]
       :doc "Surgically substitutes target AST node in RAM in <50 microseconds.")

;; 3. Codebase Diagnostic Matrix (intel/src/health.asl)
(:tool :name "eddie-health"
       :params [scope:Str]
       :doc "Returns structural cycles, orphan exports, type drift, and high-risk hotspots.")

;; 4. Lockfile Introspection & Version-Pinned Library Inspection
(:tool :name "deps-resolve"
       :params [package:Str symbol:Str]
       :doc "Inspects lockfile and returns exact type signature for installed library version.")

;; 5. Ephemeral Knowledge Lifecycle (Prompt VMM)
(:tool :name "knowledge-load"
       :params [target:Str slot:Str]
       :doc "Hydrates version-pinned library API into ephemeral context slot.")

(:tool :name "knowledge-offload"
       :params [slot:Str emit-receipt:Bool]
       :doc "Wipes knowledge slot, appending concise semantic receipt.")

;; 6. Intent Graph Navigation & Traceability
(:tool :name "intent-query"
       :params [entity-id:Str relation:Str depth:I64]
       :doc "Traverses relational hypergraph linking code symbols to requirements and decisions.")

(:tool :name "trace-verify"
       :params [symbol:Str]
       :doc "Validates that a symbol has valid linkages to requirements, usecases, and invariants.")

(:tool :name "intent-record"
       :params [kind:Str title:Str rationale:Str links:(List Str)]
       :doc "Records a new versioned requirement, decision, or invariant in .eddie/graph/.")

;; 7. Sandboxed Command Execution with Watchdog
(:tool :name "exec-cmd"
       :params [command:Str timeout-sec:I64]
       :doc "Executes shell command with non-interactive STDIN and 10s Sliding Idle Watchdog.")

;; 8. Perceptual Pointer Dereference
(:tool :name "ptr-deref"
       :params [ptr-id:Str query:Str region:(Option (List I64))]
       :doc "Delegates visual/audio inspection to isolated subagent, returning scalar fact.")
```

---

## 11. Two-Pronged Distribution Strategy & External Agent Steering Engine

### 11.1. Track A: Drop-in Tooling Accelerator (`@genseam/lens` via NPM / CLI / MCP)
* Plugs into Claude Code, Gemini CLI, Cursor, Windsurf, OpenDevin.
* Enforces strict Negative Constraints (`CLAUDE.md`, `AGENTS.md`, `.cursorrules`) that forbid `View`/`cat` on files >50 lines and mandate `asl intel outline` and `asl intel impact`.
* **Prerequisite / Onboarding Hook:** If `asl` is not installed on `$PATH`, the agent detects this on turn 0, halts immediately, and prompts the user for a one-click install:
  `curl -fsSL https://get.genseam.org | bash` (Documentation: `https://genseam.org/install`).

### 11.2. Track B: Sovereign Standalone EDDIE Stack (Binary / React 19 Ink TUI)
* Complete, standalone terminal client (`eddie`) with React 19 / Ink TUI.
* Full local privacy, running against local Gemma 31B, DeepSeek, or dedicated LLM Gateway.
* Integrated process supervision, fleet matrix, and zero-disk in-memory AST editing.
