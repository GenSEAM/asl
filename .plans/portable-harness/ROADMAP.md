# Portable Agent Harness: Comprehensive Execution Architecture & Detailed Phase Plans

> **Vision**: A lightweight, highly portable Agent Harness runnable both in-browser (zero-server WASI + Web Workers) and locally (Node/Rust/CLI), with maximum core logic authored in AgentScript (ASL Nano), paired with metasearch, epistemic memory, anti-hallucination guardrails, and sandboxed tool execution.

---

## 1. Architectural Foundations

### 1.1 Pure Functional Core (Elm/Redux Pattern)
ASL Core v0.2 enforces totality and determinism without native async/await. The agent execution engine is structured as a pure state transition function:
```lisp
(df step [(state AgentState) (event AgentEvent) (ledger EpistemicLedger)] 
  -> (Pair AgentState (List AgentEffect)))
```
The ASL core emits declarative `AgentEffect` values (`search`, `fetch`, `infer-model`, `store`, `run-tool`). The host bridge executes these effects asynchronously in TypeScript/Wasm and posts `AgentEvent` responses back into `step`.

### 1.2 Dual Host Runtime Parity
- **In-Browser Target**: Pure TypeScript in-memory WASI preview1 shim, Web Workers, browser fetch with CORS proxy / extension mode (`asl-browser-plugin`), and IndexedDB/OPFS persistence.
- **Local CLI Target**: Node.js / Rust CLI, direct HTTP/HTTPS fetch, POSIX filesystem, SQLite persistence (`asl-sql`), and sandboxed subprocess execution (`asl-sh`).

### 1.3 Grounding & Anti-Hallucination Pipeline
- Strict Epistemic Ledger: All factual claims require explicit provenance `(source-id, exact-snippet, confidence)`.
- Verification Gate: N-gram / substring inclusion validator in ASL before advancing from `verifying` to `acting`.
- Schema Conformance: Output structure validation via `asl-codec` (`asn-check.asl`).

---

## 2. Detailed Phase Specifications

### Phase 1: ASL Harness Core Schema & Epistemic State Machine
- **Goal**: Author pure ASL data models and lifecycle transitions.
- **Key Modules**:
  - `packages/asl-harness/src/core.asl`: `AgentState`, `AgentEvent`, `AgentEffect`.
  - `packages/asl-harness/src/state_machine.asl`: `step`, `is-terminal`, `next-transition`.
  - `packages/asl-harness/src/ledger.asl`: `EpistemicFact`, `EpistemicLedger`, `add-fact`, `verify-fact`, `context-budget`.
- **Failing Gate / Verification Command**:
  `.venv/bin/python checker/gate.py && .venv/bin/python tools/native_parser.py packages/asl-harness/src/core.asl`

### Phase 2: Pluggable Adapter Contracts & Isomorphic Host Effect Loop
- **Goal**: Abstract host interfaces and build the asynchronous effect-driver loop in TypeScript.
- **Key Modules**:
  - `packages/asl-harness/src/adapters.asl`: Abstract adapter specifications.
  - `packages/asl-harness/bridges/host.ts`: `AgentHost` interface, async effect loop.
  - `packages/asl-harness/bridges/browser_host.ts`: In-memory WASI + Web Worker driver.
  - `packages/asl-harness/bridges/node_host.ts`: Node.js driver.
  - `packages/asl-harness/bridges/tests/test_host_bridge.ts`: Dual-runtime mock test.
- **Failing Gate / Verification Command**:
  `npx tsx packages/asl-harness/bridges/tests/test_host_bridge.ts`

### Phase 3: Metasearch, CORS-Aware Fetcher & Live Data Actualization
- **Goal**: Production-grade search aggregation and freshness scoring in `asl-search`.
- **Key Modules**:
  - `packages/asl-search/src/engine.asl`: Proxy rotator, multi-query aggregation.
  - `packages/asl-search/src/actualize.asl`: Freshness scoring, content chunker.
  - `packages/asl-harness/bridges/search_adapter.ts`: Tri-modal fetcher (Extension, CORS-proxy, Node).
  - `packages/asl-search/tests/test_search_actualize.ts`: Search integration test.
- **Failing Gate / Verification Command**:
  `.venv/bin/python checker/gate.py && npx tsx packages/asl-search/tests/test_search_actualize.ts`

### Phase 4: Epistemic State & Hybrid Memory Store (IndexedDB/OPFS + SQLite)
- **Goal**: Hybrid memory store combining ASL vector similarity with structured metadata.
- **Key Modules**:
  - `packages/asl-mem/src/store.asl`: Vector L2 and cosine similarity (existing).
  - `packages/asl-mem/src/epistemic_index.asl`: Top-K candidate reranker with metadata tags.
  - `packages/asl-harness/bridges/memory_adapter.ts`: Dual persistence (IndexedDB/OPFS for browser, SQLite via `asl-sql` for Node).
  - `packages/asl-mem/tests/test_epistemic_memory.ts`: Store and recall tests.
- **Failing Gate / Verification Command**:
  `.venv/bin/python checker/gate.py && npx tsx packages/asl-mem/tests/test_epistemic_memory.ts`

### Phase 5: Anti-Hallucination & Precision Guardrails (Grounding Pipeline)
- **Goal**: Automated grounding and invariant verification pipeline in ASL.
- **Key Modules**:
  - `packages/asl-harness/src/grounding.asl`: Substring & token n-gram overlap verifier.
  - `packages/asl-harness/src/verifier.asl`: Schema checks via `asl-codec`, AST rules via `asl-lint`.
  - `packages/asl-harness/tests/test_grounding.ts`: Assertion tests rejecting ungrounded claims.
- **Failing Gate / Verification Command**:
  `.venv/bin/python checker/gate.py && npx tsx packages/asl-harness/tests/test_grounding.ts`

### Phase 6: Multi-Modal Tool Runtime Mesh (DOM, Sandboxed CLI, Mesh Bus)
- **Goal**: Safe sandboxed tool invocation bridging ASL to host capabilities.
- **Key Modules**:
  - `packages/asl-harness/src/tools.asl`: `ToolSpec`, `ToolCall`, `SandboxMode`.
  - `packages/asl-harness/bridges/tool_mesh.ts`: Integration with `asl-browser-plugin`, `asl-sh`, `asl-agent-bus`.
  - `packages/asl-harness/tests/test_tool_mesh.ts`: Tool execution tests.
- **Failing Gate / Verification Command**:
  `npx tsx packages/asl-harness/tests/test_tool_mesh.ts`

### Phase 7: End-to-End Dual-Host Harness Validation
- **Goal**: Full-scenario agent benchmark running across both Node and browser environments.
- **Key Modules**:
  - `packages/asl-harness/tests/e2e_local.ts`: Full flow running in Node CLI.
  - `packages/asl-harness/tests/e2e_browser.ts`: Full flow running in headless browser Wasm.
  - `packages/asl-harness/package.json`: Script `test:e2e`.
- **Failing Gate / Verification Command**:
  `npm run --prefix packages/asl-harness test:e2e`
