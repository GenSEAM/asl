# Phase 10 — Reconciliation

| ID | Lens | Finding | Disposition | Action |
|---|---|---|---|---|
| D1 | Design | Memory detachment on Wasm memory growth | **Accept** | Fresh `DataView` / `Uint8Array` instantiated on each host syscall invocation |
| D2 | Design | `createWasmInstance` helper for direct export invocation | **Accept** | Export `createWasmInstance()` alongside `runWasm()` in `wasm_runner.ts` |
| D3 | Design | WASI syscall 64-bit parameter typing (`bigint`) | **Accept** | Explicit `bigint` types for 64-bit offsets/timestamps |
| D4 | Design | Streaming `onStdout`/`onStderr` callbacks | **Accept** | Add optional streaming callbacks to `WasmRunOptions` |
| E1 | Exec | TS compilation flags for standalone validation | **Accept** | Add `backend/ts/tsconfig.json` and explicit `tsc` command |
| E2 | Exec | Ciovec 8-byte step and little-endian unpacking | **Accept** | Stride 8 bytes, unpack `ptr = getUint32(offset, true)`, `len = getUint32(offset + 4, true)` |
| E3 | Exec | `sys.stdout.buffer.write` for raw wasm in CLI | **Accept** | Use `sys.stdout.buffer.write` when emitting binary to stdout without `-o` |
| E4 | Exec | Null-terminator inclusion in `environ_get` / `args_get` | **Accept** | Account for `\0` in size calculation and write byte 0 |
| C1 | Coverage | Trap capture test in `test_wasm_runner.ts` | **Accept** | Add test case running numeric trap fixture |
| C2 | Coverage | Pure / zero-output exit 0 test | **Accept** | Add test case for clean empty output |
| C3 | Coverage | Non-zero exit code on `IoError` failure | **Accept** | Add test case verifying non-zero exit code capture |
