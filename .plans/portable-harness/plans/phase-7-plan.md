# Phase 7 Plan: End-to-End Dual-Host Harness Validation

## Goal
Establish a comprehensive end-to-end evaluation suite running whole-program agent tasks (planning, search retrieval, grounded synthesis, memory recall, and tool execution) across both Node.js CLI and headless browser Wasm runtime.

## Work Items

### Item 1: End-to-End Local Node Harness Runner
- **File**: `packages/asl-harness/tests/e2e_local.ts`
- **Specification**:
  - Sets up `NodeHost` with local SQLite epistemic store and live/mock SearXNG search.
  - Feeds multi-step scenario: "Research topic X, summarize verified facts into markdown, generate ASL data validation script, execute in sandboxed shell, verify output".
  - Asserts full FSM progression from `idle` to `completed`, zero ungrounded assertions, and all artifacts generated.
- **Gate**: `npx tsx packages/asl-harness/tests/e2e_local.ts`

### Item 2: End-to-End In-Browser Wasm Harness Runner
- **File**: `packages/asl-harness/tests/e2e_browser.ts`
- **Specification**:
  - Sets up `BrowserHost` using Playwright / headless Chromium and in-memory WASI preview1 shim.
  - Runs the identical agent scenario using IndexedDB persistence and mock CORS-proxy search.
  - Verifies identical state machine step sequence, identical epistemic ledger counts, and byte-equivalent final output.
- **Gate**: `npx tsx packages/asl-harness/tests/e2e_browser.ts`

### Item 3: Package Scripts & Automated Gate Integration
- **File**: `packages/asl-harness/package.json`
- **Specification**:
  - Adds scripts:
    - `"test:bridge": "tsx bridges/tests/test_host_bridge.ts"`
    - `"test:grounding": "tsx tests/test_grounding.ts"`
    - `"test:tools": "tsx tests/test_tool_mesh.ts"`
    - `"test:e2e": "tsx tests/e2e_local.ts && tsx tests/e2e_browser.ts"`
- **Gate**: `npm run --prefix packages/asl-harness test:e2e`
