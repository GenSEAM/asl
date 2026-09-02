# Phase 11 Design Review

**Lens:** DESIGN
**Verdict:** approve-with-amendments

## Findings

1. **Module Compression Syntax Validity (D3)**
   - *Reference:* `.plans/phase-11/PLAN.md:39` ("omitting function body forms")
   - *Critique:* Simply omitting the body of a `defun` form may yield syntactically invalid AgentScript, breaking parsers or agents that attempt to read the compressed output. The compressor should replace the body with a minimal valid expression (e.g., `(...)`, `(todo)`, or an empty string `""` if the language allows it) to ensure the compressed module remains parseable.

2. **Tool Signature Schemas and Mutually Exclusive Parameters (D2)**
   - *Reference:* `.plans/phase-11/PLAN.md:34` ("tools accept either an in-memory string `source` or a file path `path`")
   - *Critique:* The schema design must clearly encode that `source` and `path` are mutually exclusive. Furthermore, for in-memory execution, evaluating a string often requires a virtual path or module context so that intra-project imports and diagnostics (`file` field) resolve correctly. The tool signature should ideally require an optional `path` even when `source` is provided, to act as the virtual location.

3. **Query Parameter for AST Tool**
   - *Reference:* `.plans/phase-11/PLAN.md:55` (`asex_ast_query`)
   - *Critique:* The plan lists `asex_ast_query` but does not specify its parameters. It must accept a `query` string (the `.scm` tree-sitter query) in addition to the standard `source`/`path` arguments, and return the matching nodes. This needs to be explicitly modeled in the tool's JSON schema definition.

## Invariants

- **`tools/mcp/compressor.py:1`**: Compressed modules must remain syntactically valid AgentScript (able to be parsed by tree-sitter without syntax errors).
- **`tools/mcp/server.py:1`**: MCP tool schemas must strictly define parameter types, required fields, and handle mutually exclusive inputs (e.g., `source` vs `path`).

## Ordering & Failure Modes

- **Missing Schema Validation (W2)**: If tool schemas are loose (e.g., allowing both `source` and `path` simultaneously without defined precedence), agents may send ambiguous requests causing the MCP server to execute the wrong payload.
- **Parse Failure Pipeline**: If W1 outputs invalid syntax, downstream AST queries on the compressed code will fail. W1 must pass a syntax-check gate on its own output before being considered complete.
