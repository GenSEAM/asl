# Agent Intelligence, Context Engine & Harness: Phases & Acceptance Criteria (v2.0)

Goal: Build a high-density, agent-native intelligence ecosystem in pure AgentScript (ASL): an isolated HTML/DOM/JSON context extraction engine (`asl-context`), multi-ecosystem code & deep web search (`asl-search`), high-density semantic/graph memory with binary ASN compression (`asl-mem`), token-optimized S-expression tool calling (`asl-toolcall`), and anti-hallucination epistemic proxy guardrails (`asl-harness`).

## Architectural Invariants
1. **Decoupled Context & Search Separation**: `asl-search` strictly queries and returns references; `asl-context` handles HTML/DOM/JSON extraction, noise stripping, AST chunking, and RAG context compression.
2. **Pure Functional ASL Core (Zero Python Runtime in Shipped Code)**: All logic runs in pure ASL compiled to Wasm/Rust/TypeScript. Host bridges only handle raw I/O.
3. **ASL S-Expression Tool Calling**: Replace bulky JSON schemas with dense ASL S-expression tool calls `(call :tool <name> <args>)`, slashing token overhead by 70–80%.
4. **Epistemic Grounding & Citation Invariant**: Claims require verifiable source references `(source-id, quote, confidence)`. Contradictions and stale sources are flagged by the proxy.
5. **High-Density Binary Memory Matrix**: In-memory vector cosine similarity and graph links backed by binary ASN encoding for high-speed local recall.

---

## Ordered Phases

### Phase 1: Decoupled ASL Context Engine & Multi-Format RAG Extractor (`packages/asl-context`)
- **Objective**: Implement pure ASL context engine separating RAG from search: HTML/DOM parser and boilerplate stripper (scripts, styles, ads, nav), multi-format extractors (JSON, XML/Atom, Markdown), token-dense chunking, and LLM context compressor.
- **Paths**: `packages/asl-context/asl.json`, `packages/asl-context/src/context.asl`, `packages/asl-context/src/html.asl`, `packages/asl-context/tests/context_test.asl`
- **Acceptance Criterion**: `.venv/bin/python checker/gate.py && .venv/bin/python ./agentscript test packages/asl-context/tests/context_test.asl`

### Phase 2: Ecosystem Intelligence & Deep Search Traversal (`packages/asl-search`)
- **Objective**: Extend `asl-search` with deep link traversal (fetching and extracting linked pages via `asl-context`), multi-ecosystem package & code search (GitHub, npm, PyPI, Crates.io, Go modules, C-libraries), and domain-specific search filters.
- **Paths**: `packages/asl-search/src/engine.asl`, `packages/asl-search/src/ecosystems.asl`, `packages/asl-search/tests/search_test.asl`
- **Acceptance Criterion**: `.venv/bin/python checker/gate.py && .venv/bin/python ./agentscript test packages/asl-search/tests/search_test.asl`

### Phase 3: High-Density Semantic & Graph Memory Engine with Binary Compression (`packages/asl-mem`)
- **Objective**: High-density local intelligence store combining ASL vector similarity (`store.asl`) with entity-relationship knowledge graph edges, data freshness timestamps, contradiction resolution, and binary ASN serialization (`packages/asl-codec`).
- **Paths**: `packages/asl-mem/src/store.asl`, `packages/asl-mem/src/graph.asl`, `packages/asl-mem/src/compact.asl`, `packages/asl-mem/tests/mem_test.asl`
- **Acceptance Criterion**: `.venv/bin/python checker/gate.py && .venv/bin/python ./agentscript test packages/asl-mem/tests/mem_test.asl`

### Phase 4: ASL S-Expression Tool-Calling Bridge & Token Compressor (`packages/asl-toolcall`)
- **Objective**: Implement compact S-expression tool calling protocol replacing multi-kilobyte JSON schemas: model outputs dense ASL forms `(call :tool search :q "query" :limit 5)`, tool dispatcher validates against ASL type signatures and executes with zero JSON bloat.
- **Paths**: `packages/asl-toolcall/asl.json`, `packages/asl-toolcall/src/protocol.asl`, `packages/asl-toolcall/src/dispatch.asl`, `packages/asl-toolcall/tests/toolcall_test.asl`
- **Acceptance Criterion**: `.venv/bin/python checker/gate.py && .venv/bin/python ./agentscript test packages/asl-toolcall/tests/toolcall_test.asl`

### Phase 5: Anti-Hallucination LLM Proxy & Grounding Firewall (`packages/asl-harness`)
- **Objective**: Epistemic grounding firewall and proxy: verifies factual claims against exact source quotes from retrieved search/context pages, detects conflicting data, manages namespace-isolated prompt caches, and blocks unverified actions.
- **Paths**: `packages/asl-harness/src/core.asl`, `packages/asl-harness/src/grounding.asl`, `packages/asl-harness/src/proxy.asl`, `packages/asl-harness/tests/harness_test.asl`
- **Acceptance Criterion**: `.venv/bin/python checker/gate.py && .venv/bin/python ./agentscript test packages/asl-harness/tests/harness_test.asl`

### Phase 6: End-to-End Orchestration, Benchmarks, Documentation & `llms.txt`
- **Objective**: Full end-to-end task runner bridging search, context, memory, and tool execution; token-density benchmarks vs JSON tool calling; user README, and machine-readable `llms.txt` card for models.
- **Paths**: `packages/asl-harness/README.md`, `llms.txt`, `bench/token_toolcall.py`, `tools/doc_examples.py`
- **Acceptance Criterion**: `.venv/bin/python checker/gate.py && .venv/bin/python tools/doc_examples.py --quiet && .venv/bin/python -m pytest tools/tests/test_cli_search.py -q`

---

## Out of Scope & Rationale
- **Direct Python runtime in client production artifacts**: Core search, context, and memory must compile to WebAssembly and TypeScript without Python runtime dependencies.
- **External SaaS Vector DB dependencies (Pinecone, Weaviate, Qdrant)**: Violates zero-dependency and in-browser WASI portability. All indexing is local, embeddable, and compact.
- **Modifications to ASL Core Language Grammar**: Language v0.2 core grammar is frozen and normative. All capabilities are built as modular standard packages.
