# Architectural Specification: Deterministic L7 Cognitive Gateway & Execution Harness (GenSEAM / ASL)
**Document ID:** SPEC-2026-GATEWAY-HARNESS-v1.0  
**Classification:** Technical Architecture Standard & Implementation Contract  
**Applies to:** `packages/asl-gateway`, `packages/harness`, `packages/agent-core`, `packages/asl-lens`

---

## 1. System Philosophy & Ontological Decomposition

Current autonomous AI agent frameworks suffer from a foundational architectural flaw: **the stochastic conflation of computation, state, routing, and verification within the model's attention window.**

```
+-------------------------------------------------------------------------------+
|                             SYSTEM ONTOLOGY                                   |
|                                                                               |
|  [ LLM Inference Engine ]  <--- Stochastic CPU / Arithmetic Logic Unit (ALU)   |
|  [ Model Context Window ]  <--- Ephemeral Register Stack (Minimal Footprint)  |
|  [ L7 Gateway / Harness ]  <--- Deterministic Operating System (Process Mgr)  |
|  [ External Blackboard  ]  <--- Transactional MVCC RAM (DAG & Knowledge Graph)|
+-------------------------------------------------------------------------------+
```

### 1.1. Core Postulates
1. **The LLM is an ALU, not a Database or Controller:** The language model transforms semantic tokens. It possesses zero guarantee of causal memory, spatial invariants, or chronological consistency.
2. **Context as Cache, Not Storage:** Storing long-term state in the prompt induces quadratic attention cost ($O(N^2)$), attention dilution ("Lost-in-the-Middle"), and invariant erosion. State must reside in an external, persistent, content-addressed Blackboard.
3. **Dual Deployment Topologies:**
   * **Boundary L7 Gateway (Network Barrier):** Sits between client/subagents and external model providers (OpenAI, Anthropic, Gemini, local Ollama). Handles streaming bifurcation, constrained decoding, and token-level guardrails.
   * **Embedded Execution Harness (In-Process Super-visor):** Embedded inside the agent worker process. Jails syscalls, manages memory slices, executes JIT-compiled Wasm tools, and audits file modifications via AST diffing.

---

## 2. Blackboard State Hierarchy & Task-Premise DAG

All persistent state is removed from the model's prompt and organized into a 4-tier immutable memory hierarchy.

```
+-------------------------------------------------------------------------------+
|                         BLACKBOARD MEMORY HIERARCHY                           |
+-------------------------------------------------------------------------------+
| Tier 4: Dynamic Hydration Frame  | Ephemeral AST slice for current atomic step|
| Tier 3: Artifact & Fact Store    | Perceptual Pointers, scalar verified facts |
| Tier 2: Task-Premise DAG G=(V,E,P| State transitions, dependencies, predicates|
| Tier 1: Immutable Invariants     | Root domain constraints & negative rules   |
+-------------------------------------------------------------------------------+
```

### 2.1. Mathematical Formulation of the Task-Premise DAG
The execution plan is formalized as a directed acyclic graph with explicit logical assumptions:

$$G = (V, E, P, H)$$

Where:
* $V = \{v_1, v_2, \dots, v_n\}$ — set of discrete task nodes. Each node $v_i$ possesses a Finite State Machine:
  $$\text{State}(v_i) \in \{\text{Pending}, \text{Active}, \text{Completed}, \text{Failed}, \text{Invalidated}, \text{Suspended\_HITL}\}$$
* $E \subseteq V \times V$ — directed dependency edges. $(v_i, v_j) \in E$ dictates that task $v_j$ cannot transition to `Active` until $v_i$ achieves verified `Completed` status.
* $P = \{p_1, p_2, \dots, p_k\}$ — set of explicit contextual predicates/hypotheses upon which branches depend (e.g., $p_1$: "Underlying database supports sub-millisecond vector indexing").
* $H: V \to \mathcal{P}(P)$ — mapping from task nodes to their dependent premise set.

### 2.2. Structural Sharing, OCC & Concurrency (Fan-Out)
* **Persistent Immutable Tree:** DAG state transitions utilize structural sharing. Any state mutation creates a new version root $R_{t+1} = \text{commit}(R_t, \Delta)$, retaining references to unmodified subtrees. Snapshot creation and rollback are $O(1)$ operations.
* **Optimistic Concurrency Control (OCC):** When parallel subagents execute concurrent tasks, state updates apply via atomic Compare-And-Swap (CAS) on the version pointer:
  $$\text{CAS}(\&R_{\text{head}}, R_{\text{expected}}, R_{\text{new}})$$
  Upon collision, conflicting branches branch into isolated worktrees, escalated to the arbitration scheduler.

### 2.3. Premise Invalidation, Falsification Registry & Monotonic Time-Travel
* **Cascading Invalidation:** If a premise $p_x \in P$ is disproven during execution ($\neg p_x$):
  $$\forall v \in V \text{ where } p_x \in H(v) \implies \text{State}(v) \leftarrow \text{Invalidated}$$
* **Pruning and Rollback:**
  1. Active child processes tied to invalidated nodes are sent immediate `SIGKILL` / `AbortSignal`.
  2. Associated ephemeral filesystem worktrees (`UpperDir`) are wiped.
  3. The active Blackboard version pointer rewinds to the nearest checkpoint prior to the branch bifurcation point.
* **Falsified Premise Registry:** Disproven premises are recorded in an append-only blacklist $\mathcal{F}_{\text{falsified}}$. The orchestrator is mathematically prohibited from scheduling tasks that rely on any $p \in \mathcal{F}_{\text{falsified}}$, terminating infinite oscillation loops.

---

## 3. Perceptual Offloading & Perceptual Pointers

To eliminate attention bloat, raw multimodal inputs (audio streams, video, high-resolution DOM captures, full-text PDFs) are intercepted at the L7 ingress and converted into lightweight **Perceptual Pointers**.

```
+-----------------------------------------------------------------------------------+
|                        PERCEPTUAL POINTER SCHEMA                                  |
+-----------------------------------------------------------------------------------+
| Raw Artifact (Audio/Video/DOM/PDF) ---> Content-Addressed Blob Storage (BLAKE3)   |
|                                                                                   |
| Pointer Token Emitted:                                                            |
| (:ptr :id "b3-7f8a..." :kind @dom :tokens-saved 8420 :summary "..." :slice-fn ...) |
+-----------------------------------------------------------------------------------+
```

### 3.1. Pointer Dereference Protocol
The coordinator agent is strictly forbidden from directly ingesting raw media payloads. When deep inspection is required:
1. Coordinator emits a query request: `(ptr-deref :id "b3-7f8a" :query "Verify button label" :region [100, 20, 250, 60])`.
2. Gateway routes the request to an isolated, ephemeral **Perception Subagent** running in a sterile context window.
3. The Perception Subagent extracts the answer and returns exclusively a verified scalar fact to the Blackboard:
   `(:fact :key "login_button_label" :val "Continue with SSO" :confidence 0.99)`.
4. The coordinator's attention window remains unpolluted by high-dimensional tokens.

---

## 4. Dual-Tier Execution Plane & Sandboxing

All agent interactions with external systems pass through an intercepted four-stage lifecycle:
$$\text{Input} \longrightarrow \text{[Pre-Execution Gate]} \longrightarrow \text{[Sandbox]} \longrightarrow \text{[Post-Execution Audit]} \longrightarrow \text{[Trace Sanitizer]}$$

```
+-------------------------------------------------------------------------------+
|                       TWO-TIER SANDBOX ARCHITECTURE                           |
+-------------------------------------------------------------------------------+
| TIER 1: In-Memory Wasm/WASI (Sub-millisecond JIT)                             |
|  - Engine: Wasm3 (interpreter) / Wasmtime (JIT) / Native Browser Wasm         |
|  - Startup: < 0.05 ms | Memory: Flat Linear Heap (64KB - 16MB)                |
|  - Isolation: Strict capability-based I/O | Instruction Fuel Limiter          |
|  - Use: On-The-Fly Ephemeral Tool Synthesis, Data Parsers, Math, ASL Scripts  |
+-------------------------------------------------------------------------------+
| TIER 2: Hardware-Virtual / Worktree Sandbox (OverlayFS)                       |
|  - Engine: Git Worktree + Ephemeral RAM OverlayFS                             |
|  - Storage: LowerDir (Base Repo, RO) | UpperDir (RAM disk scratchpad, RW)     |
|  - Rollback: rm -rf UpperDir (Instant O(1) clean state restoration)           |
|  - Use: Native Compilers (rustc, gcc), Integration Tests, Shell Commands     |
+-------------------------------------------------------------------------------+
```

### 4.1. On-The-Fly Tool Synthesis (JIT Ephemeral Tools)
When an agent encounters a domain problem lacking an existing tool:
1. Agent generates a pure, single-pass ASL micro-module.
2. The compiler compiles the module directly into `wasm32-wasip1` in memory.
3. The module executes inside Tier-1 sandbox with fixed fuel allocation (e.g., $10^6$ instructions).
4. Result is recorded to Blackboard; Wasm instance memory is immediately recycled.

---

## 5. Epistemic Grounding & Anti-Hallucination Gatekeeper

The gateway classifies and suppresses model hallucinations across five distinct failure modes:

| Failure Mode | Failure Taxonomy | Deterministic Gatekeeper Enforcement |
|---|---|---|
| **TSH** (Tool Selection Hallucination) | Invoking nonexistent tools or cross-domain tools | **Trie-Based Logit Masking:** Valid tool tokens constrained to allowable subset of active DAG phase. |
| **TCH** (Tool Constraint Hallucination) | Type errors, missing parameters, invalid formats | **Grammar-Constrained Decoding:** CFG/FSM enforcement over ASN schema parameters during token generation. |
| **ESH** (Execution State Hallucination) | Model asserts action completed without runtime evidence | **Acoustic/Verbal Ban:** Execution status set strictly by host exit code, never by model natural language. |
| **IE** (Invariant Erosion) | Model forgets prohibitions in long multi-turn sessions | **Verbatim Injection:** Non-summarized immutable negatives injected into every system frame prefix. |
| **FC** (Factual / Citation Drift) | Fabricated quotes or invalid timestamps | **Dual-Track Grounding Gate:** Direct quotes verified via LCS ($F_\beta \ge 0.95$), claims verified via Entailment. |

### 5.1. AST Diffing Gate
To defeat the common LLM failure pattern where a model passes tests by deleting or commenting out assertions:
1. Pre-execution AST is cached: $T_{\text{pre}} = \text{Parse}(F)$.
2. Post-execution AST is extracted: $T_{\text{post}} = \text{Parse}(F')$.
3. Structural Delta is computed:
   $$\Delta_{\text{AST}} = T_{\text{post}} \setminus T_{\text{pre}}$$
4. If $\Delta_{\text{AST}}$ contains mutations within protected nodes (test files, invariant assertions, build manifests), the commit is rejected with `AST_MUTATION_FORBIDDEN`.

### 5.2. Dual-Track Grounding Protocols
* **Direct Quotes:** Identified by `<quote>` delimiter tags. Grounding engine computes the Longest Common Subsequence (LCS) against source texts. If token match precision $F_\beta < 0.95$, frame is dropped with `HALLUCINATED_CITATION`.
* **Synthetic Claims:** Analytical summaries undergo entity verification: all Named Entities, numbers, units, and dates must exist in registered source artifacts, validated through logical entailment checking.

---

## 6. End-to-End Protocols & Gap Remediation

The architecture incorporates 12 cross-cutting protocols resolving inter-system gaps:

1. **Context Hydration:** Context windows receive strictly the minimal required AST slice, dependent interface definitions, and immediate task invariants.
2. **AST Mutation Gate:** Structural diffing replaces all self-reported agent summaries.
3. **Premise Rollback:** Atomic branch invalidation and RAM worktree purge on assumption failure.
4. **Synthetic Convergence Gate:** Before merging parallel DAG branches at a `Join` node, the harness automatically runs a global type-check and cross-module interface verification step.
5. **Trace Sanitization:** Error outputs are stripped of library noise, isolating failing assertions and immediate source lines to $< 300$ tokens.
6. **Immutable Negatives Registry:** System-level prohibitions bypass summarization and inject verbatim into every prompt.
7. **Saga Triad & Compensation Barrier:**
   * Tools categorized: `Reversible`, `Irreversible`, `Idempotent`.
   * `Irreversible` operations require a 2-Phase Hold and are blocked in speculative branches until premise validation.
   * `Reversible` operations register a LIFO compensation action in the undo log.
8. **Two-Tier Tool-Paging:** Vector pre-filtering of tool schemas + `system.discover_tools(query)` escape hatch.
9. **RFC 8785 Canonical Serialization:** Key-sorted deterministic JSON/ASN serialization ensuring maximum KV-cache hits.
10. **Durable Suspension & HITL:** Safe process state serialization to disk with cryptographically signed `ResumeToken` for human-in-the-loop pauses.
11. **Write-Ahead Intent:** Write-ahead logging with unique idempotency keys prior to tool invocation.
12. **Falsified Premise Registry:** Append-only memory of disproven hypotheses preventing cyclic regression.

---

## 7. Stream Bifurcation & Telemetry Architecture

```
[ Model Output Stream ]
          │
          ├──> Channel A: User Interface Socket (Natural language tokens, smoothed)
          ├──> Channel B: Quarantined CoT Stream (Internal thought process held in metadata buffer)
          └──> Channel C: Structural Tool Frame (Intercepted, validated, executed in Sandbox)
```

* **CoT Quarantine:** Raw reasoning tokens are segregated from user-facing streams to prevent premature disclosure of actions that might be blocked by pre-execution gates.
* **Circuit Budget Breaker:** Tasks have fixed token and monetary thresholds:
  Tier 1 Model (Fast) $\xrightarrow{\text{Failure}}$ Sanitized Retry $\xrightarrow{\text{Failure}}$ Tier 2 Model (Reasoning) $\xrightarrow{\text{Exhaustion}}$ `Suspended_HITL`.

---

## 8. Multi-Dimensional Observability & Cartography (`@genseam/asl-lens`)

To provide immediate topological comprehension for both autonomous agents and human operators via a web dashboard, the system defines the `asl-lens` inspection interface.

### 8.1. Agent Topological Query (`lens:inspect-topology`)
Emits a compact ASN-encoded structural snapshot:
```lisp
(:lens-summary
  :workspace "@genseam/workspace"
  :modules [
    (:m "asl-mem" :exports ["VectorStore" "MemoryEngine"] :imports ["core"] :status :green)
    (:m "asl-bus" :exports ["SeamBus" "Mesh"] :imports ["asl-skyloom" "asl-mem"] :status :green)
    (:m "asl-gateway" :exports ["L7Gateway" "TrieFilter"] :imports ["harness"] :status :green)
  ]
  :dependency-drift [
    (:pkg "wasmtime" :installed "18.0.0" :latest "24.0.0" :breaking-risk :medium)
  ]
  :circular-dependencies []
  :unreferenced-exports ["asl-mem/paged:slab-debug-dump"]
)
```

### 8.2. Web Cockpit Stream Protocol
`asl-gateway` exposes an SSE/WebSocket endpoint emitting the live telemetry graph:
* **Node Attributes:** Module identity, cyclomatic complexity, token consumption, health state (`green`, `amber`, `red`).
* **Edge Attributes:** Real-time AgP frame throughput, message latencies, active capability locks.
* **Gatekeeper HUD:** Live counts of suppressed hallucinations (TSH, TCH, AST, LCS).

---

## 9. Implementation Roadmap & Package Mapping

| Package | Path | Responsibility | Core New Deliverables |
|---|---|---|---|
| `@genseam/asl-gateway` | `packages/asl-gateway` | L7 Boundary Gateway | Trie token masker, RFC 8785 normalizer, Stream bifurcator, CoT quarantine |
| `@genseam/asl-harness` | `packages/harness` | Execution Harness | Tier-1 Wasm JIT runner, AST Diffing Gate, Trace Sanitizer, Saga rollback |
| `@genseam/asl-core` | `packages/agent-core` | Blackboard Engine | Task-Premise DAG $G=(V,E,P)$, OCC structural sharing, Falsified Premise log |
| `@genseam/asl-lens` | `packages/asl-lens` | Architecture Cartography | Static AST dependency analyzer, dependency drift radar, Web Cockpit API |
| `@genseam/asl-cockpit` | `apps/asl-cockpit` | Operator Dashboard | Interactive Cytoscape/React Flow DAG visualizer, Time-travel debugger UI |

---

## 10. The Pluggable Constructor & Multi-Tier Extensibility Architecture

The entire GenSEAM / AgentScript ecosystem is architected as an **open, modular constructor** rather than a rigid monolithic runtime. Out-of-the-box, it ships with battle-tested, optimal defaults calibrated for the target model (Gemma 31B), while exposing granular configuration toggles, model profiles, experimental flags, and a dual-tier plugin system.

```
+-------------------------------------------------------------------------+
|                  Tier 2: Language & Compiler Extensions                 |
|  * Custom Compilation Backends (Stylus Wasm, EVM, eBPF, Native LLVM)   |
|  * Dialect Macros & AST Transforms (@genseam/asl-plugin)                |
|  * Foreign Host Capabilities (Cap-DB, Cap-FS, Cap-Net, Cap-Wasm)       |
+-------------------------------------------------------------------------+
                                    |
                                    v
+-------------------------------------------------------------------------+
|                 Tier 1: Harness Middleware & Plugin Pipeline            |
|  * Model Optimization Profiles (Gemma 31B, Claude, DeepSeek, Custom)    |
|  * Granular Feature Flags (Firewall, FSM Normalizer, In-Memory REPL)    |
|  * Experimental Feature Sandbox (:experimental ["exp-speculative"...]) |
|  * Pluggable Tool Interceptors & Security Middleware (Onion Pipeline)   |
+-------------------------------------------------------------------------+
```

### 10.1. Declarative Configuration & Model Profiles
The harness configuration (`HarnessConfig` in `harness/src/config.asl`) allows users and autonomous agents to declaratively customize runtime behavior:
- **Optimal Defaults**: Ships with `profile-gemma-31b` enabled by default (strict Action Firewall, single-pass FSM normalizer, sub-millisecond in-memory REPL, ASN perceptual pointers).
- **Profile Switching**: Easily swapped to alternative model families (Claude, DeepSeek, Llama) with distinct token budgets and cognitive boundary rules.
- **Granular Toggles**: Every individual mechanism (firewall, cache, normalizer, REPL, lens) can be toggled independently via `toggle-feature`.

### 10.2. Experimental Sandboxing
Cutting-edge heuristics and experimental capabilities are safely isolated behind experimental feature flags (`enable-experimental` / `experimental-enabled?`):
- Speculative token generation & grammar caching.
- SMT-driven live pre-flight constraint validation.
- Custom vector memory quantizers and hardware-accelerated SIMD kernels.

### 10.3. Two-Tier User Extensibility Model
1. **Harness Runtime Plugins**: Community developers can author plugins implementing `HarnessPlugin` and register them via `register-plugin`. Plugins hook into pre-call, post-call, model-response, and error stages of the execution lifecycle.
2. **Language & Compiler Plugins (`asl-plugin`)**: Developers can extend AgentScript itself by authoring Wasm or FFI plugins providing custom capabilities, adding custom AST syntax macros, or compiling ASL contracts to novel target execution environments (such as Arbitrum Stylus Wasm, Solana BPF, or RISC-V microcontrollers).

