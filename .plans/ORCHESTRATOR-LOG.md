# Orchestrator Log

## Iteration 2026-09-03-portable-harness

- **Goal**: Portable Dual-Host Agent Harness (Browser & Local) with Search, Epistemic Memory & Anti-Hallucination Guardrails in ASL.
- **Created**: 2026-09-03
- **Architectural Gap & Consistency Review (2026-09-03)**:
  1. *Async/Purity Gap*: ASL has no native async or thread concurrency. Resolution: Elm/Redux architecture. Pure ASL state machine emits typed `AgentEffect`s; asynchronous host bridge (TS/Node) executes I/O and sends `AgentEvent`s back.
  2. *Browser Network/CORS Gap*: Direct browser fetch to SearXNG/external URLs fails on CORS. Resolution: Tri-modal fetch adapter: extension mode (`asl-browser-plugin`), CORS-proxy gateway mode, and local Node mode.
  3. *Grounding Verification Gap*: Abstract "citations" defined as concrete algebraic tuples: `(source-id, exact-snippet, confidence-score)`. ASL validator checks string containment and n-gram overlap before letting FSM proceed to action execution.
  4. *Vector Scaling Gap*: Pure ASL `(List F64)` linear scan is O(N). Suitable for episodic working memory (<1,000 items). For larger stores, SQLite/OPFS persistence indexes metadata, and ASL performs reranking over top candidates.
  5. *Dual-Host Parity*: Wasm + TS dual path verified against existing in-memory WASI preview1 runner (`ROADMAP.md` Phase 10).
