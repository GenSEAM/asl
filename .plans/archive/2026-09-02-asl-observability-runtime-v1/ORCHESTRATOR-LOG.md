# Orchestrator Log — asl-observability-runtime-v1

## Decisions & Directives
- **Visual Observability Paradigm**: Humans should inspect modules, topologies, SQL queries, and telemetry visually rather than reading raw code line by line.
- **PCP Compliance**: Respect `@pcp:d-1eed` (dual-projection), `@pcp:c-adc8` (control-flow nesting), and `@pcp:r-8d8e` (virtual inspection).
- **Direct Main Branch Policy**: Work directly on `main`, commit after each phase passes its verification gate.
- **Tiers**: Standard / Tier 1.5 across all 5 phases.

## Roadmap Execution
- Phase 1: Visual Module Topology & Architecture Graph Inspector (`asl graph` & `web/src/components/ModuleGraphVisualizer.tsx`) [TIER 1.5] — DONE
- Phase 2: Native Language Server (LSP) Engine with Virtual Projections (`tools/lsp.py` & `asl lsp`) [TIER 1.5] — DONE
- Phase 3: Ultra-Nano Syntax Expansion (`:f`, `:c`, `:d`, `:x`, `:i`, `Str`, `I64`) & Dual-Projection Transcoder [TIER 1.5] — DONE
- Phase 4: Isolated In-Memory Sandbox & Jailed Runner (`asl run --jail` / `tools/sandbox_runner.py`) [TIER 1.5] — DONE
- Phase 5: Zero-Cost Native Schema Codec (`packages/asl-codec/src/core/codec.asl`) [TIER 1.5] — DONE
- Phase 6: Full Observability Dashboard Integration in Web Showcase & 7-Gate CI [TIER 1.5] — DONE
