# Lens: SIMPLIFY

**Verdict**: `reject`

### Blockers

1. **Unmet Acceptance Criterion: Silently Skipped Pytest Suite**
   - **Evidence**: §1 Acceptance Criteria and W4 mandate a pytest suite at `backend/t/test_wasm_runner.py` verifying valid corpus programs via the in-memory runner. This file was silently skipped and does not exist.
   - **Class Enumeration**: Every required test suite must be implemented. Skipping an entire suite silently leaves integration paths untested and breaks the acceptance gate.

2. **Wrong Behaviour: Shared Stateful TextDecoder Across Independent Streams**
   - **Evidence**: In `wasm_runner.ts`, a single `TextDecoder('utf-8')` is instantiated in `createWasiImportObject` and used for all `fd_write` calls with `{ stream: true }`. Because `stdout` and `stderr` are independent byte streams, interleaving writes with partial UTF-8 sequences will cause the state from one stream to corrupt the decoded text of the other.
   - **Class Enumeration**: Any stateful parser or decoder must be scoped 1:1 with the stream it decodes. `stdout` (fd 1) and `stderr` (fd 2) require separate `TextDecoder` instances.

3. **Unauthorized Scope Expansion / Gold-Plating**
   - **Evidence**: `agentscript` CLI introduces brittle string-matching (`is_prog = "pub fn main_(" in rs_src ...`) to conditionally compile non-programs using `--target wasm32-unknown-unknown --crate-type=cdylib`. The plan explicitly and only specified compiling to `wasm32-wasip1`. 
   - **Class Enumeration**: Branching logic for unrequested targets introduces untested paths and brittle heuristics. The CLI should unconditionally target `wasm32-wasip1` as specified.

### Non-blocking

1. **Efficiency: Redundant String Encoding**
   - **Evidence**: `args_sizes_get` / `args_get` and `environ_sizes_get` / `environ_get` re-encode strings to `Uint8Array` via `TextEncoder` on every invocation. For a simpler and more efficient approach, these could be pre-encoded once in `createWasiImportObject`.
2. **Boilerplate: `memoryRef` State Tracking**
   - **Evidence**: `createWasmInstance` uses a mutable `let memoryRef: WebAssembly.Memory | null = null;` that gets captured by `createWasiImportObject` and mutated later. This boilerplate is unnecessary; the closure can directly reference `instance.exports.memory`, as `instance` is fully initialized before the guest invokes any WASI imports.

### Gates run

```
$ cat backend/t/test_wasm_runner.py
cat: backend/t/test_wasm_runner.py: No such file or directory
```

### Unverified

- Memory limits or large allocations, as the current test fixtures do not stress the memory buffer boundaries or `memory.grow` behavior.
