# Portable Agent Harness: Phases & Acceptance Criteria (Refined v1.1)

Goal: Build a portable, dual-host agent harness (Browser & Local CLI) powered by AgentScript (ASL) core logic and pure functional FSM, featuring pluggable adapters for metasearch/data actualization, hybrid epistemic memory, anti-hallucination precision guardrails, and sandboxed tool execution.

## Architectural Invariants (Post Gap-Analysis)
1. **Pure Functional ASL Core (Elm/Redux Pattern)**: ASL contains no async runtime and no raw networking. The ASL core is a pure state machine: `step: (State, Event) -> (State, List Effect)`. The host bridge (TS/Node/Wasm) executes effects asynchronously and posts events back.
2. **Isomorphic Dual Host (Parity without Leaks)**: Host runtime handles environment-specific I/O. In Browser: Fetch/CORS-proxy, OPFS/IndexedDB, in-memory WASI. In Local CLI: POSIX fs, SQLite, child_process.
3. **Epistemic Ledger for Grounding**: Hallucination prevention is enforced via algebraic tracking: facts require exact snippet references (`source-id`, `snippet-quote`, `confidence`). Unverified facts fail pre-execution assertion gates.
4. **Context Window Economy**: Raw search/DOM payloads are never injected directly; they pass through ASL chunking, similarity reranking (`asl-mem`), and token budget compression.

---

## Ordered Phases

### Phase 1: ASL Harness Core Schema & Epistemic State Machine
- **Objective**: Implement pure ASL data models and transition rules for the agent execution lifecycle: `AgentState`, `AgentEvent`, `AgentEffect`, `EpistemicLedger` (facts, citations, confidence, verification status), and context window budget calculator.
- **Paths**: `packages/asl-harness/src/core.asl`, `packages/asl-harness/src/state_machine.asl`, `packages/asl-harness/src/ledger.asl`
- **Acceptance Criterion**: `.venv/bin/python checker/gate.py && .venv/bin/python tools/native_parser.py packages/asl-harness/src/core.asl`

### Phase 2: Pluggable Adapter Contracts & Isomorphic Host Effect Loop
- **Objective**: Define ASL effect specifications (`Effect: Search`, `Effect: Store`, `Effect: RunTool`, `Effect: InferModel`) and the TypeScript asynchronous effect-driver loop supporting both Browser (Web Workers, Fetch/CORS proxy, in-memory WASI) and Local Node/Native (fs, child_process, SQLite).
- **Paths**: `packages/asl-harness/src/adapters.asl`, `packages/asl-harness/bridges/host.ts`, `packages/asl-harness/bridges/browser_host.ts`, `packages/asl-harness/bridges/node_host.ts`
- **Acceptance Criterion**: `npx tsx packages/asl-harness/bridges/tests/test_host_bridge.ts`

### Phase 3: Metasearch, CORS-Aware Fetcher & Live Data Actualization
- **Objective**: Metasearch aggregation in `asl-search` (SearXNG endpoints, query expansion, proxy health rotation), browser CORS handling / fallback modes, HTML-to-markdown extraction, and ASL freshness scoring.
- **Paths**: `packages/asl-search/src/engine.asl`, `packages/asl-search/src/actualize.asl`, `packages/asl-harness/bridges/search_adapter.ts`
- **Acceptance Criterion**: `.venv/bin/python checker/gate.py && npx tsx packages/asl-search/tests/test_search_actualize.ts`

### Phase 4: Epistemic State & Hybrid Memory Store (IndexedDB/OPFS + SQLite)
- **Objective**: Hybrid memory matrix combining ASL vector cosine similarity (`asl-mem/store.asl`) with structured metadata tagging, citation linking, and dual-backend persistence (Browser IndexedDB/OPFS & Local SQLite via `asl-sql`).
- **Paths**: `packages/asl-mem/src/store.asl`, `packages/asl-mem/src/epistemic_index.asl`, `packages/asl-harness/bridges/memory_adapter.ts`
- **Acceptance Criterion**: `.venv/bin/python checker/gate.py && npx tsx packages/asl-mem/tests/test_epistemic_memory.ts`

### Phase 5: Anti-Hallucination & Precision Guardrails (Grounding Pipeline)
- **Objective**: Construct grounding verification pipeline in ASL: citation verification against retrieved search/doc snippets, algebraic schema conformity via `asl-codec`, AST invariant checks via `asl-lint`, and pre-execution assertion gates.
- **Paths**: `packages/asl-harness/src/grounding.asl`, `packages/asl-harness/src/verifier.asl`, `packages/asl-harness/tests/test_grounding.ts`
- **Acceptance Criterion**: `.venv/bin/python checker/gate.py && npx tsx packages/asl-harness/tests/test_grounding.ts`

### Phase 6: Multi-Modal Tool Runtime Mesh (DOM, Sandboxed CLI, Mesh Bus)
- **Objective**: Safe sandboxed tool execution bridging ASL Nano contracts to Browser DOM actions (`asl-browser-plugin`), sandboxed shell commands (`asl-sh` / WASI runner), and agent mesh messaging (`asl-agent-bus` / `asl-skyloom`).
- **Paths**: `packages/asl-harness/src/tools.asl`, `packages/asl-harness/bridges/tool_mesh.ts`, `packages/asl-harness/tests/test_tool_mesh.ts`
- **Acceptance Criterion**: `npx tsx packages/asl-harness/tests/test_tool_mesh.ts`

### Phase 7: End-to-End Dual-Host Harness Validation (Local CLI & In-Browser WASI)
- **Objective**: Full end-to-end evaluation suite running whole-program agent tasks (planning, search retrieval, grounded synthesis, memory recall, and tool execution) across both Node.js CLI and headless browser Wasm runtime.
- **Paths**: `packages/asl-harness/tests/e2e_local.ts`, `packages/asl-harness/tests/e2e_browser.ts`, `packages/asl-harness/package.json`
- **Acceptance Criterion**: `npm run --prefix packages/asl-harness test:e2e`

---

## Out of Scope & Rationale
- **Modifications to ASL Core Language Grammar**: The v0.2 core specification is frozen and normative. All harness semantics are implemented using standard ASL constructs and modular packages.
- **External SaaS Vector DB dependencies (Pinecone, Weaviate)**: Violates offline, zero-dependency, and in-browser portability goals. We rely on self-contained ASL cosine-similarity (`asl-mem`) backed by SQLite / OPFS.
- **Proprietary Single-Provider Lock-In**: The model interface is abstracted over standard JSON-RPC / REST schemas allowing arbitrary providers (Gemini, Claude, OpenAI, local llama.cpp / Ollama).
