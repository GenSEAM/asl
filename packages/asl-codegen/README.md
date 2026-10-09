# asl-codegen

ASL source generators that turn parsed ASL (the `asl-parser` AST, typed by `asl-checker`) into Rust, ISO C99 or embedded C text.

## Modules
- Rust: `emit.asl` (top-level forms, `emitRustProgram`), `expr.asl` (expression and pattern lowering), `rtypes.asl` (type mapping and derives), `mangle.asl` (identifier and module-path mangling), `builtins.asl` (builtin templates, `renderBuiltin`).
- ISO C99: `c99Emit.asl` (translation unit, prototypes, `main` entry), `c99Expr.asl` (expression lowering), `c99Type.asl` (type mapping, Option/Result/Map typedefs), `c99Mangle.asl` (C identifier hygiene).
- Embedded C: `emitC.asl` (C and Arduino sketch headers, GPIO and delay calls, `emitCStandalone`).

## Status
- These modules are libraries; no command drives them. `./bin/asl build` returns `ERR_UNIMPLEMENTED` ("produces no artifact until R1"), so emitting a C or Rust file from the CLI is a target.
- Tests (2026-09-24): `./bin/asl test asl/packages/asl-codegen/tests/codegenTest.asl` exits 0 with 9 assertions on the lenient asl-core runner; the stage-0 host `asl/host/out/asl-host test` on the same file exits 1 (`ERR_TYPE: .-first expects a record, got Variant`).
