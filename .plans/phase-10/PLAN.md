# Phase 10 — WebAssembly Browser Sandbox & Web Runner

## §1 Scope and acceptance

Build a pure, zero-native-dependency TypeScript/JavaScript in-memory WASI preview1 shim and Wasm runner (`backend/ts/wasm_runner.ts`) capable of executing AgentScript Wasm programs in both Browser and Node.js environments without depending on `node:wasi` or native filesystem bindings. Add `agentscript build <file> --target wasm [-o <out.wasm>]` support to the `agentscript` CLI, and verify whole-program execution over the corpus via unit tests.

### Acceptance Criteria

1. **In-memory WASI Preview1 Engine (`backend/ts/wasm_runner.ts`)**:
   Pure TypeScript/ESM module implementing WASI snapshot_preview1 imports (`fd_write` capturing stdout/stderr into in-memory buffers, `proc_exit` trapping exit codes, `environ_sizes_get`/`environ_get`, `args_sizes_get`/`args_get`, `clock_time_get`, `random_get`, `fd_seek`, `fd_close`, `fd_fdstat_get`, `fd_prestat_get`).
2. **Standard Execution Interface**:
   ```typescript
   export interface WasmRunOptions {
     args?: string[];
     env?: Record<string, string>;
     stdin?: string | Uint8Array;
   }
   export interface WasmRunResult {
     stdout: string;
     stderr: string;
     exitCode: number;
     durationMs: number;
   }
   export async function runWasm(
     wasmSource: BufferSource | WebAssembly.Module,
     options?: WasmRunOptions
   ): Promise<WasmRunResult>;
   ```
3. **CLI Wasm Compilation (`agentscript build <file> --target wasm [-o <out.wasm>]`)**:
   Compiles an `.agentscript` file through Rust backend to `wasm32-wasip1` binary, writing to stdout or `-o/--output`.
4. **Browser & Node Verification**:
   - Node test suite `backend/ts/test_wasm_runner.ts` runnable under `node --test` or compiled via `tsc`.
   - Pytest test suite `backend/t/test_wasm_runner.py` verifying valid corpus programs produce matching stdout/stderr/exit codes through the in-memory runner.
5. **Gates Clean**: All repository gates (`validate.py`, `closure_audit.py`, `checker/gate.py`, `check_corpus.py`, `monomorphism.py`, `differential.py`) remain green.

---

### Decisions

**D1 — Pure In-Memory WASI Preview1 Engine:**
The runner does not import `node:wasi` or `node:fs`. It interacts solely with WebAssembly Memory buffer views (`DataView`, `Uint8Array`) and string decoders (`TextDecoder`), making it directly bundlable for Web/React apps without polyfill overhead.

**D2 — Exit & Trapping Semantics:**
`proc_exit(code)` throws a private `WasiExit(code)` error that `runWasm()` catches and extracts as `exitCode`. WebAssembly runtime traps (e.g. integer overflow, unreachable) are surfaced with descriptive error messages and exit code 134/trap code.

**D3 — CLI Compilation Workflow:**
`agentscript build <file> --target wasm` invokes `backend/to_rust.py` to generate standalone Rust code, and compiles via `rustup run stable rustc --target wasm32-wasip1 -O --edition 2021` in a temporary workspace, emitting the raw `.wasm` bytes.

**D4 — Dual Export (TS and Compiled JS):**
`backend/ts/wasm_runner.ts` is compiled to `backend/ts/wasm_runner.js` with `.d.ts` declaration maps via `tsc` so it can be imported directly in browser bundles and Node scripts.

---

## §2 Inventory

**Modified:**
- `agentscript`: Add `wasm` to supported targets in `cmd_build` and add optional `-o/--output` argument.
- `package.json`: Add build/test script for wasm runner.

**New:**
- `backend/ts/wasm_runner.ts`: The WASI preview1 in-memory engine and `runWasm` execution harness.
- `backend/ts/test_wasm_runner.ts`: Integration tests for the TS runner.
- `backend/t/test_wasm_runner.py`: Pytest integration test compiling and running corpus programs via `wasm_runner`.

**Unchanged, verified:**
- `backend/to_rust.py`: Rust code generation.
- `backend/rust/rt.rs`: Rust runtime for AgentScript programs.
- `backend/differential.py`: Multi-arm differential gate.

---

## §3 Work Items

### W1 — WASI preview1 in-memory runner (`backend/ts/wasm_runner.ts`)
Implement `backend/ts/wasm_runner.ts` with `MemoryView` helpers and `wasi_snapshot_preview1` host import object.
*Target files:* `backend/ts/wasm_runner.ts`
*Gate:* Compile `backend/ts/wasm_runner.ts` with `npx tsc --noEmit` and assert clean typecheck.

### W2 — TypeScript test harness for WASI runner (`backend/ts/test_wasm_runner.ts`)
Implement test cases covering stdout/stderr capture, `proc_exit` handling, CLI argv passing, env var reading, and trap recovery.
*Target files:* `backend/ts/test_wasm_runner.ts`
*Gate:* Run compiled test harness via Node and assert all assertions pass.

### W3 — CLI `--target wasm` support in `agentscript`
Wire `wasm` target in `agentscript` CLI, using `backend/to_rust.py` and `rustc --target wasm32-wasip1` to emit compiled wasm binary.
*Target files:* `agentscript`
*Gate:* `agentscript build grammar/corpus/valid/01-basics.agentscript --target wasm -o /tmp/basics.wasm && file /tmp/basics.wasm` identifies as WebAssembly binary.

### W4 — Pytest integration test suite (`backend/t/test_wasm_runner.py`)
Add automated pytest tests compiling valid corpus programs to wasm and executing them via `wasm_runner.js` in Node, asserting stdout and exit codes.
*Target files:* `backend/t/test_wasm_runner.py`
*Gate:* `.venv/bin/pytest backend/t/test_wasm_runner.py -v` passes.

### W5 — Full gate verification
Run full project gate suite to ensure zero regressions.
*Gate:* `.venv/bin/python grammar/validate.py && .venv/bin/python grammar/closure_audit.py && .venv/bin/python checker/gate.py && .venv/bin/python backend/check_corpus.py && .venv/bin/python backend/monomorphism.py && .venv/bin/python backend/differential.py && .venv/bin/pytest backend/t`
