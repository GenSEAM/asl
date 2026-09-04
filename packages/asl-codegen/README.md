# @genseam/asl-codegen

Self-hosted, pure AgentScript code generator and module emitter.

## Overview
`asl-codegen` translates verified AgentScript AST structures from `@genseam/asl-parser` and typed signatures from `@genseam/asl-checker` into standalone target source code (Rust / WebAssembly).

## Architecture
- `mangle.asl`: Safe identifier and module path mangling into snake_case and PascalCase.
- `rtypes.asl`: Type declaration emission, derive traits (`Clone`, `PartialEq`, `PartialOrd`), Box wrapping for recursive types.
- `builtins.asl`: Code emission for standard prelude builtins (List, Map, String, Option, Result, math).
- `expr.asl`: Expression translation (`let`, `cond`, `match`, closures, function calls).
- `emit.asl`: Top-level form emission (`df`, `dfs`, `dfe`), module import resolution, and standalone executable assembly.

## Status
100% pure AgentScript. Zero Python/Rust/Go runtime dependencies in emitted logic.
