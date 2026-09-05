# GAP Audit Report: Master Ecosystem Execution Plan (`master-unified-ecosystem-v1`)

- **Audited Target**: `.plans/PHASES.md`, `.plans/INDEX.md`, `.plans/STATUS.md`
- **Protocol**: `gap` Critic Standard (@pcp:d-1eed, @pcp:d-bda8, @pcp:d-446d, @pcp:d-8d4c)
- **Verdict**: **`approve-with-amendments`**

---

## 1. Gap Analysis (Completeness & Edge Cases)

### GAP-1: Test Runner Mismatch on Native `.asl` Test Files
- **Evidence**: In `.plans/PHASES.md:10`, the gate for `vdom-dual-perception` is declared as:
  ```bash
  .venv/bin/python checker/gate.py && .venv/bin/python -m pytest packages/asl-vdom/tests -q
  ```
  Inspection of `packages/asl-vdom/tests/` reveals only `vdom_test.asl` with no Python `test_*.py` driver:
  ```bash
  ls packages/asl-vdom/tests/
  # output: vdom_test.asl
  ```
  `pytest` returns exit code 5 ("no tests collected") when run against a directory containing only `.asl` files.
- **Risk**: The gate will fail immediately before implementation even begins, falsely blocking the wave.
- **Remedy / Amendment**: Use the native ASL test runner or add a standard `test_vdom.py` pytest wrapper (like in `packages/asl-parser/tests/harness.py`). The gate should specify:
  ```bash
  .venv/bin/python checker/gate.py && .venv/bin/python ./agentscript test packages/asl-vdom/tests/vdom_test.asl
  ```

### GAP-2: Sub-Path Coupling in `web/` Between Wave 0 Tracks
- **Evidence**: `core-token-aliases` (Wave 0) runs `prelude/generate.py`, which regenerates `web/public/llms.txt`. Concurrently, `web-showcase-pages` (Wave 0) modifies the web showcase.
- **Risk**: While `web-showcase-pages` is scoped to `web/src/`, any broad `git add web/` in phase commits would cause race conditions or merge collisions between parallel implementers.
- **Remedy / Amendment**: Strictly enforce that `web-showcase-pages` owns `web/src/` exclusively, while `web/public/` is excluded from its write permissions and reserved for `prelude/generate.py`.

### GAP-3: Package Manifest Prerequisite for Semantic Checker
- **Evidence**: Wave 1 introduces `packages/asl-agent-core` and `packages/asl-shrody`. Neither directory currently exists on disk.
- **Risk**: When parallel implementers begin writing `.asl` files without an `asl.json` manifest declaring module paths and dependencies, `checker/gate.py` fails across the entire workspace because it scans `packages/**/*.asl`.
- **Remedy / Amendment**: Item 1 of both phases must be a zero-dependency package scaffold (`asl.json`, `package.json`, and minimal export header) before any functional logic is authored.

---

## 2. Consistency Analysis (Architectural Invariants & ADRs)

### INVARIANT-1: Standard ASL vs ASL Verbose (@pcp:d-1eed, @pcp:d-ddc2)
- **Evaluation**: PASS.
- The master roadmap completely eliminates "Nano" terminology from public interfaces, READMEs, and phase titles. The 2-token ceiling on all language primitives (`df`, `dfs`, `dfe`, `mt`, `:d`, `:x`, `:i`, `:a`, `Str`, `I64`) is preserved as the canonical on-disk and wire standard.

### INVARIANT-2: Closed Vocabulary & Capability Port Isolation (@pcp:d-4b8c, @pcp:d-446d)
- **Evaluation**: PASS.
- In both `sh-proc-guard-core` and `shrody-asl-port`, host interactions (PTY, audio, processes) are isolated behind typed capability manifests and FFI bridges (`host_bridge.js`, `host_process.ts`). The ASL AST and core logic remain 100% mathematically closed and free of unmodeled host side effects.

### INVARIANT-3: Pure Self-Hosted Toolchain Progression (@pcp:d-8d4c)
- **Evaluation**: PASS.
- The progression correctly builds upon Phase 10 (`packages/asl-codegen`, verified clean with 8/8 tests passing) and schedules `core-selfhost-retire-lark` to eliminate legacy Python/Lark scripts in Wave 2.

---

## 3. Adequacy & Anti-Overengineering (Critic Filter / YAGNI)

### YAGNI-1: In-Memory Ephemeral Process Spooling vs Heavy Log Daemons
- **Check**: Does `sh-proc-guard-core` or `sh-proc-guard-bridge` require Redis, SQLite, or external daemons?
- **Verdict**: PASS. The plan explicitly specifies an in-memory ring buffer with a 10MB/10k-line ceiling and middle-eviction markers. No external background daemons or database servers are introduced.

### YAGNI-2: CDP Browser Driver vs Heavy Electron Wrappers
- **Check**: Does `agent-browser-cdp` pull in bloated headless browser distribution binaries?
- **Verdict**: PASS. It connects directly to existing local Chrome instances via `--remote-debugging-port` over standard WebSocket/CDP or lightweight Chromium.

### YAGNI-3: ASN Schema Materialization vs Redundant Compilers
- **Check**: Does `asn-codec-phase2` reinvent AST parsing?
- **Verdict**: PASS. It builds directly upon `packages/asl-codec/src/core/asn.asl` and existing backend emitters without creating a secondary parser.

---

## 4. Required Amendments Applied to `.plans/PHASES.md`

1. Update `vdom-dual-perception` gate command to use `agentscript test` instead of `pytest`.
2. Confirm explicit ownership boundaries:
   - `web-showcase-pages`: `web/src/` (excluding `web/public/llms.txt`).
   - `core-token-aliases`: `prelude/`, `web/public/llms.txt`, `packages/asl-lint/src/core/tokens.asl`.
3. Mandate Item 1 package scaffolding for `packages/asl-agent-core` and `packages/asl-shrody`.

---

## 5. Architectural Gap & Critic Review: Compact UI Dialect (`asl/ui` -> TSX / Svelte / Vue)

- **Proposal**: Introduce 1–2 token UI aliases (`d`, `s`, `b`, `i`, `:c`, `:bind`, `:@c`) to write frontend views in AgentScript and transpile to native React TSX, Svelte 5, and Vue 3 SFCs.
- **Protocol**: `gap` Critic & Anti-Overengineering Standard
- **Verdict**: **`approve-with-amendments`** (Approved strictly as a userland library + emitter pass; **rejected** as a core grammar extension).

### A. Architectural Invariant Audit
1. **Core Language Boundary (PCP `c-c759`, `AGENT_SPEC_CORE.md`)**:
   - `AGENT_SPEC_CORE.md` deliberately excludes UI, graphics, DOM, and async from Core.
   - PCP `c-c759` explicitly warns: *"any plan that treats graphics or UI as another contract to be imported is planning against a capability that must first be built by hand... and is neither portable nor free"*.
   - **Enforcement**: No HTML or JSX primitives may be added to `AGENT_SPEC_CORE.md` or `prelude/prelude.json`. Core grammar remains completely domain-agnostic.

2. **The Zero-Grammar-Change Solution**:
   - In S-expressions, `(d :c "..." (s "hello"))` is **already** valid AgentScript syntax. It is simply a function or constructor call returning a `VNode` record from `packages/asl-vdom`.
   - HTML tags (`d`, `s`, `b`, `p`, `h1`..`h3`, `i`, `form`) can live cleanly as standard functions inside `packages/asl-vdom/src/html.asl`:
     ```lisp
     (df d [(attrs (Map Str Str)) (children (List VNode))] -> VNode
       (VNode :tag "div" :attrs attrs :children children))
     ```
   - No new language terminals, keywords, or parser changes required.

### B. Anti-Overengineering (YAGNI) & Scope Fences
1. **Zero Browser Runtime**: Do NOT build a custom in-browser VDOM diffing engine or state runtime. AgentScript must remain a pure static source-to-source transpiler.
2. **Framework Interop Over Re-invention**:
   - Let React manage React Fiber; let Svelte manage Runes; let Vue manage Proxies.
   - The ASL emitter in `packages/asl-codegen` simply emits standard, clean, readable `.tsx`, `.svelte`, or `.vue` source files that Vite/Next.js/Nuxt consume directly.
3. **No Heavy Event System**: Do not attempt to map 1,000 W3C DOM event interfaces into ASL types. Represent callbacks as standard total lambdas `(fn [] Unit)` or opaque payloads `(fn [Event] Unit)`.

### C. Placement in Master Roadmap
- **Phase ID**: `ui-transpiler-mvp`
- **Track**: Secondary ecosystem extension (scheduled for Wave 2 after `vdom-dual-perception`).
- **Owns**: `packages/asl-vdom/src/html.asl`, `packages/asl-codegen/src/emit_jsx.asl`.
- **Failing Gate**:
  ```bash
  .venv/bin/python ./agentscript compile --target tsx packages/asl-vdom/examples/card.asl -o /tmp/Card.tsx && npx tsc --noEmit /tmp/Card.tsx
  ```

