# Phase 13 Plan: ASL Best Practices & Integration Recipes

## Overview
Document and build an interactive guide of battle-tested Best Practices and Integration Recipes for ASL (AgentScript Language). Cover in-browser WebAssembly sandboxing, Multi-Agent MCP loops, cross-compilation CI pipelines, agent VFS scratchpad workflows, and foreign declarations (`defextern`).

---

## Architecture & Design Decisions
- **D1 (Documentation First):** Create `docs/BEST_PRACTICES.md` covering 5 core integration recipes with complete, runnable code examples, Do's & Don'ts, and anti-patterns.
- **D2 (Interactive UI Integration):** Add `web/src/components/BestPractices.tsx` to the web showcase with copyable snippets and tabbed recipe switcher.
- **D3 (Navigation & Discovery):** Add direct navigation anchor `#recipes` in `Navbar.tsx` and integrate into `App.tsx`.
- **D4 (Zero-Drift Verification):** Ensure all recipe code examples strictly adhere to ASL grammar and pass semantic checks.

---

## Work Items

### W1: Author Comprehensive `docs/BEST_PRACTICES.md`
- **Description:** Write structured best practices and 5 complete recipes:
  1. *Recipe 1: In-Browser WebAssembly Sandbox (React / Vanilla JS)*
  2. *Recipe 2: Autonomous Agent MCP Tooling Workflow*
  3. *Recipe 3: Multi-Target Production CI/CD (ASL ➔ TS + Rust + Go)*
  4. *Recipe 4: Agent In-Memory Scratchpad & Batch VFS Transformations*
  5. *Recipe 5: Foreign Function Interface & Host Bindings (`defextern`)*
- **Target Files:** `docs/BEST_PRACTICES.md`
- **Gate Command:** `test -f docs/BEST_PRACTICES.md`

### W2: Create Interactive Recipes Component in Showcase Web App
- **Description:** Build `web/src/components/BestPractices.tsx` with interactive recipe selector, syntax-highlighted code blocks, copy buttons, and architecture schematics.
- **Target Files:** `web/src/components/BestPractices.tsx`
- **Gate Command:** `npm run build:web`

### W3: Wire Navigation & App Mounting
- **Description:** Mount `BestPractices` in `web/src/App.tsx` and add `#recipes` link to `web/src/components/Navbar.tsx`.
- **Target Files:** `web/src/App.tsx`, `web/src/components/Navbar.tsx`
- **Gate Command:** `npm run build:web`

### W4: Full Repository Gate Verification & Test Suite
- **Description:** Verify complete project gate pipeline across all targets and unit tests.
- **Gate Command:** `npm run build:web && .venv/bin/python grammar/validate.py && .venv/bin/python checker/gate.py && .venv/bin/python backend/differential.py && .venv/bin/pytest backend/tests checker/tests tools/tests -q`
