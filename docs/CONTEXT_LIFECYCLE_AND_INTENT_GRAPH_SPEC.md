# Architectural Specification: Context Lifecycle Management, Prompt VMM & Relational Intent Hypergraph
**Document ID:** SPEC-2026-CONTEXT-INTENT-v1.0  
**Classification:** Engineering Standard & Knowledge Substrate Specification  
**Applies to:** `packages/intel`, `packages/mem`, `packages/harness`, `packages/gateway`

---

## 1. Executive Summary & Problem Formulation

Standard autonomous agent systems suffer from **Linear Context Exhaustion**: as session turns increase and codebases grow, the prompt is monotonically filled with historical logs, entire file contents, library documentations, and disconnected natural language commentary.

```
+-------------------------------------------------------------------------------+
|                       THE PROMPT EXHAUSTION CRISIS                            |
|                                                                               |
|  Traditional Agent Prompt:                                                    |
|  [System Instructions] + [Full Library Docs (4k)] + [File A (2k)] +           |
|  [File B (3k)] + [Chat History (15k)] + [Console Dumps (8k)] = 32k Tokens!    |
|                                                                               |
|  Result: Extreme Latency, Massive API Costs, Attention Loss (Lost-in-Middle). |
+-------------------------------------------------------------------------------+
```

This specification establishes an enterprise-grade solution based on two unified paradigms:
1. **The Prompt Virtual Memory Manager (Prompt VMM):** Segmented, ephemeral context frames with dynamic JIT knowledge loading, automatic semantic compaction, and offloading with cryptographic reference receipts.
2. **The Relational Intent-Code Hypergraph (PCP 2.0):** A multi-aspect knowledge substrate unifying Use Cases, Requirements, Architectural Decisions (ADRs), Plans, Constraints, and Code AST nodes into an interconnected graph queryable in sub-milliseconds.

---

## 2. Prompt VMM: Context Segmentation, JIT Paging & Offloading

Instead of treating the context window as a flat, monotonic text append buffer, the prompt is structured into formal **Context Segments** governed by a deterministic Virtual Memory Manager.

```
+-------------------------------------------------------------------------------+
|                       PROMPT VMM CONTEXT ENVELOPE                             |
+-------------------------------------------------------------------------------+
| Segment 1: Invariable Anchor      | System constitution, immutable invariants  |
| Segment 2: Semantic Receipts      | 1-line cryptographic stubs of past turns  |
| Segment 3: Pinned Knowledge Slot  | Ephemeral JIT library/API frame (Paged)   |
| Segment 4: Active Working Frame   | Current atomic task, local AST slice      |
+-------------------------------------------------------------------------------+
```

### 2.1. The Ephemeral Knowledge Lifecycle (Load -> Operate -> Offload)
When an agent needs to work with a third-party library, external framework, or complex internal module:

```
[ Step 1: Request Knowledge ]
  Agent emits: (:call knowledge-load :target "zod@3.22.4" :slot :library-slot)
       │
       ▼
[ Step 2: Hydrate Pinned Knowledge Slot ]
  Gateway pages in the distilled API skeleton (180 tokens) into Segment 3.
       │
       ▼
[ Step 3: Execute Domain Operations ]
  Agent writes code using exact verified signatures.
       │
       ▼
[ Step 4: Atomic Knowledge Offload & Receipt Minting ]
  Agent emits: (:call knowledge-offload :slot :library-slot :emit-receipt true)
  VMM wipes the 180 tokens from Segment 3 and appends a 12-token Semantic Receipt
  into Segment 2:
  `(:receipt :target "zod@3.22.4" :action "defined-schema" :anchor "auth.asl:24")`
```

* **Quantitative Impact:** The detailed documentation exists in the context window **for exactly one cognitive turn**. Subsequent turns carry only the 12-token receipt. If the agent needs to revisit the library 10 turns later, it simply references the receipt or re-pages the slot.

### 2.2. Sliding-Window Semantic Compaction with Anchor Ledgers
In accordance with [harness/src/compactor.asl](file:///Users/purplelephant/projects/asex/harness/src/compactor.asl):
* Turns $T_{n-1}$ and $T_{n}$ are retained in high-fidelity verbatim S-expression representation.
* Turns $T_0$ to $T_{n-2}$ are structurally collapsed by the VMM into monotonic **Semantic Receipts**:
  * Raw terminal output (500 lines of build logs) $\to$ `(:receipt :step "build" :status :pass :exit-code 0)` (99.2% token reduction).
  * Whole file reads (800 lines) $\to$ `(:receipt :step "inspect" :file "engine.asl" :symbols ["search-knn" "dot"])`.

---

## 3. The Relational Intent-Code Hypergraph (PCP 2.0)

Code does not exist in a vacuum. Disconnected source code without intent produces hallucinations; disconnected documentation without code anchors produces documentation rot.

The system formalizes the codebase knowledge base as an attributed directed hypergraph:

$$\mathcal{H} = (\mathcal{V}, \mathcal{E})$$

```
          [ Plan / Milestone (P) ]
                     │ :schedules
                     ▼
          [ Requirement (R) ] ◄─── :governs ─── [ Decision / ADR (D) ]
             ▲            │                         │
  :validates │            │ :fulfills               │ :constrains
             │            ▼                         ▼
     [ Use Case (U) ] ──► [ Code AST Node (C) ] ◄─── [ Invariant (C_t) ]
               :implements
```

### 3.1. Entity Taxonomy ($\mathcal{V}$)

| Entity Kind | Code Prefix | Purpose & Semantics | Storage Representation |
|---|---|---|---|
| **Use Case ($U$)** | `uc-xxxx` | End-to-end user journeys, functional scenarios, integration test specs | Markdown scenario / ASN record |
| **Requirement ($R$)** | `req-xxxx` / `r-xxxx` | Functional and non-functional requirements, acceptance criteria | Markdown contract with formal predicates |
| **Decision / ADR ($D$)** | `d-xxxx` | Architectural choices, alternatives evaluated, trade-offs accepted | Git-native ADR file in `.pcp/` |
| **Constraint / Invariant ($C_t$)** | `c-xxxx` | Immutable negative rules, security boundaries, performance ceilings | Verbatim rules injected into prompt |
| **Code AST Node ($C$)** | `@sym:...` | Concrete function, type declaration, module, or S-expression form | Source file coordinate + AST node hash |
| **Plan / Milestone ($P$)** | `plan-xxxx` | Strategic roadmap, phase gates, execution dependency DAG | Roadmap node with status FSM |

### 3.2. Relational Edge Calculus ($\mathcal{E}$)

Every link in the hypergraph represents a strongly-typed, bidirectional semantic relation:
1. **`fulfills(C, R)`**: AST node $C$ implements requirement $R$.
2. **`validates(U, R)`**: Use Case $U$ provides the verification criterion for requirement $R$.
3. **`implements(C, U)`**: AST node $C$ executes the workflow specified in Use Case $U$.
4. **`governs(D, R)` / `governs(D, C)`**: Architectural Decision $D$ dictates the design of requirement $R$ or code node $C$.
5. **`constrained_by(C, C_t)`**: Code node $C$ is bound by invariant $C_t$ (verified via AST Diffing Gate).
6. **`schedules(P, R)`**: Milestone $P$ gates the release of requirement $R$.

### 3.3. Transitive Blast Radius & Traceability Queries
With the hypergraph compiled in memory:
* **Forward Impact Query:** *«If requirement `req-auth-02` changes, what code symbols ($C$), use cases ($U$), and decisions ($D$) are invalidated?»*
* **Backward Attribution Query:** *«Why does function `paged/slab-slot-offset` exist in `store.asl`?»*  
  $\implies$ Traces back: `store.asl:140` $\xrightarrow{\text{fulfills}}$ `r-vector-64k` $\xrightarrow{\text{governed\_by}}$ `d-sq8-quantization` $\xrightarrow{\text{validates}}$ `uc-benchmark-swe001`.

---

## 4. Dual-Tier Storage Engine: Git-Native on Disk $\leftrightarrow$ In-Memory Paged Wasm Slab

To ensure the knowledge base scales to millions of nodes without unbounded memory growth or process crashes:

```
+-------------------------------------------------------------------------------+
|                       DUAL-TIER KNOWLEDGE ENGINE                              |
+-------------------------------------------------------------------------------+
| TIER 1: Human-Readable Git-Native Disk Layer (.pcp/, .mem/, ADRs)             |
|  - Storage: Structured Markdown files + MAP.json / INVENTORY.json             |
|  - Auditability: 100% version-controlled via Git. Zero proprietary DB locks.  |
|  - Addressing: Short 6-char content hashes (@pcp:d-84a9, @req:r-7ea3)         |
+-------------------------------------------------------------------------------+
|                       │ Background Compiler / Indexer                         |
|                       ▼ (< 5 ms per 1,000 entities)                           |
+-------------------------------------------------------------------------------+
| TIER 2: High-Performance In-Memory Wasm Graph Slab (asl-mem + asl-intel)      |
|  - Storage: Contiguous typed arrays (nodes array + CSR adjacency matrix)      |
|  - Paging: Adaptive LRU segment paging (paged.asl) with strict max-bytes cap  |
|  - Performance: O(1) symbol lookup, sub-millisecond BFS traversal            |
+-------------------------------------------------------------------------------+
```

### 4.1. Memory Bounds & LRU Segment Eviction
When the knowledge graph exceeds the resident memory budget (e.g. 16 MB in `PagedMemoryManager`):
1. Knowledge is partitioned into **Domain Segments** (e.g., `seg:auth`, `seg:storage`, `seg:compiler`).
2. Only the active segment and its 1-hop cross-segment dependencies remain resident in RAM.
3. Inactive segments are unmapped to disk cache, completely eliminating Out-Of-Memory (OOM) failures.

---

## 5. Extended Agent Toolset for Context & Intent Management

The harness exposes 6 specialized tools allowing agents to navigate and manipulate the intent-code hypergraph:

```lisp
;; 1. Load ephemeral knowledge pack into pinned slot
(:tool :name "knowledge-load"
       :params [target:Str slot:Str]
       :doc "Pages in distilled API or domain knowledge into ephemeral context slot.")

;; 2. Evict ephemeral knowledge and mint semantic receipt
(:tool :name "knowledge-offload"
       :params [slot:Str emit-receipt:Bool]
       :doc "Wipes knowledge slot from context, appending concise 1-line receipt.")

;; 3. Query the Intent Hypergraph
(:tool :name "intent-query"
       :params [entity-id:Str relation:Str depth:I64]
       :doc "Traverses hypergraph (e.g. find all requirements and code governed by ADR d-xxxx).")

;; 4. Verify Code Against Requirements & Use Cases
(:tool :name "trace-verify"
       :params [symbol:Str]
       :doc "Checks that symbol has valid links to a requirement, use case, and no invariant violations.")

;; 5. Record New Decision or Invariant
(:tool :name "pcp-record"
       :params [kind:Str title:Str rationale:Str links:(List Str)]
       :doc "Creates new versioned d/c/r/l entry in .pcp and links it to active AST nodes.")

;; 6. Search Knowledge Across Memory and Disk
(:tool :name "knowledge-search"
       :params [query:Str kinds:(List Str)]
       :doc "Searches hybrid vector index and relational graph for decisions, specs, and code.")
```
