# Phases — asl-observability-runtime-v1

Full-Spectrum Visual Observability Cockpit, Native Language Server (LSP), Jailed Sandbox Runner, and Zero-Cost Schema Codec (`packages/asl-codec`).

## Phase List

- [x] **Phase 1**: Visual Module Topology & Architecture Graph Inspector (`asl graph` & `web/src/components/ModuleGraphVisualizer.tsx`)
- [x] **Phase 2**: Native Language Server (LSP) Engine with Virtual Projections (`tools/lsp.py` & `asl lsp`)
- [ ] **Phase 3**: Ultra-Nano Syntax Expansion (`:f`, `:c`, `:d`, `:x`, `:i`, `Str`, `I64`) & Dual-Projection Transcoder
  - Criterion: Both grammars (`agentscript.lark` and `tree-sitter-agentscript`) admit short markers; `.venv/bin/python grammar/validate.py` passes 100%; `asl transcode --to-nano` compacts schemas by $\ge 40\%$.
- [ ] **Phase 4**: Isolated In-Memory Sandbox & Jailed Runner (`asl run --jail` / `tools/sandbox_runner.py`)
  - Criterion: `.venv/bin/python -m pytest tools/tests/test_sandbox.py -q` passes 100%, enforcing memory ceilings, execution deadlines, and returning structured execution telemetry.
- [ ] **Phase 5**: Zero-Cost Native Schema Codec (`packages/asl-codec/src/core/codec.asl`)
  - Criterion: `agentscript check packages/asl-codec/src/core/codec.asl` has 0 diagnostics, Quality Score 100/100, and `pytest tools/tests/test_codec.py -q` passes roundtrip serialization.
- [ ] **Phase 6**: Full Observability Dashboard Integration in Web Showcase & 7-Gate CI
  - Criterion: `npm run build:web` succeeds; all 7 pre-commit verification gates pass cleanly.

## Out of Scope
- Proprietary closed-source IDE extensions or non-LSP editors (we target the open Language Server Protocol standard compatible with VS Code, Cursor, Zed, NeoVim).
