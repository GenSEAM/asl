# Iteration: asl-web-redesign-v1
Goal: Unified Cosmic Blueprint Design System, Vector Chameleon & Curled-'a' Logos, Key Capabilities Blueprint Cards, Honest UI, Multi-Page Dual-Audience Architecture, and Rich Agent-Centric Specifications.

## Completed Phases (Phases 1–4)
- **Phase 1: Design System & Vector Identity Assets** — DONE (commit `1438f43`).
- **Phase 2: Hero Section & Blueprint Key Capabilities** — DONE (commit `fbc3d04`).
- **Phase 3: Interactive Components & Honest UI Consistency** — DONE (commit `e7bb073`).
- **Phase 4: Production Build, CI & Frozen Lockfile Gate** — DONE (commit `c3bbf6d` & `9792362`).

## Active Phases (Phases 5–8)

### Phase 5: Dual-Audience Routing & Multi-Page Architecture (`web/src/lib/router.tsx`, `App.tsx`, `Navbar.tsx`)
- Goal: Decouple human visual exploration from deep developer tooling. Implement client-side routing supporting `/`, `/playground`, `/ecosystem`, `/roadmap`, and `/docs`. Move heavy code studios (`SqlStudio`, `AslQualityDoctor`) into dedicated `/playground`.
- Checkable Criterion: `cd web && npm run build`

### Phase 6: High-Impact Hero with Isometric Circuit Backdrop & Value Hook (`Hero.tsx`)
- Goal: Implement the geometric isometric circuit traces from reference mockup in the hero background. Hook visitors with clear value propositions: 40–70% token savings, zero repair loops, safe jailed sandboxing, universal target compilation (Wasm, Rust, TS, Go, Python, SQL). Embed prominent `llms.txt` and `llms-full.txt` links directly in the Hero.
- Checkable Criterion: `cd web && npm run build`

### Phase 7: Comprehensive Agent-Centric Machine Specifications (`web/public/llms.txt`, `llms-full.txt`)
- Goal: Expand `/llms.txt` and `/llms-full.txt` with full agentic programming guidance, CLI toolchain reference (`asl run`, `asl fmt`, `asl lint`, `asl mcp`), A2A wire protocol frames, and formal security guarantees.
- Checkable Criterion: `test -f web/public/llms.txt && test -f web/public/llms-full.txt`

### Phase 8: Dedicated Pages (`PlaygroundPage.tsx`, `EcosystemPage.tsx`, `RoadmapPage.tsx`, `DocsPage.tsx`) & Deployment Verification
- Goal: Build the dedicated full-page experiences for Playground, Ecosystem, Roadmap, and Docs. Run full verification suite (`tsc`, `check-tokens.mjs`, `deploy_check.py`).
- Checkable Criterion: `.venv/bin/python tools/deploy_check.py`

## Out of Scope
- Modifying `packages/asl-parser` (running concurrently in the self-hosted runtime session).
