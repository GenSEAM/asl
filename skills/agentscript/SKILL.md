---
name: agentscript
description: AgentScript language developer instructions, S-expression syntax reference, type rules, gates, and MCP tool suite.
---

# AgentScript Developer Guide

AgentScript is a strongly-typed, S-expression language designed for single-pass LLM code generation and zero-overhead WebAssembly execution.

## Core Language Rules
1. **Modules by Default**: Every file is a module with mandatory `:doc` and explicit `:export [...]` list.
2. **Totality & Exhaustiveness**:
   - `match` must cover all enum/union cases exhaustively.
   - `if` always requires both then and else branches.
   - `cond` always requires `:else` branch.
3. **Fixed Numeric Types**: `Int32`, `Int64`, `Float64`. No implicit widening or narrowing.
4. **Effect Tracking**: Functions interacting with host/I/O must carry the effect marker `!` on their signature: `(defun ! main [(args (List String))] -> (Result Unit IoError) ...)`.
5. **Derivations Precede Results**: In S-expressions, body expressions evaluate sequentially with the tail expression becoming the return value.

## MCP Developer Tools
The local MCP server is available at `tools/mcp/server.py`.
- `asex_check(source=...)`: Check types and semantics in-memory; returns `{ valid: bool, diagnostics: Diagnostic[] }`.
- `asex_eval(source=..., args=...)`: Execute code in-memory with reference interpreter; returns `{ stdout, stderr, exit_code, success }`.
- `asex_format(source=...)`: Canonicalize S-expression layout; returns `{ formatted, changed, diagnostics }`.
- `asex_compress_module(source=...)`: Compress a module into an interface signature, saving 70-85% prompt tokens.
- `asex_ast_query(source=..., query=...)`: Execute Tree-sitter `.scm` pattern queries against AST.

## Project Gates (must pass before every commit)
```bash
.venv/bin/python grammar/validate.py
.venv/bin/python grammar/closure_audit.py
.venv/bin/python checker/gate.py
.venv/bin/python backend/check_corpus.py
.venv/bin/python backend/monomorphism.py
.venv/bin/python backend/differential.py
.venv/bin/pytest backend/t tools/t -q
```
