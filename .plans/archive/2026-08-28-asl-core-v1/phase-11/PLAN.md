# Phase 11 — AgentScript MCP Server & Developer Agent Tooling

## §1 Scope and acceptance

Build a stdlib-only Model Context Protocol (MCP) server for AgentScript (`tools/mcp/server.py`) communicating over stdio JSON-RPC 2.0, providing dedicated tools for LLM agents:
1. `asex_check`: In-memory and file-based semantic checking returning structured `Diagnostic[]`.
2. `asex_eval`: In-memory code evaluation through `agentscript-interp`, returning `{ stdout, stderr, exit_code }`.
3. `asex_format`: S-expression formatting via `tools/fmt/fmt.py`.
4. `asex_compress_module`: AST signature compressor extracting `:doc`, `:export`, `defschema`, `defenum`, and `defun` headers without function bodies (reducing token count by 70–80%).
5. `asex_ast_query`: Tree-sitter S-expression query over source.

Provide an automated pytest test suite (`tools/t/test_mcp.py`) and developer agent skill guide (`skills/agentscript/SKILL.md`).

### Acceptance Criteria

1. **MCP Server Protocol Compliance (`tools/mcp/server.py`)**:
   Standard JSON-RPC 2.0 over stdio supporting `initialize`, `tools/list`, `tools/call`, and `ping` without external third-party dependencies.
2. **Tool Capabilities**:
   - `asex_check` returns structured diagnostics `{file, line, col, code, message}` with exit 0 for valid code and exact rule violations for invalid.
   - `asex_eval` executes code in-memory or on-disk, returning captured stdout, stderr, and integer exit codes.
   - `asex_format` canonicalizes code formatting.
   - `asex_compress_module` outputs interface-only signatures for context compression.
   - `asex_ast_query` executes `.scm` queries against AST.
3. **Automated Test Suite (`tools/t/test_mcp.py`)**:
   `pytest tools/t/test_mcp.py` passes 100% of tests.
4. **Developer Skill Documentation (`skills/agentscript/SKILL.md`)**:
   Clear reference documentation for agents developing in AgentScript.
5. **Gates Clean**:
   All repository gates remain green.

---

### Decisions

**D1 — Zero-Dependency Stdlib-Only MCP Implementation:**
The MCP server uses Python's standard library `json`, `sys`, `dataclasses`, and `subprocess`. It requires no external MCP packages (`mcp-sdk`), ensuring zero supply-chain friction and instant execution.

**D2 — In-Memory Execution Harness:**
For `asex_check`, `asex_eval`, `asex_format`, and `asex_compress_module`, tools accept either an in-memory string `source` or a file path `path`. In-memory strings are written to temporary files and executed with search roots automatically configured to `grammar/corpus/modules`.

**D3 — AST Signature Extraction:**
`asex_compress_module` parses the source AST using tree-sitter, extracts the `(module ...)` header with docstrings, `defschema` and `defenum` definitions, and `defun` signatures with parameter types, return types, and `:doc` strings, omitting function body forms.

---

## §2 Inventory

**New:**
- `tools/mcp/__init__.py`
- `tools/mcp/server.py`: The MCP stdio server.
- `tools/mcp/compressor.py`: The module signature extractor.
- `tools/t/test_mcp.py`: Pytest suite for MCP server and tools.
- `skills/agentscript/SKILL.md`: Developer guide and agent instructions.

**Unchanged, verified:**
- `checker/resolve.py`: Semantic analysis engine.
- `tools/fmt/fmt.py`: Formatter.
- `tools/tsutil.py`: Tree-sitter query interface.
- `crates/agentscript-interp`: Reference interpreter.

---

## §3 Work Items

### W1 — Module Interface Compressor (`tools/mcp/compressor.py`)
Implement `compress_module(source: str) -> str` extracting module doc/exports, schemas, enums, and defun signatures.
*Target files:* `tools/mcp/compressor.py`
*Gate:* `pytest tools/t/test_mcp.py -k test_compress_module`

### W2 — MCP Server Protocol & Tools (`tools/mcp/server.py`)
Implement stdio JSON-RPC server and the 5 MCP tools (`asex_check`, `asex_eval`, `asex_format`, `asex_compress_module`, `asex_ast_query`).
*Target files:* `tools/mcp/server.py`
*Gate:* `pytest tools/t/test_mcp.py -k test_mcp_server`

### W3 — Automated Test Suite (`tools/t/test_mcp.py`)
Complete test coverage for all MCP requests and edge cases.
*Target files:* `tools/t/test_mcp.py`
*Gate:* `.venv/bin/pytest tools/t/test_mcp.py -v` passes.

### W4 — Developer Skill Guide (`skills/agentscript/SKILL.md`)
Create domain skill documentation for AgentScript syntax, idioms, gates, and MCP tools.
*Target files:* `skills/agentscript/SKILL.md`

### W5 — Full Gate Verification
Run full project gate suite.
*Gate:* `.venv/bin/python grammar/validate.py && .venv/bin/python grammar/closure_audit.py && .venv/bin/python checker/gate.py && .venv/bin/python backend/check_corpus.py && .venv/bin/python backend/monomorphism.py && .venv/bin/python backend/differential.py && .venv/bin/pytest backend/t tools/t`
