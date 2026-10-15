# Comparative End-to-End Benchmark Report: ASL Eddy Migration (withdrawn)

**Status, 2026-10-14: withdrawn. None of its figures can be reproduced from this repository.**

This file used to report a comparison between a Node.js agent runtime and an ASL "Agent Eddy" micro-harness: cold start, memory, token counts for tool calls, permission prompts and audio barge-in latency, all marked PASS. Everything it was measured with is absent from this repository and its history:

- the package `packages/asl-eddie` and its `benchmark/run.js` and `test/*.test.js`;
- the npm package `@genseam/asl-toolcall`;
- `checker/gate.py`, `ai-docs/constitution.yaml` and `ROADMAP.md`.

What does exist is `packages/asl-agent/src/eddie.asl`, ASL source with no benchmark attached.

The figures it published are not results. `bench/publishedClaims.asn` marks the cold-start (`<100ms`) and memory (`24MB`) targets `:unmeasured`, and lists no row for the report's other numbers (the 72.7% and 64.2% token savings, 0 prompts, 0.004 ms barge-in). Do not cite them. A benchmark that replaces this one goes in `bench/` with the code that produces it, and its figures go into `bench/publishedClaims.asn` with their status.
