1. **Lens** — COVERAGE
2. **Verdict** — reject
3. **Blockers**
1. Missing timeout handling for `asex_eval`. Evidence: `asex_eval` executes code (lines 7, 20) but no timeout is mentioned, which could block the server on infinite loops. Fix: Require a timeout mechanism for `asex_eval`.
2. Missing input validation. Evidence: D2 (line 39) says tools accept `source` or `path`, but does not mention validation if both/neither are provided. Fix: Specify input validation and error returns.
3. Missing JSON-RPC error handling. Evidence: W2 (line 70) doesn't specify handling of invalid requests or standard JSON-RPC errors. Fix: Specify error handling.
4. Syntax errors. Evidence: Line 19 mentions exact rule violations, but not parse/syntax errors. Fix: Specify how syntax errors are reported.
4. **Non-blocking**
None
5. **Verified**
Plan includes all 5 required tools.
6. **Unverified**
None
