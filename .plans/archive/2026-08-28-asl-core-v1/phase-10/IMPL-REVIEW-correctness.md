**Lens**: Correctness
**Verdict**: reject

**Blockers**:

1. Dead state / unimplemented `stdin`.
   - **Evidence**: `WasmRunOptions` accepts `stdin`, but `fd_read` in `backend/ts/wasm_runner.ts` unconditionally writes `0` to `nread_ptr` (simulating immediate EOF) and never reads from `options.stdin`.
   - **Class**: Unimplemented functionality masquerading as supported. Any attempt to pass `stdin` to the WASM runner will silently fail by simulating an immediate EOF.

2. Missing memory bounds checks causing silent data corruption and incorrect error propagation.
   - **Evidence**:
     - In `fd_write`, `uint8.subarray(ptr, ptr + len)` silently clamps out-of-bounds memory ranges, but the un-clamped `len` is added to `totalWritten`. The guest is incorrectly informed that all bytes were written.
     - In `random_get`, writes to `uint8[buf_ptr + i]` silently fail for out-of-bounds indices in JS TypedArrays, leaving uninitialized memory that the guest assumes is populated.
     - In `args_get` and `environ_get`, `uint8.set()` throws an unhandled `RangeError` if out-of-bounds.
     - Out-of-bounds `DataView` accesses (e.g., `nread_ptr` in `fd_read`, `iovs` reads in `fd_write`) throw `RangeError`.
   - **Class**: Unsafe WASI boundary handling. Pointers passed by the guest must be bounds-checked against `memory.buffer.byteLength`, and invalid pointers must return the appropriate WASI errno (like `21` for `EFAULT`) rather than throwing JS exceptions or silently corrupting reads/writes.

3. Swallowed trap/runtime error messages.
   - **Evidence**: In `runWasm`, when an unknown exception occurs, the error message is assigned to `(handle.exports as any).stderrOutput = msg;`. This is never appended to the runner's `stderr` state, so the returned `WasmRunResult` has an empty `stderr` and the caller receives an exit code 134 with no diagnostic information.
   - **Class**: Error swallowing. Trap diagnostics are dropped instead of being surfaced to the caller.

**Non-blocking**:
- `clock_time_get` ignores the clock `id` and `precision` arguments and always returns the current wall-clock time. This technically violates WASI semantics for monotonic clocks but is acceptable for a mock runner.

**Unverified**:
- `backend/t/test_wasm_runner.py`: The user prompt requested reviewing this file, but it does not exist in the repository.

**Gates run**:
No specific execution gates were run as the core testing file was missing, but static analysis identified multiple critical memory safety and correctness violations.
