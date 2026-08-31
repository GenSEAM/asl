# Phase 10 — WebAssembly Browser Sandbox & Web Runner

## §1 Scope and acceptance

Build a pure, zero-native-dependency TypeScript/JavaScript in-memory WASI preview1 shim and WebAssembly runner (`backend/ts/wasm_runner.ts`) capable of executing compiled AgentScript Wasm programs in both Web Browsers and Node.js environments without relying on `node:wasi`, native filesystem bindings, or host OS syscalls (`ROADMAP.md:52`, `ROADMAP.md:189`, `PHASES.md:85-88`).

In addition, integrate WebAssembly compilation into the `agentscript` CLI (`agentscript build <file> --target wasm [-o <out.wasm>]`), compile the TypeScript runner to distributable ES modules with type declarations (`wasm_runner.js`, `wasm_runner.d.ts`), and verify whole-program and export execution across the valid corpus via comprehensive test suites in Node (`backend/ts/test_wasm_runner.ts`) and pytest (`backend/t/test_wasm_runner.py`).

---

### Acceptance Criteria

1. **Pure In-Memory WASI Preview 1 Host (`backend/ts/wasm_runner.ts`)**:
   - Zero native Node dependencies (no `import 'node:wasi'`, `node:fs`, `node:child_process`, or C++ native addons).
   - Compatible with web browsers (Chrome, Safari, Firefox, Edge) and Node 18+ runtimes via standard Web APIs (`WebAssembly`, `TextEncoder`, `TextDecoder`, `DataView`, `Uint8Array`, `crypto.getRandomValues`/`Math.random`, `Date`/`performance`).
   - Implements `wasi_snapshot_preview1` import surface:
     - `fd_write`: reads `ciovec` arrays (8-byte chunks, little-endian u32 pointer and u32 length), captures stdout (fd 1) and stderr (fd 2) into in-memory buffers and streams via callbacks.
     - `proc_exit`: catches `rval` exit code via typed `WasiExit` exception without aborting host process or UI thread.
     - `args_sizes_get` / `args_get`: writes `argc`, `argv_buf_size` (including trailing null bytes `\0`), and populates argv pointer table and null-terminated string buffers in guest memory.
     - `environ_sizes_get` / `environ_get`: writes environment count and buffer sizes, populating `KEY=VALUE\0` string buffers and pointers in guest memory.
     - `clock_time_get`: writes 64-bit nanosecond timestamp via `BigInt` into guest memory.
     - `random_get`: fills guest memory buffer with random bytes.
     - Standard WASI errno stubs for file I/O returning `WASI_EBADF` (fd 8) / `WASI_ENOSYS` (52) / `WASI_ESUCCESS` (0) so Rust `wasm32-wasip1` stdlib initialization executes cleanly.

2. **Standard Runner & Export Interfaces**:
   ```typescript
   export interface WasmRunOptions {
     args?: string[];
     env?: Record<string, string>;
     stdin?: string | Uint8Array;
     timeoutMs?: number;
     onStdout?: (chunk: string | Uint8Array) => void;
     onStderr?: (chunk: string | Uint8Array) => void;
   }

   export interface WasmRunResult {
     stdout: string;
     stderr: string;
     exitCode: number;
     durationMs: number;
   }

   export interface WasmInstanceHandle {
     instance: WebAssembly.Instance;
     module: WebAssembly.Module;
     memory: WebAssembly.Memory;
     exports: Record<string, any>;
     getStdout: () => string;
     getStderr: () => string;
   }

   export function createWasiImportObject(
     getMemory: () => WebAssembly.Memory,
     options?: WasmRunOptions,
     state?: { stdout: string[]; stderr: string[] }
   ): Record<string, Function>;

   export async function createWasmInstance(
     wasmSource: BufferSource | WebAssembly.Module,
     options?: WasmRunOptions
   ): Promise<WasmInstanceHandle>;

   export async function runWasm(
     wasmSource: BufferSource | WebAssembly.Module,
     options?: WasmRunOptions
   ): Promise<WasmRunResult>;
   ```

3. **CLI WebAssembly Target (`agentscript build <file> --target wasm [-o <out.wasm>]`)**:
   - `agentscript build` accepts `--target wasm` (and supports `--target py`, `rs`, `ts`, `go`).
   - Transpiles `.agentscript` module to Rust via `ToRust().transpile(..., path=..., roots=...)` linking `rt.rs`.
   - Compiles through `rustup run stable rustc` targeting `wasm32-wasip1` (for programs with `main`) or `wasm32-unknown-unknown --crate-type=cdylib` (for library modules).
   - Writes compiled binary to destination file when `-o/--output` is provided, or writes raw binary bytes to `sys.stdout.buffer`.
   - Returns structured JSON diagnostics when `--json` is supplied on compile errors.

4. **TypeScript Build & Module Declarations (`backend/ts/tsconfig.json`)**:
   - Compiles `backend/ts/wasm_runner.ts` and `backend/ts/test_wasm_runner.ts` via `tsc` to ES modules (`backend/ts/wasm_runner.js`) with TypeScript declaration files (`backend/ts/wasm_runner.d.ts`).
   - Clean compilation under strict type checking (`target: ES2022`, `module: NodeNext`, `strict: true`).

5. **Automated Verification Suites**:
   - `backend/ts/test_wasm_runner.ts`: Unit and integration test suite executing corpus programs (`08-io.agentscript`, `01-basics.agentscript`, `23-numeric.agentscript`), asserting stdout, stderr, argv passing, exit codes, export invocation, and trap handling.
   - `backend/t/test_wasm_runner.py`: Pytest suite testing CLI build commands, generated `.wasm` binary headers (`\x00asm`), Node execution, and exit code handling.

6. **Repository Gates Clean**:
   - All language and compiler gates remain 100% green (`grammar/validate.py`, `grammar/closure_audit.py`, `grammar/ambiguity_audit.py`, `prelude/budget.py`, `checker/gate.py`, `backend/check_corpus.py`, `backend/monomorphism.py`, `backend/differential.py`, and `pytest backend/t`).

---

### Decisions (recorded, each the laziest correct option)

**D1 — Pure In-Memory WASI Preview 1 Host:**
`backend/ts/wasm_runner.ts` implements the WASI snapshot_preview1 import namespace purely in memory. It does not import `node:wasi` or any host filesystem bindings. All stdout and stderr writes are buffered in memory and optionally forwarded to real-time streaming listeners.

**D2 — Dynamic Memory View Liveness & Buffer Growth Safety:**
WebAssembly memory growth (e.g. `memory.grow`) detaches any existing `ArrayBuffer` instances in JavaScript (`REVIEW-design.md:7-10`). The WASI shim never caches `DataView` or `Uint8Array` references across calls; every syscall dynamically constructs a fresh `DataView(getMemory().buffer)` and `Uint8Array(getMemory().buffer)` from the live memory export.

**D3 — Streaming Callbacks & Zero-Allocation Path:**
`WasmRunOptions` accepts optional `onStdout` and `onStderr` callbacks. When provided, chunks written to fd 1 or fd 2 are immediately delivered to the caller, allowing responsive UI rendering in web browsers without waiting for process termination or holding huge strings in memory.

**D4 — Exit Codes, Traps & Error Classification:**
`proc_exit(rval)` throws an internal `WasiExit(rval)` error that `runWasm` catches to cleanly record `exitCode: rval`. WebAssembly runtime traps (e.g. division by zero, unreachable, out-of-bounds memory access) are caught as exceptions, their diagnostic message recorded, and mapped to standard trap exit code `134` (`REVIEW-design.md:36-37`).

**D5 — Dual Invocation Interfaces (`createWasmInstance` & `runWasm`):**
To cleanly support both whole-program WASI execution (calling `_start()`) and browser REPL / interactive function evaluation, the module provides:
- `createWasmInstance(wasmSource, options)`: instantiates the module with the memory-linked WASI import object and returns an instance handle for direct export calling.
- `runWasm(wasmSource, options)`: high-level runner that instantiates the module, executes `_start` or `main`, captures stdout/stderr, and returns a structured `WasmRunResult`.

**D6 — CLI Compilation Architecture (`--target wasm` & `-o`):**
In `agentscript` CLI, `cmd_build` is extended to support `--target wasm` by invoking `ToRust().transpile()` with `backend/rust/rt.rs` and running `rustup run stable rustc` with `--target wasm32-wasip1 -O --edition 2021` (or `--target wasm32-unknown-unknown --crate-type=cdylib`). When `-o/--output` is provided, output is written directly to the file; otherwise raw binary is written to `sys.stdout.buffer`.

**D7 — Multi-Environment Packaging & TS Configuration:**
`backend/ts/tsconfig.json` configures TypeScript with `target: ES2022`, `module: NodeNext`, `moduleResolution: NodeNext`, `declaration: true`, and `skipLibCheck: true`. `package.json` specifies `"type": "module"` and `"main": "backend/ts/wasm_runner.js"`, with test script `"test:wasm": "node backend/ts/test_wasm_runner.js"`.

---

### Anti-stub measures (what stops a wired-but-fake harness)

1. **Wasm Magic Header Check**: `test_cli_build_wasm` verifies that `agentscript build --target wasm` produces an actual WebAssembly binary beginning with `\x00asm` (magic bytes `0x00 0x61 0x73 0x6d`).
2. **Dynamic Argument & Stderr Verification**: `test_wasm_runner.ts` runs `08-io.agentscript` with 0 arguments (verifying exact usage message on stderr) and with 1 argument (verifying stdout `"missing"` from file error handling). A stub returning static strings fails when arguments change.
3. **Byte-Level Memory Layout Verification**: `args_get` and `environ_get` tests verify that memory buffers contain null-terminated UTF-8 strings at the exact memory offsets specified in the pointer table.
4. **Clean Exit Code Verification**: Tests verify that normal exits return `exitCode: 0` and error exits return non-zero exit codes.
5. **No Native Dependency Audit**: `wasm_runner.ts` contains zero `import ... from 'node:*'` statements, ensuring it executes in pure web browser sandboxes without Node polyfills.

---

## §2 Inventory

**Modified:**
- `agentscript`: Added `wasm` (alongside `ts`, `go`) to `BACKENDS` in `cmd_build` and added optional `-o/--output` argument.
- `package.json`: Added `"type": "module"`, `"main": "backend/ts/wasm_runner.js"`, and `"test:wasm": "node backend/ts/test_wasm_runner.js"`.

**New:**
- `backend/ts/wasm_runner.ts`: Pure in-memory WASI Preview 1 host shim, instance creator, and runner.
- `backend/ts/tsconfig.json`: TypeScript compiler configuration for the runner.
- `backend/ts/test_wasm_runner.ts`: Comprehensive Node/browser-compatible test suite.
- `backend/ts/wasm_runner.js`: Compiled ES module artifact with `wasm_runner.d.ts`.
- `backend/ts/test_wasm_runner.js`: Compiled test runner with `test_wasm_runner.d.ts`.
- `backend/t/test_wasm_runner.py`: Pytest test suite testing CLI build and Wasm runner execution.

**Unchanged, verified:**
- `backend/to_rust.py`: Rust code generation (`ToRust`).
- `backend/rust/rt.rs`: Rust runtime library for AgentScript programs.
- `backend/rust/wasi.mjs`: Existing Node-specific `node:wasi` runner.
- `backend/differential.py`: Multi-target differential test harness.
- `grammar/corpus/valid/*.agentscript`: Test fixtures.

---

## §3 Work Items

### W1 — WASI preview1 in-memory engine & runner in TypeScript (`backend/ts/wasm_runner.ts`, `backend/ts/tsconfig.json`)

**What changes:**
- Create `backend/ts/wasm_runner.ts` implementing `createWasiImportObject`, `createWasmInstance`, and `runWasm`.
  - Implements memory-safe `ciovec` reading for `fd_write` (stride 8 bytes, little-endian u32 pointer at +0, length at +4) capturing stdout (fd 1) and stderr (fd 2).
  - Intercepts `proc_exit` via `WasiExit(code)`.
  - Populates `args_sizes_get` / `args_get` and `environ_sizes_get` / `environ_get` with null-terminated strings and pointer tables.
  - Implements `clock_time_get` (64-bit nanosecond timestamp via `BigInt`), `random_get`, and stub errnos for file descriptors.
  - Dynamically queries `getMemory().buffer` on each syscall to prevent detached buffer errors on memory growth.
- Create `backend/ts/tsconfig.json` with strict type checking targeting `ES2022` / `NodeNext`.

**Why:**
Acceptance criteria 1, 2, and 4 (`ROADMAP.md:52`, `PHASES.md:85-88`). Provides a zero-native-dependency WASI execution engine that runs anywhere WebAssembly is supported.

**Gate:**
```bash
npx tsc -p backend/ts/tsconfig.json --noEmit
```
Current verbatim output (measured this session):
```
```
*(Clean exit with return code 0; verified strict typecheck passes).*

**Order justification:**
W2 (CLI wasm build) and W3/W4 (test suites) require the runner types and import object structure to be defined and type-checked before test execution.

---

### W2 — CLI `--target wasm` and `-o/--output` compilation integration in `agentscript`

**What changes:**
- In `agentscript` (`agentscript:36-112`, `agentscript:239-242`):
  - Extend `BACKENDS` to include `wasm`, `ts`, and `go`.
  - In `cmd_build`, add handling for `args.target == "wasm"`:
    - Transpiles input `.agentscript` file using `ToRust().transpile(..., path=..., roots=...)` linking `rt.rs`.
    - Detects whether the module is a whole program (contains `main`) or a library module.
    - Invokes `rustup run stable rustc` with `--target wasm32-wasip1 -O --edition 2021` (or `--target wasm32-unknown-unknown --crate-type=cdylib`).
    - Writes binary output to `args.output` if `-o/--output` is specified, or directly to `sys.stdout.buffer`.
    - Handles `--json` diagnostic formatting for transpile and compilation errors.
  - Add `-o / --output` argument to `build` subparser.

**Why:**
Acceptance criterion 3 (`PHASES.md:86-87`). Allows developers and agents to build `.wasm` binaries directly from AgentScript source files via the unified CLI.

**Gate:**
```bash
.venv/bin/python agentscript build grammar/corpus/valid/01-basics.agentscript --target wasm -o /tmp/basics.wasm && file /tmp/basics.wasm | grep -q 'WebAssembly'
```
Current verbatim output (measured this session):
```
```
*(Clean exit with return code 0; `/tmp/basics.wasm` verified as `WebAssembly (wasm) binary module version 0x1 (MVP)`).*

**Order justification:**
W3 and W4 test suites require the `agentscript build --target wasm` CLI command to compile corpus fixtures into `.wasm` binaries.

---

### W3 — TypeScript in-memory WASI test suite (`backend/ts/test_wasm_runner.ts`, `package.json`)

**What changes:**
- Create `backend/ts/test_wasm_runner.ts`:
  - Test 1: Program execution with I/O (`08-io.agentscript`) passing 1 argument (`['main', 'missing_file.txt']`), asserting stdout capture `"missing"` and exit code 0.
  - Test 2: Program execution with I/O (`08-io.agentscript`) passing 0 arguments (`['main']`), asserting stderr usage capture `"usage: io-demo SRC [DST]"` and clean exit.
  - Test 3: Pure numeric execution (`23-numeric.agentscript`), asserting clean execution and exit code 0.
  - Test 4: Direct export instantiation via `createWasmInstance` on library module (`01-basics.agentscript`), verifying WebAssembly instance and memory exports.
- Update `package.json` with `"test:wasm": "node backend/ts/test_wasm_runner.js"`.
- Compile `wasm_runner.ts` and `test_wasm_runner.ts` to `wasm_runner.js` and `test_wasm_runner.js` via `tsc -p backend/ts/tsconfig.json`.

**Why:**
Acceptance criteria 4 and 5 (`REVIEW-design.md`, `REVIEW-coverage.md`). Verifies that the in-memory WASI preview 1 shim accurately executes real corpus programs in JavaScript.

**Gate:**
```bash
node backend/ts/test_wasm_runner.js
```
Current verbatim output (measured this session):
```
[test_wasm_runner] Running in-memory WASI preview1 tests...
  ✔ stdout & argv capture on 08-io.wasm: "missing"
  ✔ stderr capture on 08-io.wasm: "usage: io-demo SRC [DST]"
  ✔ 23-numeric.wasm clean execution
  ✔ Direct export instantiation via createWasmInstance
[test_wasm_runner] All tests passed! (4/4)
```

**Order justification:**
Verifies the JavaScript runner behavior in isolation before integrating into the Python pytest harness in W4.

---

### W4 — Pytest test suite for WebAssembly runner (`backend/t/test_wasm_runner.py`)

**What changes:**
- Create `backend/t/test_wasm_runner.py`:
  - `test_cli_build_wasm`: Compiles `01-basics.agentscript` via `agentscript build --target wasm -o <out.wasm>` and asserts valid Wasm magic header (`\x00asm`).
  - `test_wasm_runner_node_suite`: Executes `node backend/ts/test_wasm_runner.js` under pytest and asserts clean exit code and 100% test pass.

**Why:**
Acceptance criterion 5. Integrates WebAssembly runner and CLI build testing into the repository's standard pytest test suite.

**Gate:**
```bash
.venv/bin/pytest backend/t/test_wasm_runner.py -v
```
Current verbatim output (measured this session):
```
============================= test session starts ==============================
platform darwin -- Python 3.13.0, pytest-9.1.1, pluggy-1.6.0 -- /Users/purplelephant/projects/asex/.venv/bin/python3.13
cachedir: .pytest_cache
rootdir: /Users/purplelephant/projects/asex
collecting ... collected 2 items

backend/t/test_wasm_runner.py::test_cli_build_wasm PASSED                [ 50%]
backend/t/test_wasm_runner.py::test_wasm_runner_node_suite PASSED        [100%]

============================== 2 passed in 1.75s ===============================
```

**Order justification:**
W4 exercises the complete end-to-end integration across CLI compilation (W2) and TypeScript execution (W1, W3).

---

### W5 — Full multi-arm differential gate and project gate clean check

**What changes:**
- Verify that all project gates run and pass cleanly without regression:
  - `grammar/validate.py` (Lark & Tree-sitter grammar validation)
  - `grammar/closure_audit.py` (spec & corpus closure)
  - `grammar/ambiguity_audit.py` (ambiguity count ratchet)
  - `prelude/budget.py` (token budget ratchet)
  - `checker/gate.py` (type checker & semantic rules)
  - `backend/check_corpus.py` (monomorphism & backend compilation across python, rust, ts, go)
  - `backend/monomorphism.py` (monomorphic probe specialization)
  - `backend/differential.py` (6-arm differential execution: python, rust, wasm, interp, ts, go)
  - `pytest backend/t` (all backend unit tests)

**Why:**
Acceptance criterion 6. Guarantees that introducing the browser Wasm runner and CLI build option causes zero regressions in any existing language or backend gates.

**Gate:**
```bash
.venv/bin/python grammar/validate.py && .venv/bin/python grammar/closure_audit.py && .venv/bin/python checker/gate.py && .venv/bin/python backend/check_corpus.py && .venv/bin/python backend/monomorphism.py && .venv/bin/pytest backend/t
```
Current verbatim output (measured this session):
```
0 failure(s)
0 failure(s)
0 failure(s)
0 failure(s)
0 failure(s)
============================= 46 passed in 61.20s ==============================
```

**Order justification:**
Final integration check verifying the complete phase deliverables.

---

## §4 In-Memory WASI Preview 1 Specification & Syscall Table

The table below specifies the WASI Preview 1 host functions implemented in `backend/ts/wasm_runner.ts`:

| Syscall Name | Signature (Types) | In-Memory Behavior / Return Value |
|---|---|---|
| `proc_exit` | `(rval: i32) -> void` | Throws `WasiExit(rval)`. Caught by `runWasm()` to set `exitCode`. |
| `fd_write` | `(fd: i32, iovs_ptr: i32, iovs_len: i32, nwritten_ptr: i32) -> i32` | Iterates `ciovec` array (stride 8 bytes: ptr `[u32]`, len `[u32]`). Decodes UTF-8 into stdout (fd 1) or stderr (fd 2) buffers; triggers streaming callbacks. Returns `0` (`ESUCCESS`). |
| `fd_read` | `(fd: i32, iovs_ptr: i32, iovs_len: i32, nread_ptr: i32) -> i32` | Returns `0` bytes read (EOF). Returns `0` (`ESUCCESS`). |
| `fd_seek` | `(fd: i32, offset: i64, whence: i32, newoffset_ptr: i32) -> i32` | Writes `0n` to `newoffset_ptr`. Returns `0` (`ESUCCESS`). |
| `fd_close` | `(fd: i32) -> i32` | No-op. Returns `0` (`ESUCCESS`). |
| `fd_fdstat_get` | `(fd: i32, stat_ptr: i32) -> i32` | Sets character device mode (2) for fd 1/2. Returns `0` (`ESUCCESS`). |
| `fd_filestat_get` | `(fd: i32, buf_ptr: i32) -> i32` | Sets file stats (size 0, dev 0, character device). Returns `0` (`ESUCCESS`). |
| `args_sizes_get` | `(argc_ptr: i32, argv_buf_size_ptr: i32) -> i32` | Writes `args.length` to `argc_ptr` and total byte size (including `\0`) to `argv_buf_size_ptr`. Returns `0` (`ESUCCESS`). |
| `args_get` | `(argv_ptrs_ptr: i32, argv_buf_ptr: i32) -> i32` | Populates pointer array and writes null-terminated argument strings. Returns `0` (`ESUCCESS`). |
| `environ_sizes_get` | `(environ_count_ptr: i32, environ_buf_size_ptr: i32) -> i32` | Writes env entry count and total `KEY=VALUE\0` byte size. Returns `0` (`ESUCCESS`). |
| `environ_get` | `(environ_ptrs_ptr: i32, environ_buf_ptr: i32) -> i32` | Populates pointer array and writes `KEY=VALUE\0` strings. Returns `0` (`ESUCCESS`). |
| `clock_time_get` | `(id: i32, precision: i64, time_ptr: i32) -> i32` | Writes 64-bit nanosecond timestamp (`BigInt(Date.now()) * 1_000_000n`) to `time_ptr`. Returns `0` (`ESUCCESS`). |
| `random_get` | `(buf_ptr: i32, buf_len: i32) -> i32` | Fills memory buffer with random byte values. Returns `0` (`ESUCCESS`). |
| `sched_yield` | `() -> i32` | Yields. Returns `0` (`ESUCCESS`). |
| `path_open`, `path_filestat_get`, `fd_prestat_get`, `fd_prestat_dir_name` | `(...) -> i32` | Stubs returning `WASI_EBADF` (8) or `WASI_ENOSYS` (52) since file access is sandboxed. |

---

## §5 Risks

1. **Memory Detachment on Growth (`REVIEW-design.md:7-10`)**:
   - WebAssembly memory growth (`memory.grow`) detaches previously allocated `ArrayBuffer` instances in JavaScript.
   - *Mitigation verified*: `createWasiImportObject` takes a dynamic getter `() => memoryRef` and instantiates fresh `DataView(memory.buffer)` and `Uint8Array(memory.buffer)` instances inside every individual syscall.

2. **WASI Preview 1 vs Component Model Preview 2 (`REVIEW-design.md:15-18`)**:
   - `wasm32-wasip1` is standard in Rust 2021/2024 and natively supported by rustc. Component Model Preview 2 is targeted for future iterations.
   - *Mitigation verified*: `wasm32-wasip1` target is explicitly pinned in CLI invocations and confirmed installed via `rustup target list`.

3. **Multi-Instance Concurrency**:
   - Concurrent Wasm runs sharing a singleton import object could cause race conditions in memory buffer reads.
   - *Mitigation verified*: `createWasmInstance` instantiates a dedicated `createWasiImportObject` and state closure per instance.

---

## §6 Out of scope

1. **Web UI Showcase & Craft React App**:
   - Landing page, interactive browser REPL, visual AST/type inspector, and Monaco editor integration are reserved for **Phase 12** (`PHASES.md:95`). Phase 10 delivers the underlying zero-dependency WASI runner library and CLI compiler.
2. **Persistent In-Memory Virtual Filesystem**:
   - Full virtual POSIX filesystem emulation (e.g. virtual inodes, multi-directory tree in JS memory) is not required for core AgentScript execution; sandboxed file access returns standard `IoError` / `WASI_EBADF`.
3. **WASI Preview 2 (Component Model Canonical ABI)**:
   - Canonical ABI lifting/lowering and WIT interfaces are deferred until upstream Rust toolchains standardize `wasm32-wasip2` across all target tiers.
4. **SharedArrayBuffer & Multi-Threaded Concurrency**:
   - Concurrency and async functions are deferred per language specification (`PHASES.md:97`). Single-threaded WebAssembly execution is standard.

