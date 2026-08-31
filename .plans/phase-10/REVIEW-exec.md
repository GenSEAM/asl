# Lens: Executability and Gates

**Verdict**: `approve-with-amendments`

### Blockers

1. **W1 Missing WASI edge cases (BigInt and iovec)**: A conformant-but-wrong implementation would use JS `number` for WASI `i64` types (like in `clock_time_get` or `fd_seek`) or fail to properly decode `iovec` arrays for `fd_write`. This leads to WebAssembly signature mismatch traps and memory corruption.
   - **Evidence**: The W1 description (line 75) does not mandate `BigInt` for `i64` signatures or `iovec` struct layout mapping (8-byte chunks of 32-bit offset/length).
   - **Fix**: Update W1 to explicitly require `BigInt` for `i64` WASI imports and correct parsing of `iovec` memory layouts.

2. **W1 Gate is not an executable command**:
   - **Evidence**: Line 77: `Compile backend/ts/wasm_runner.ts with npx tsc --noEmit and assert clean typecheck.`
   - **Fix**: Replace with an exact, fail-closed shell command: `npx tsc --noEmit backend/ts/wasm_runner.ts`.

3. **W2 Gate is not an executable command**:
   - **Evidence**: Line 82: `Run compiled test harness via Node and assert all assertions pass.`
   - **Fix**: Replace with an exact command, e.g., `npx tsc backend/ts/test_wasm_runner.ts && node --test backend/ts/test_wasm_runner.js`.

4. **W3 Gate is not fail-closed and missing `./`**:
   - **Evidence**: Line 87: `agentscript build ... && file /tmp/basics.wasm identifies as WebAssembly binary.` (relies on human evaluation, and `agentscript` may not be in PATH).
   - **Fix**: Replace with `./agentscript build grammar/corpus/valid/01-basics.agentscript --target wasm -o /tmp/basics.wasm && file /tmp/basics.wasm | grep -q 'WebAssembly'`.

### Non-blocking

1. **W4 Gate phrasing**: The gate command `.venv/bin/pytest backend/t/test_wasm_runner.py -v passes.` contains the word `passes.` which is informal. It should just be the raw command.

### Verified

- All target file paths and Python script locations (`backend/t`, `grammar/validate.py`, etc.) are accurate.
- `package.json` correctly includes `typescript` as a dev dependency, supporting W1/W2 tests.
- `agentscript` script exists and is executable in the root.

### Unverified

- Pytest fixtures or internal assertions of `backend/t/test_wasm_runner.py`, as the file does not exist yet.
