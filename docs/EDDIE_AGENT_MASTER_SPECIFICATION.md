# Master Architecture Specification: Autonomous Agent EDDIE & Deterministic Execution Harness
**Document ID:** SPEC-2026-EDDIE-MASTER-v1.0  
**Codename:** EDDIE (*Engine for Dynamic Decomposition, Intent-routing & Execution*)  
**Applies to:** `packages/eddie`, `packages/harness`, `packages/agent-core`, `packages/intel`, `packages/mem`

---

## 1. System Philosophy & Ontological Clarification

**EDDIE** is an autonomous, self-contained, native software engineering agent built directly into the AgentScript (ASL) runtime. 

```
+-------------------------------------------------------------------------------+
|                       SYSTEM BOUNDARIES & ARCHITECTURE                        |
|                                                                               |
|  [ External World / Proved Skills ]  <--- Purely auxiliary toolkits (Opt-in)  |
|                                                                               |
|  [ EDDIE NATIVE RUNTIME CORE ]       <--- Self-contained in-engine agent      |
|    ├── Event Bus (core.asl)          <--- High-throughput internal pub/sub    |
|    ├── Composable Onion Middlewares   <--- Priority-ordered execution filters  |
|    ├── Native Wasm Execution Harness <--- Sub-millisecond sandboxed runtime   |
|    ├── Prompt Virtual Memory Manager <--- JIT knowledge paging & offloading   |
|    └── Git-Mergeable State Snapshots <--- Human-readable, Git-native memory   |
+-------------------------------------------------------------------------------+
```

### 1.1. Core Architectural Corrections
1. **Strictly Native, Not MCP/Skill-Dependent:** EDDIE does not rely on Claude-specific skills (such as PCP) or external MCP bridge daemons for its core cognition. All cognitive routing, state management, and epistemic firewalls are compiled directly into the ASL agent runtime via composable onion middlewares (`agent-core/src/onion.asl`) and the internal event bus (`agent-core/src/core.asl`).
2. **Pluggable & Fully Toggleable:** All sub-modules (Intent Graph, AST Differ, Prompt VMM, Epistemic Firewall) attach as native middleware hooks. They can be selectively activated or deactivated at runtime via `HarnessConfig` (`config.asl`) with zero performance penalty when disabled.
3. **Git-Mergeable Textual Storage:** Agent memory, decisions, and intent linkages are serialized as line-oriented, conflict-free S-expression records (`.eddie/`). Multiple agents and human developers can branch, commit, and merge state via standard Git pull requests without merge collision.

---

## 2. Composable Onion Middleware & Event-Driven Core

EDDIE's cognitive and execution pipeline is organized as an onion architecture with strict topological dependency ordering.

```
       [ Client Request / Task Event ]
                      │
                      ▼
 ┌───────────────────────────────────────────────┐
 │ Layer 1: Security & Lease Filter (mw-firewall)│
 ├───────────────────────────────────────────────┤
 │ Layer 2: Context Pager & VMM (mw-vmm)         │
 ├───────────────────────────────────────────────┤
 │ Layer 3: FSM Grammar Normalizer (mw-fsm)      │
 ├───────────────────────────────────────────────┤
 │ Layer 4: Pre-Execution AST Gate (mw-ast-gate) │
 ├───────────────────────────────────────────────┤
 │      [ CORE EXECUTION: Wasm Tier-1 / Host ]   │
 ├───────────────────────────────────────────────┤
 │ Layer 5: Post-Execution Audit (mw-audit)      │
 ├───────────────────────────────────────────────┤
 │ Layer 6: Trace Sanitizer (mw-sanitizer)       │
 ├───────────────────────────────────────────────┤
 │ Layer 7: Intent Graph Committer (mw-intent)   │
 └───────────────────────────────────────────────┘
                      │
                      ▼
          [ Event Bus Notification ]
```

### 2.1. Middleware Hooks (`agent-core/src/onion.asl`)
Middlewares register into defined lifecycle phases:
* `kind-filter`: Evaluates preconditions and filesystem boundary constraints.
* `kind-pre-call`: Intercepts tool calls before execution (e.g. token-budget checking, schema validation).
* `kind-mutate`: Transforms arguments or context frames (e.g. S-expression normalization).
* `kind-post-call`: Inspects tool outputs and executes AST delta verifications.
* `kind-audit`: Records telemetry, token consumption, and failure logs.

---

## 3. Git-Native Mergeable Textual Snapshot Engine (`.eddie/`)

To prevent repository merge conflicts and avoid proprietary binary databases, EDDIE serializes its internal state into modular, line-oriented ASN/S-expression files under `.eddie/`.

```
.eddie/
├── config.asn          # Active feature toggles, active model profile (Gemma 31B)
├── graph/              # Relational Intent-Code Hypergraph
│   ├── usecases.asn    # Line-oriented Use Case definitions
│   ├── requirements.asn# Line-oriented Requirements with formal predicates
│   ├── decisions.asn   # Architectural decisions and trade-offs
│   ├── invariants.asn  # Immutable negative rules and security boundaries
│   └── edges.asn       # Relational link tuples: (:e :src "..." :dst "..." :rel :fulfills)
├── state/
│   ├── dag.asn         # Active Task-Premise DAG G=(V,E,P)
│   └── falsified.asn   # Append-only list of disproven hypotheses
└── cache/              # Local ephemeral cache (Git-ignored)
```

### 3.1. Conflict-Free Mergeability Properties
1. **Sorted Content-Addressed Tuples:** All records in `edges.asn` are stored as sorted, unique single-line S-expressions:
   ```lisp
   (:edge :src "sym:store/dot" :dst "req:vector-simd" :rel :fulfills)
   (:edge :src "sym:paged/slab" :dst "dec:sq8-quant" :rel :governed-by)
   ```
2. **Three-Way Merge Cleanliness:** In standard Git merges, additions from parallel branches simply append or insert adjacent lines. Git resolves these cleanly without manual conflict resolution.
3. **Atomic Commit Hook:** Upon task completion, EDDIE commits code changes and the updated `.eddie/` state files together in a single atomic Git commit.

---

## 4. Prompt VMM: Knowledge Paging, Offloading & Semantic Receipts

EDDIE enforces strict **Context Hygiene** through the Prompt Virtual Memory Manager (Prompt VMM), eliminating prompt bloat and keeping token consumption minimal.

```
+-------------------------------------------------------------------------------+
|                       PROMPT VMM CONTEXT SLOTS                                |
+-------------------------------------------------------------------------------+
| Slot 1: Static Invariant Header   | System constitution, immutable rules       |
| Slot 2: Semantic Receipt Ledger   | 1-line stubs of completed historical turns |
| Slot 3: Pinned Domain Slot (Paged)| Ephemeral JIT library types / API specs   |
| Slot 4: Working Frame (Ephemeral) | Active S-expression being modified         |
+-------------------------------------------------------------------------------+
```

### 4.1. JIT Knowledge Life-Cycle (Load -> Operate -> Offload)
When EDDIE works with a library or complex subsystem:
1. **JIT Hydration:** EDDIE requests knowledge via `(knowledge-load :target "package@version" :slot :pinned)`. The distilled type skeleton (~150 tokens) is loaded into Slot 3.
2. **Surgical Operation:** EDDIE generates code against the verified type signatures.
3. **Immediate Offload & Receipt Minting:** EDDIE unloads the knowledge: `(knowledge-offload :slot :pinned :emit-receipt true)`. Slot 3 is wiped, and a 12-token receipt is recorded in Slot 2:
   `(:receipt :target "package@version" :status :completed :anchor "module.asl:42")`.
4. **Result:** Heavy documentation never leaks into subsequent turns, slashing multi-turn token costs by 75–85%.

---

## 5. Relational Intent-Code Hypergraph Architecture

EDDIE understands *why* code exists through an internal relational hypergraph linking intent to concrete syntax nodes.

```
          [ Milestone Plan (P) ]
                     │ :schedules
                     ▼
          [ Requirement (R) ] ◄─── :governs ─── [ Architecture Decision (D) ]
             ▲            │                         │
  :validates │            │ :fulfills               │ :constrains
             │            ▼                         ▼
     [ Use Case (U) ] ──► [ Code AST Node (C) ] ◄─── [ Invariant (C_t) ]
               :implements
```

### 5.1. Entity & Relational Calculus
* **Nodes:**
  * $U$: Use Cases (`uc-xxxx`) — behavioral scenarios and acceptance tests.
  * $R$: Requirements (`req-xxxx`) — formal functional and non-functional specifications.
  * $D$: Decisions (`dec-xxxx`) — architectural choices with alternative trade-offs.
  * $C_t$: Invariants (`inv-xxxx`) — immutable constraints and security boundaries.
  * $C$: Code AST Nodes (`@sym:...`) — concrete functions, types, and modules.
* **Traceability Invariants:**
  * Every public export must fulfill at least one requirement: $\forall c \in C_{\text{public}}, \exists r \in R: \text{fulfills}(c, r)$.
  * Every mutation to code $C$ automatically triggers validation of all linked use cases $U$ where $\text{implements}(C, U)$.

---

## 6. Real-Time Codebase Diagnostics & Adaptive Graph Horizon

### 6.1. Adaptive Graph Preloading
When EDDIE investigates an unfamiliar module:
$$\text{PreloadHorizon}(m, k, B) = \left\{ n \in \text{Nodes} \;\middle|\; \text{dist}(m, n) \le k \;\land\; \sum \text{Tokens}(n) \le B \right\}$$
* **Distance 0 (Target Module):** Full source code with S-expression bodies.
* **Distance 1 (Direct Callers/Callees):** Interface stubs (`Valid Stubs` — signatures only, saving 78% tokens).
* **Distance 2 (Transitive Neighborhood):** Module names and 1-line docstrings.

### 6.2. Instant Codebase Health Matrix (`eddie-health`)
EDDIE can inspect the health of the codebase in $<1$ ms via graph traversal:
* **Blast Radius Hotspots:** Nodes with high incoming degree ($\text{InDegree} \ge 10$) flagged as high-risk.
* **Circular Import Detector:** Instant cycle detection preventing runtime import deadlocks.
* **Zombie Export Auditor:** Identifies public exports that have zero consumers across the repository.
* **Signature Mismatches:** Detects arity or type divergence between caller and callee nodes before running compilers.

---

## 7. Native Tooling Plane for EDDIE

All tools execute natively within EDDIE's harness via in-memory WASI / Wasm3 or isolated Git worktrees:

```lisp
;; 1. Scoped Preloading
(:tool :name "eddie-preload"
       :params [target:Str depth:I64 token-budget:I64]
       :doc "Pulls modular AST slices and interface stubs into context up to token budget.")

;; 2. In-Memory Surgical AST Mutation
(:tool :name "ast-patch"
       :params [path:Str symbol:Str replacement:Str]
       :doc "Surgically substitutes target AST node in RAM in <50 microseconds.")

;; 3. Codebase Diagnostic Matrix
(:tool :name "eddie-health"
       :params [scope:Str]
       :doc "Returns structural cycles, orphan symbols, type drift, and high-risk hotspots.")

;; 4. Ephemeral Knowledge Lifecycle
(:tool :name "knowledge-load"
       :params [target:Str slot:Str]
       :doc "Loads distilled version-pinned API into ephemeral context slot.")

(:tool :name "knowledge-offload"
       :params [slot:Str emit-receipt:Bool]
       :doc "Evicts ephemeral knowledge, minting concise semantic receipt.")

;; 5. Intent Graph Traceability
(:tool :name "intent-query"
       :params [entity-id:Str relation:Str depth:I64]
       :doc "Traverses relational hypergraph linking code symbols to requirements and decisions.")
```
