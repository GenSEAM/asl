# Roadmap & Implementation Plan: Autonomous In-Browser Agent (`asl-browser-agent-v1`)

**Goal**: Transform browser interaction from passive, token-wasteful DevTools scraping into an autonomous, in-tab co-pilot (`packages/asl-browser-plugin`) that runs private 0.5B models via WebGPU, compresses DOM hierarchies into typed ASL S-expression frames (-78% tokens), and syncs with backend IDE orchestrators over the A2A mesh bus (@pcp:d-596e).

## Status: PLANNED (Scheduled for execution following Self-Hosting & Admin Toolkit completion)

---

### Phase 1: In-Tab WASI Runtime & Semantic DOM Compressor
- [ ] Implement `dom_compressor.ts` in `packages/asl-browser-plugin`: converts raw DOM elements into canonical ASL S-expressions (`(! dom/snapshot ...)`).
- [ ] Filter out non-semantic boilerplate (style blocks, script tags, SVG paths, inline CSS) while preserving accessibility roles, reactive component identities, and data attributes.
- [ ] Benchmark token reduction: target $\ge 75\%$ reduction against raw outerHTML.
- [ ] Embed compiled AgentScript WASI runtime directly into Manifest V3 background service worker.

### Phase 2: WebGPU 0.5B Local Instruct Model Engine
- [ ] Integrate lightweight in-browser inference runtime (e.g. WebLLM / ONNX Web / wgpu) supporting quantized 0.5B instruct models (Qwen2.5-0.5B-Instruct or SmolLM2-360M).
- [ ] Run zero-server private inference inside an isolated Web Worker.
- [ ] Provide fallback to remote Model Context Protocol (MCP) endpoint when WebGPU is unavailable or disabled.
- [ ] In-tab intent analyzer: understands UI interactions, form inputs, and state changes locally without cloud roundtrips.

### Phase 3: Bi-Directional Agent-to-Agent (A2A) Mesh Sync
- [ ] Implement browser-side A2A client connecting to `@genseam/asl-agent-bus` over WebSockets and Server-Sent Events (SSE).
- [ ] Frame streaming: send live UI anomalies, component re-render loops, and hydration errors directly to IDE orchestrator agents.
- [ ] Command reception: receive structured actions (`(? ui/click ...)`, `(? ui/fill ...)`, `(? ui/navigate ...)`) from backend developer swarms.
- [ ] Sub-millisecond latency channel verification.

### Phase 4: Autonomous Web QA, Auto-Healing & Extension Packaging
- [ ] Automated regression detection: compare live DOM state with component contracts.
- [ ] Cross-browser manifest packaging: Google Chrome, Mozilla Firefox, Apple Safari, Microsoft Edge.
- [ ] Integration with `asl test --browser`: run browser-driven e2e tests natively from the ASL CLI.
- [ ] End-to-end dogfooding: autonomous in-browser agent tests the AgentScript Showcase website in CI.
