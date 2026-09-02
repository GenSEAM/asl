# Iteration: asl-selfhosted-runtime-v1
Goal: 100% Self-Hosted Pure ASL Parser & S-Expression Reader (`packages/asl-parser`), Native CLI Integration (`asl parse`), Dual-Projection Native AST & Full Migration.

## Phases

### Phase 1: Native Lexer & Tokenizer in Pure AgentScript (`packages/asl-parser/src/lexer.asl`)
- Goal: Implement tokenization of S-expressions, symbols, strings, numbers, keywords, and comments in pure ASL.
- Checkable Criterion: `.venv/bin/python -m pytest packages/asl-parser/tests/test_lexer.py -q`

### Phase 2: Native S-Expression Reader & Dual-Projection AST (`packages/asl-parser/src/reader.asl`, `ast.asl`)
- Goal: Implement hierarchical S-expression parsing into typed AST nodes (`ModuleNode`, `SchemaNode`, `EnumNode`, `DefunNode`) supporting both Ultra-Nano and Verbose forms natively.
- Checkable Criterion: `.venv/bin/python -m pytest packages/asl-parser/tests/test_reader.py -q`

### Phase 3: Native Parser CLI Integration (`asl parse`, `tools/native_parser.py`)
- Goal: Wire native parser into CLI as `asl parse` and provide high-speed parsing benchmark comparing memory/latency against Lark.
- Checkable Criterion: `.venv/bin/python -m pytest tools/tests/test_native_parser.py -q`

### Phase 4: Full Ecosystem Verification & 7-Gate CI Hardening
- Goal: Parse all 24 packages with native parser, run full 7-gate CI pre-commit pipeline, verify zero regressions.
- Checkable Criterion: `node /Users/purplelephant/.gemini/config/skills/pcp/scripts/pcp.js actualize && npm run build:web`

## Out of Scope
- Modifying tree-sitter C syntax highlighting grammar for VS Code (textmate/syntax highlighting is preserved for editors).
- Breaking existing Lark grammar file used by external Python LLM constrained decoders (vLLM/Outlines compatibility preserved).
