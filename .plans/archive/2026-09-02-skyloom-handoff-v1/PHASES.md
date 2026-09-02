# Phases — skyloom-handoff-v1

SkyLoom Handoff & Scoping Engine: Coordination Dialect (`asl/coord`), Zero-Leak Directory Jailing, Context Snapshot Compression, and Multi-Agent Delegation.

## Ordered Phases

1. **Phase 1: Coordination Dialect (`asl/coord`) & Algebraic Handoff Types**
   - Acceptance: `.venv/bin/python checker/gate.py && node packages/asl-skyloom/dist/tests/handoff_codec_test.js` exits 0.
2. **Phase 2: Directory Scoping & Zero-Leak Mesh Firewall**
   - Acceptance: `node packages/asl-skyloom/dist/tests/scoping_test.js` exits 0.
3. **Phase 3: Context Snapshot Compression & Handoff Serializer**
   - Acceptance: `node packages/asl-skyloom/dist/tests/snapshot_test.js` exits 0.
4. **Phase 4: CLI & Subprocess Worker Orchestration (`asl loom handoff` / `spawn`)**
   - Acceptance: `.venv/bin/python -m pytest tools/tests/test_cli_handoff.py -q` exits 0.
5. **Phase 5: Comparative Multi-Agent Token Benchmark & Web Showcase Simulation**
   - Acceptance: `.venv/bin/python bench/harness/bench_handoff_tokens.py && /usr/local/bin/node web/node_modules/vite/bin/vite.js build web` exits 0.

## Out of Scope

- **Distributed WAN Multi-datacenter Byzantine Consensus**: Out of scope for this iteration; SkyLoom is designed for low-latency local mesh IPC (Unix sockets, in-memory, local HTTP/SSE) between co-located and containerized agent swarms.
- **LLM Model Weights Fine-tuning**: Protocol operates at the prompt, syntax, and wire levels without requiring custom fine-tuned weights.
