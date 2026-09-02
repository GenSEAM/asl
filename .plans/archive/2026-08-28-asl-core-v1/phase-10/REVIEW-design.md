# Design Review: Phase 10

**Verdict:** `approve-with-amendments`

## Findings

1. **Memory Growth Invalidation (Memory Isolation)**
   - **Severity:** High
   - **Description:** `.plans/phase-10/PLAN.md:41` states the runner "interacts solely with WebAssembly Memory buffer views (DataView, Uint8Array)". In WebAssembly, when memory grows (e.g., via `memory.grow`), the underlying `ArrayBuffer` is detached. Any previously cached `DataView` or `Uint8Array` will throw a `TypeError` upon access. The shim must not cache these views across Wasm calls; it must reconstruct them on-demand inside each WASI import call.

2. **Zero-Allocation Streaming Violations**
   - **Severity:** High
   - **Description:** `.plans/phase-10/PLAN.md:18-20` defines `WasmRunResult` as returning `stdout: string; stderr: string;`. Accumulating potentially unbounded output into large JavaScript strings directly violates the requirement for zero-allocation streaming patterns. For a web showcase, this blocks UI responsiveness and causes large GC pauses. `WasmRunOptions` should include streaming callbacks (e.g., `onStdout?: (chunk: Uint8Array) => void`) or return a stream, rather than forcing full string allocation.

3. **WASI Preview 1 vs Component Model (Preview 2)**
   - **Severity:** Medium
   - **Description:** `.plans/phase-10/PLAN.md:47` explicitly targets `wasm32-wasip1`. This is currently sound for a manual in-memory shim, as Preview 2 (Component Model) radically changes I/O to use the canonical ABI instead of linear memory exports. However, `wasm32-wasip1` is deprecated in future Rust toolchains in favor of `wasm32-wasip2`. The architectural assumption that Wasm memory linear exports will always be available for `fd_write` will break unless the toolchain target is explicitly pinned, or a transition path to Component Model JS tooling is planned.

4. **API Cleanliness & Entrypoint Ambiguity**
   - **Severity:** Low
   - **Description:** `.plans/phase-10/PLAN.md:24-27` exposes `runWasm(wasmSource, options)`. It is unstated whether this function instantiates the module and calls `_start()` (the WASI command model) or initializes it as a reactor. For an export invocation interface, cleanly separating module instantiation from the execution of the `_start` entrypoint allows the host to provide custom imports or interact with exported memory before execution begins.

5. **W1 Gate is Invalid**
   - **Severity:** Medium
   - **Description:** `.plans/phase-10/PLAN.md:77` defines W1's gate as `npx tsc --noEmit`. There is no `tsconfig.json` in the project root, and no file path is specified. This will fail immediately or trivially succeed without checking `wasm_runner.ts`. The gate should be `npx tsc backend/ts/wasm_runner.ts --noEmit --target ES2022 --module NodeNext` or similar.

## Invariants

- **Memory View Liveness:** The `wasi_snapshot_preview1` shim must always read `instance.exports.memory.buffer` locally within the host function invocation, never caching it in the outer closure. (Applies to W1, `.plans/phase-10/PLAN.md:41`).
- **Zero-Allocation Data Path:** Standard out and err paths from `fd_write` must directly forward `Uint8Array` slices to listeners without forcing `TextDecoder` allocation if the caller only wants binary streaming. (Applies to W1, W2, `.plans/phase-10/PLAN.md:18`).

## Ordering & Failure Modes

- **Ordering Risk:** W2 (tests) must strictly follow W1. W1 must be testable in isolation. If W3 (`agentscript build --target wasm`) is run before W1/W2 are stable, W4 integration tests cannot be meaningfully debugged (you won't know if the compiler or the runner is broken). W1 -> W2 -> W3 -> W4 is correct.
- **Failure Mode - Shared State Hazard:** If `runWasm` initializes a singleton `wasi_snapshot_preview1` import object for multiple concurrent Wasm instantiations, `fd_write` will race between instances trying to read different memories. The WASI import object must be instantiated *per* `runWasm` call.
- **Failure Mode - Trap Masking:** `.plans/phase-10/PLAN.md:44` catches `proc_exit` as a `WasiExit(code)`. If a true trap (e.g., Unreachable) occurs, it throws a `RuntimeError`. The wrapper must distinguish `WasiExit` from `RuntimeError` to ensure traps correctly exit with code 134, rather than swallowing the error or crashing the web app.

## Per-Item Gates

**W1:**
```bash
npx tsc backend/ts/wasm_runner.ts --noEmit --target ES2022
```
*Current output:* `error TS6053: File 'backend/ts/wasm_runner.ts' not found.`

**W2:**
```bash
node --test backend/ts/test_wasm_runner.ts
```
*Current output:* `Could not find 'backend/ts/test_wasm_runner.ts'`

**W3:**
```bash
.venv/bin/python agentscript build grammar/corpus/valid/01-basics.agentscript --target wasm -o /tmp/basics.wasm && file /tmp/basics.wasm | grep WebAssembly
```
*Current output:* `agentscript build: error: argument --target: invalid choice: 'wasm' (choose from 'py', 'rs')`

**W4:**
```bash
.venv/bin/pytest backend/t/test_wasm_runner.py -v
```
*Current output:* `ERROR: file or directory not found: backend/t/test_wasm_runner.py`

**W5:**
```bash
.venv/bin/python grammar/validate.py && .venv/bin/python grammar/closure_audit.py && .venv/bin/python checker/gate.py && .venv/bin/python backend/check_corpus.py && .venv/bin/python backend/monomorphism.py && .venv/bin/python backend/differential.py && .venv/bin/pytest backend/t
```
*Current output:* Executes cleanly, but does not yet cover Wasm because `test_wasm_runner.py` is missing from `backend/t/`.
