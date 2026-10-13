# asl-compiler

ASL modules for a compiler pipeline: a C99 path through `asl-codegen`, a WebAssembly binary encoder, a reference evaluator and supporting passes. The toolchain that runs today is `bin/asl` (bash and Python), the sourceless `bin/asl-core` and the C host in `asl/host`; this package is not yet on that path.

## Modules (`asl/packages/asl-compiler/src`)
- `compiler.asl`: `compileSourceToC99`, `compilePackageToC99!`, `compilePackageToLlvm!`, `formatDiagnostic`, capability checks.
- `targets.asl`: target dispatch to C99, C11, LLVM, Swift, Rust and shell backends.
- `wasm.asl`: WebAssembly v1 binary encoding (LEB128, sections, opcodes); its own header says `evalNode`, `invokeClosure`, `loadModule` and `makeEvalEnv` are stubs.
- `wasi.asl`: WASI preview 1 constants, import descriptors and capability checks.
- `evaluator.asl`: tree-walking evaluator (`evalSexpr`, environments, builtin groups).
- `elf.asl`, `macho.asl`: ELF64 and Mach-O ARM64 emitter sketches.
- `parser.asl`, `diagnostics.asl`, `heal.asl`, `comptime.asl`, `salsa.asl`, `compactRewrite.asl`, `optFold.asl`, `vfsGit.asl`, `macro.asl`, `monad.asl`, `threadMacro.asl`, `tryMacro.asl`: parsing, diagnostics with patch suggestions, compile-time evaluation, incremental queries, rewrites, a git reader and macros.

## Status
- Target: compile a module to Wasm or C from the CLI. Today `./bin/asl build` returns `ERR_UNIMPLEMENTED` ("produces no artifact until R1").
- Tests live in `asl/packages/asl-compiler/tests/` (32 files). On 2026-09-24 `./bin/asl test` (lenient asl-core) exits 0 on `evaluatorTest.asl` (36 assertions, 32 refutations) and `wasmTest.asl` (9 assertions, 6 refutations); `asl/host/out/asl-host test` exits 1 on both with load errors (21 and 2).
