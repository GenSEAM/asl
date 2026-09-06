# Large-Scale Codebase Intelligence, Adaptive Graph Memory & Dependency RAG Specification
**Document ID:** SPEC-2026-CODEBASE-INTEL-v1.0  
**Classification:** Engineering Specification & Implementation Standard  
**Applies to:** `packages/intel`, `packages/mem`, `packages/harness`, `packages/lens`

---

## 1. The Autonomous Engineering Problem Space in Large Codebases

When autonomous software agents operate on real-world, enterprise-scale repositories (100,000+ lines of code, polyglot monorepos, multi-package workspaces), standard file-based retrieval mechanisms (`grep`, `find`, `cat`) suffer catastrophic cognitive collapse.

### 1.1. The Taxonomy of Real-World Agent Coding Failures

```
+-----------------------------------------------------------------------------------------------+
|                       TAXONOMY OF AGENT DEGRADATION IN LARGE REPOSITORIES                     |
+-----------------------------------+-----------------------------------------------------------+
| Failure Category                  | Root Cause & Real-World Mechanism                         |
+-----------------------------------+-----------------------------------------------------------+
| 1. The "Ghost API" Syndrome       | Model trained on Library v1 (e.g. Pydantic v1, React 18); |
|    (Version-Skew Hallucination)   | Repo uses Library v2 (Pydantic v2, React 19). Model emits |
|                                   | deprecated methods (.dict(), useFormState) with 100%      |
|                                   | syntactic confidence, failing at runtime.                 |
+-----------------------------------+-----------------------------------------------------------+
| 2. Invisible Blast Radius         | Agent edits an internal utility in Module A. Module A's   |
|    (Transitive Breakage)          | local tests pass, but the function is exported across 14  |
|                                   | packages in the monorepo. Downstream microservices fail.  |
+-----------------------------------+-----------------------------------------------------------+
| 3. Reinventing the Wheel          | In a 250k-line repo, canonical utilities already exist     |
|    (Duplication Drift)            | (e.g. `format_currency`, `jwt_verifier`). Unable to locate|
|                                   | them, the agent generates ad-hoc duplicates with bugs.    |
+-----------------------------------+-----------------------------------------------------------+
| 4. Circular Architectural Suicide | Agent requires data from Module B in Module A. It adds an |
|    (Dependency Cycles)            | import. Module B already imports A. Node.js/Python emit   |
|                                   | undefined exports; Rust/Go fail with compilation errors.  |
+-----------------------------------+-----------------------------------------------------------+
| 5. Context Drowning               | Agent loads 4 full files (3,000 lines) into context to    |
|    (Attention Dilution)           | inspect 3 type signatures. 85% of tokens are consumed by  |
|                                   | irrelevant function bodies, causing "Lost-in-the-Middle". |
+-----------------------------------+-----------------------------------------------------------+
```

---

## 2. Adaptive Memory Topology: 3-Tier Representation Hierarchy

To make large codebases queryable in real time without unbounded RAM consumption, the codebase representation is split into three strictly bounded abstraction tiers:

```
+-------------------------------------------------------------------------------+
|                      3-TIER CODEBASE MEMORY ARCHITECTURE                      |
+-------------------------------------------------------------------------------+
| TIER 1: MACRO-TOPOLOGY (Always Resident in RAM: ~150 KB - 500 KB)             |
|  - Module DAG: exports (:x), imports (:i), circularity check, package boundary|
|  - File hash tree: BLAKE3 content hashes for instant O(1) change detection    |
+-------------------------------------------------------------------------------+
| TIER 2: MESO-SYMBOL GRAPH (LRU Paged Memory: ~2 MB - 8 MB in RAM)             |
|  - Entities: Function signatures, type definitions, record schemas, enums     |
|  - Relational Edges: calls, defines, imports, implements, subtypes            |
|  - Footprint: Zero function bodies. Exclusively typed interface stubs.        |
+-------------------------------------------------------------------------------+
| TIER 3: MICRO-AST SLICES (On-Demand JIT Cache: Strictly Bounded to Target)   |
|  - Concrete S-expression / AST bodies of functions currently being patched.   |
|  - Lifetime: Ephemeral. Evicted or committed back to storage upon step exit.  |
+-------------------------------------------------------------------------------+
```

---

## 3. Dynamic Graph Horizon Expansion (Scoped Preloading)

Instead of relying on an LLM to guess what files to open, the agent operates through an automated **Graph Horizon Expansion** mechanism with an immutable token ceiling.

### 3.1. Mathematical Formulation
Let $G = (V, E)$ be the Symbol Graph. For a target module or symbol $m \in V$, the preloaded horizon $H(m, k, B)$ is defined as:

$$H(m, k, B) = \left\{ n \in V \;\middle|\; \text{dist}(m, n) \le k \;\land\; \text{weight}(n) \ge \theta \;\land\; \sum_{x \in H} \text{Tokens}(x) \le B \right\}$$

Where:
* $k$ — maximum graph traversal depth (default: 2 hops).
* $\text{dist}(m, n)$ — shortest path along directed edges (`calls`, `imports`, `implements`).
* $B$ — strict token budget (e.g. 4,000 tokens).
* $\text{Tokens}(x)$ — token cost of symbol $x$'s representation.

### 3.2. Granular Tiered Hydration Strategy
When traversing the graph horizon:
* **Distance 0 (Target Module):** Hydrated at **Tier 3 (Micro-AST)** — full source code loaded for immediate inspection and modification.
* **Distance 1 (Direct Dependencies & Callers):** Hydrated at **Tier 2 (Meso-Symbol)** — public signatures and type definitions only (Valid Stub Invariant, saving 78% tokens).
* **Distance 2 (Transitive Boundaries):** Hydrated at **Tier 1 (Macro-Topology)** — module name, symbol names, and 1-line docstrings only.

---

## 4. Lockfile Introspection & Version-Pinned Documentation RAG

A fatal flaw in standard RAG is fetching generic, unversioned documentation from the public internet. If the project locks `zod@3.21.4`, but the RAG engine retrieves documentation for `zod@3.23.8` (which introduced new schema helpers), the agent will write uncompilable code.

```
[ Project Workspace ]
       │
       ▼
[ Lockfile Parser Engine ]
  • Extracts exact pinned versions:
    - pnpm-lock.yaml / package-lock.json (NPM)
    - Cargo.lock (Rust Crates)
    - poetry.lock / requirements.txt (Python)
       │
       ▼
[ Version-Pinned Type & Doc Extractor ]
  • Local First: Introspects installed node_modules, target/doc, or .venv
  • Remote Fallback (Dev Only): Fetches exact semver .d.ts or docs.rs JSON
       │
       ▼
[ Type-Dense API Skeletonizer ]
  • Strips natural language marketing filler
  • Preserves strictly exported interfaces and parameter schemas
       │
       ▼
[ Blackboard Knowledge Store: (:pkg-spec :name "..." :version "..." :types [...]) ]
```

### 4.1. The Anti-Cheating Execution Policy
* **Benchmark Mode (SWE-bench / Formal Eval):** All external network requests to NPM, PyPI, and docs.rs are **physically severed**. The agent operates in a hermetic sandbox using exclusively local lockfile introspection and local type definitions.
* **Production Dev Mode:** On-demand pinned doc fetching is enabled as a background coprocessor. If an agent encounters an unfamiliar library symbol, it invokes `deps.inspect(package: "zod", symbol: "safeParse")` to receive the exact signature for the installed version.

---

## 5. Automated Codebase Health & Anomaly Detection

Before allowing an agent to commit a code modification, the system generates an instant **Structural Health Matrix** by querying the Symbol Graph:

### 5.1. The 5 Structural Health Invariants
1. **Fan-In / Blast Radius Warning:** Flag any node where $\text{InDegree}(v) \ge 10$ (high-risk core utility). Modifications require explicit confirmation or multi-file patch generation.
2. **Circular Dependency Barrier:** Detect any cycle in $G_{\text{imports}}$:
   $$\text{HasCycle}(G) \implies \text{Block commit with CYCLE\_DETECTED}.$$
3. **Ghost / Zombie Export Detection:** Flag symbols declared in `:x` (exports) that have zero incoming references across the entire workspace ($\text{InDegree}(v) = 0$).
4. **Signature Compatibility Verification:** For every call site edge $(u, v) \in E_{\text{calls}}$, verify that $\text{Arity}(u) = \text{Arity}(v)$ and argument types conform to parameter types.
5. **Cyclomatic Complexity Hotspots:** Highlight functions where branching factor $> 15$ for automated decomposition.

---

## 6. Extended Tooling Interface for Autonomous Agents

To empower agents to navigate large codebases efficiently, the harness tool plane is extended with 5 specialized capabilities:

```lisp
;; 1. Scoped Preloading with Token Ceiling
(:tool :name "intel-preload"
       :params [target:Str depth:I64 token-budget:I64]
       :doc "Traverses symbol graph from target, preloading tiered interfaces up to budget.")

;; 2. Blast Radius Calculation
(:tool :name "intel-impact"
       :params [symbol:Str]
       :doc "Returns transitive callers and affected modules before applying changes.")

;; 3. Codebase Diagnostic Matrix
(:tool :name "intel-health"
       :params [scope:Str]
       :doc "Returns structural anomalies: circular imports, orphan exports, type mismatches.")

;; 4. Version-Pinned Library Inspection
(:tool :name "deps-resolve"
       :params [package:Str symbol:Str]
       :doc "Inspects lockfile and returns exact type signature for installed library version.")

;; 5. In-Memory Surgical AST Mutation
(:tool :name "ast-patch"
       :params [path:Str symbol:Str replacement:Str]
       :doc "Substitutes specific AST node in memory in <50 microseconds without disk rewrite.")
```
