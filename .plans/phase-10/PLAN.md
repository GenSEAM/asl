# Phase 10 — Self-Hosted Rust Code Generator (`packages/asl-codegen`) in Pure AgentScript (asl-selfhosted-runtime-v1)

*Drafted under the steps protocol (@pcp:d-8d4c). Pure AgentScript self-hosted implementation of Rust code emission, AST lowering, builtin template substitution, and standalone compiler bootstrap.*

## Acceptance Criterion

```bash
.venv/bin/python -m pytest tools/tests/test_native_codegen.py -q && .venv/bin/python checker/gate.py && ./asl compile --backend rust --native grammar/corpus/valid/01-basics.agentscript -o /tmp/basics_native.rs && rustup run stable rustc /tmp/basics_native.rs --crate-type=bin -o /tmp/basics_bin
```

Transpiled `packages/asl-codegen` (via `tools/native_codegen.py` and `./asl compile --backend rust --native`):
1. Emits valid, compiling Rust code for all 36 `grammar/corpus/valid/*.agentscript` files.
2. Every emitted Rust file compiles cleanly under `rustc` with the runtime header (`backend/rust/rt.rs`).
3. `tools/tests/test_native_codegen.py` passes 100%, verifying pairwise behavioral and compilation equivalence against `backend/to_rust.py`.
4. `packages/asl-codegen` passes all checker and clone gates (`checker/gate.py` and `agentscript clone-check packages/ --threshold 0.15`).

---

## Context & Motivation

Phase 7 delivered the self-hosted parser (`packages/asl-parser`). Phase 9 delivered the self-hosted semantic checker (`packages/asl-checker`). 

Currently, compiler emission is performed by Python:
- `backend/to_rust.py` (Lark AST -> Rust source string).
- `backend/to_python.py`, `to_typescript.py`, `to_go.py`.

Without a self-hosted emitter, AgentScript cannot compile itself without Python. Implementing `packages/asl-codegen` in pure AgentScript closes the compiler loop:
```
[AgentScript Source] 
       │
       ▼ (packages/asl-parser)
   [ASL AST]
       │
       ▼ (packages/asl-checker)
  [Typed AST]
       │
       ▼ (packages/asl-codegen)
  [Rust Source] 
       │
       ▼ (rustc)
 [Native Binary 'asl'] (Zero Python runtime dependency)
```

---

## Core Invariants

1. **Deterministic Byte-Level Formatting**:
   Given an identical AST, `packages/asl-codegen` must emit deterministic, byte-reproducible Rust source code.
2. **Conservative Ownership & Clone-At-Use (@pcp:l-880d)**:
   In this first self-hosted code generator, values are passed and returned by value and cloned (`.clone()`) on variable reads to guarantee memory safety in emitted Rust without complex borrowck analysis.
3. **Runtime Header Invariant (`backend/rust/rt.rs`)**:
   Emitted Rust relies on the verified standard runtime header (`rt.rs`). Emitted types map cleanly:
   - `Bool` -> `bool`
   - `Int32` -> `i32`
   - `Int64` -> `i64`
   - `Float64` -> `f64`
   - `String` -> `String`
   - `Unit` -> `()`
   - `List T` -> `Vec<T>`
   - `Map K V` -> `std::collections::BTreeMap<K, V>`
   - `Option T` -> `Option<T>`
   - `Result T E` -> `Result<T, E>`
   - `IoError` -> `rt::IoError`
4. **Identifier & Keyword Mangling**:
   Kebab-case names (`foo-bar`) become `foo_bar`.
   Predicate functions ending in `?` (`empty?`) become `is_empty`.
   Mutating/effect functions ending in `!` (`write!`) become `write_mut`.
   Rust reserved keywords (`type`, `match`, `fn`, `let`, `loop`, `ref`, `impl`, `main`) append a trailing underscore (`type_`).
5. **No Recursion Overflow in Generator**:
   Expression emission for deeply nested ASTs (up to 2000 nodes) must execute using tail recursion, fold loops, or worklists, never blowing stack frames.

---

## Work Items

### Item 1: Package Manifest, Identifier Mangling & Keyword Escaping
- **Files**:
  - `packages/asl-codegen/asl.json`
  - `packages/asl-codegen/src/mangle.asl`
  - `packages/asl-codegen/tests/mangle_test.asl`
- **What it implements**:
  - `mangle-ident [(s String)] -> String`: snake_case conversion, `?` -> `is_`, `!` -> `_mut`, Rust keyword escaping.
  - `pascal-ident [(s String)] -> String`: PascalCase conversion for struct/enum types.
  - `rust-mod-name [(mod-path String)] -> String`: module path mangling (`foo/bar` -> `foo_bar`).
- **Gate**:
  `.venv/bin/python checker/gate.py && .venv/bin/python ./agentscript test packages/asl-codegen/tests/mangle_test.asl`

### Item 2: Rust Type Generator & Trait Derivations
- **Files**:
  - `packages/asl-codegen/src/types.asl`
  - `packages/asl-codegen/tests/types_test.asl`
- **What it implements**:
  - `emit-type [(t ty/Type)] -> String`: maps AST `Type` to Rust type syntax (`Vec<...>`, `BTreeMap<...>`, `Option<...>`, `Result<...>`, primitives).
  - `needs-partial-ord-only? [(t ty/Type)] -> Bool`: checks if type transitively contains `Float64`, switching derives from `Eq, Ord` to `PartialEq, PartialOrd`.
  - `emit-struct-derives [(has-float Bool)] -> String`: generates `#[derive(Clone, Debug, ...)]`.
- **Gate**:
  `.venv/bin/python checker/gate.py && .venv/bin/python ./agentscript test packages/asl-codegen/tests/types_test.asl`

### Item 3: Builtin Template Engine
- **Files**:
  - `packages/asl-codegen/src/builtins.asl`
  - `packages/asl-codegen/tests/builtins_test.asl`
- **What it implements**:
  - Table of all 107 builtins from `prelude/prelude.json` with their Rust lowering templates (`b["rs"]`).
  - `render-builtin [(bname String) (args (List String))] -> (Option String)`: expands `{0}`, `{1}`, etc. templates safely.
- **Gate**:
  `.venv/bin/python checker/gate.py && .venv/bin/python ./agentscript test packages/asl-codegen/tests/builtins_test.asl`

### Item 4: Expression & Pattern Lowering Engine
- **Files**:
  - `packages/asl-codegen/src/expr.asl`
  - `packages/asl-codegen/tests/expr_test.asl`
- **What it implements**:
  - Literal emission: numbers, booleans, string escaping (escaped quotes and newlines).
  - Variable references and field accesses (`(.-foo bar)` -> `bar.foo`).
  - Calls: builtin template rendering vs regular function invocation.
  - Special forms:
    - `let`: block `let` bindings with semicolons.
    - `if` / `cond`: Rust `if ... else if ... else`.
    - `match`: Rust `match` with pattern arms, constructor destructuring, tuple/cons patterns.
    - `try`: postfix `?` propagation.
    - `fn`: Rust closures `|...| { ... }`.
- **Gate**:
  `.venv/bin/python checker/gate.py && .venv/bin/python ./agentscript test packages/asl-codegen/tests/expr_test.asl`

### Item 5: Top-Level Forms, Module Assembly & Runtime Linking
- **Files**:
  - `packages/asl-codegen/src/emit.asl`
  - `packages/asl-codegen/tests/codegen_test.asl`
- **What it implements**:
  - `defun` emission: function signature, parameter types, return type, body.
  - `defschema` emission: struct definition, derives, field definitions, and constructor helper functions.
  - `defenum` emission: enum definition, cases, and case constructor helpers.
  - Module linking: bundle transitive modules as nested Rust `pub mod` blocks.
  - Main entry point: `emit-rust-program [(root-mod Module) (deps (Map String Module))] -> String`.
- **Gate**:
  `.venv/bin/python checker/gate.py && .venv/bin/python ./agentscript test packages/asl-codegen/tests/codegen_test.asl`

### Item 6: Python Bridge, CLI Integration & Full Rustc Validation
- **Files**:
  - `tools/native_codegen.py`
  - `tools/tests/test_native_codegen.py`
  - `agentscript` (`asl compile --backend rust --native`)
- **What it implements**:
  - Bridge to execute `packages/asl-codegen` from Python / CLI.
  - Pytest suite testing all 36 `grammar/corpus/valid/*.agentscript` fixtures:
    1. Parse with `asl-parser`.
    2. Check with `asl-checker`.
    3. Emit Rust with `asl-codegen`.
    4. Compile with `rustc` and assert exit code 0.
- **Gate**:
  `.venv/bin/python -m pytest tools/tests/test_native_codegen.py -q && .venv/bin/python checker/gate.py && .venv/bin/python agentscript clone-check packages/ --threshold 0.15`
