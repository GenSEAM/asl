# Phase 11 — Reconciliation

| ID | Lens | Finding | Disposition | Action |
|---|---|---|---|---|
| D1 | Design | Standardize tool result schemas (`valid`, `success`) | **Accept** | Structured dicts `{valid, diagnostics}` and `{stdout, stderr, exit_code, success}` |
| D2 | Design | Compress module output remains parse-valid | **Accept** | Body replaced with `(panic "interface")` or clean stub |
| D3 | Design | In-memory string support for AST queries | **Accept** | Support `source` string directly in `asex_ast_query` |
| E1 | Exec | Dual stdio framing (JSON lines & Content-Length) | **Accept** | Read loop accepts both newline-delimited JSON and HTTP-style headers |
| E2 | Exec | Standard JSON-RPC 2.0 error codes | **Accept** | Use -32700, -32600, -32601, -32602, -32603 error shapes |
| C1 | Coverage | Semantic diagnostic assert on invalid fixtures | **Accept** | Pytest covers both valid and semantic error fixtures |
| C2 | Coverage | Evaluator stdout/stderr/argv test | **Accept** | Pytest tests `08-io` with custom argv |
| C3 | Coverage | Formatter idempotence test | **Accept** | Pytest tests formatting unformatted vs formatted source |
