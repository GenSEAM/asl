# Roadmap & Implementation Plan: Autonomous In-Browser Agent (`asl-browser-agent-v1`)

**Goal**: Transform browser interaction from passive, token-wasteful DevTools scraping into an autonomous, in-tab co-pilot (`packages/asl-browser-plugin`) that leverages tiered local AI (Chrome Prompt API + WebLLM WebGPU), integrates the `asl-vdom` dual-perception DOM compressor, and syncs with backend IDE orchestrators over the A2A mesh bus (@pcp:d-596e).

## Status: PLANNED (Scheduled for execution following `asl-agent-efficiency-v1`)

---

### Phase 1: Browser Extension Core & In-Tab WASI Integration (`packages/asl-browser-plugin`)
- [ ] Embed compiled AgentScript WASI runtime directly into Manifest V3 background service worker.
- [ ] Connect `packages/asl-vdom` dual-perception engine:
  - AXTree extraction for semantic web apps.
  - D2Snap downsampling for complex web apps.
  - Incremental DOM mutation stream to minimize token payload.
- [ ] Cross-browser support: Google Chrome, Mozilla Firefox, Apple Safari, Microsoft Edge, and Brave.

### Phase 2: Tiered In-Browser Local Model Engine
- [ ] **Tier 1: Native Chrome Prompt API (`window.ai`)**:
  - Leverages built-in Gemini Nano model when available in Chromium/Chrome extensions.
  - Zero-download, zero-setup, instant on-device execution.
- [ ] **Tier 2: WebLLM / Transformers.js WebGPU Engine**:
  - High-performance WebGPU runtime in an isolated Web Worker for cross-browser support (Firefox/Safari/Edge).
  - Pre-quantized Qwen2.5-0.5B-Instruct or SmolLM2-360M cached in IndexedDB.
- [ ] **Tier 3: Remote Fallback**:
  - Seamless escalation to backend LLM / MCP endpoint when local compute is insufficient or WebGPU is disabled.
- [ ] **In-Tab Local Copilot**: Classifies UI intent, parses form validations, and summarizes page state locally with 0 ms server network overhead.

### Phase 3: Bi-Directional Agent-to-Agent (A2A) Mesh Sync
- [ ] Implement browser-side A2A client connecting to `@genseam/asl-agent-bus` over WebSockets and Server-Sent Events (SSE).
- [ ] Telemetry stream: stream live UI state frames, re-render loop warnings, and console errors directly into IDE developer swarms.
- [ ] Command reception: receive structured intent frames (`(? ui/click ...)`, `(? ui/fill ...)`) and execute safely within page execution context.
- [ ] Sub-millisecond latency channel verification.

### Phase 4: Autonomous Web QA, Auto-Healing & E2E Validation
- [ ] Autonomous test runner: `asl test --browser <url>` runs in-browser e2e assertions natively from the ASL CLI.
- [ ] Auto-healing: detect component regressions and suggest exact ASL/CSS/TS diffs to fix UI issues.
- [ ] Dogfooding: the in-browser agent runs automated QA over the AgentScript Showcase website in CI.
