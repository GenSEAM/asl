# Orchestrator Log: asl-selfhosted-runtime-v1

## Phase Tiers
- Phase 1: Tier 1 (Pure ASL Lexer & Tokenizer)
- Phase 2: Tier 1 (Pure ASL Reader & AST Schema)
- Phase 3: Tier 1 (CLI Tooling & Benchmark)
- Phase 4: Tier 1 (Full 7-Gate CI Hardening)

## Cross-Phase Decisions
- Standalone self-hosted parser lives in `packages/asl-parser`.
- Manifest scoped as `@genseam/asl-parser`.
- Supports both Ultra-Nano (`dfs`, `dfe`, `df`, `:f`, `:c`) and Verbose (`defschema`, `defenum`, `defun`) transparently without regex pre-processing.
