---
name: agentscript-native
description: Enforces AgentScript (ASL) native-first architecture. All logic, modules, and tests must be in ASL. Wasm-first by default; transpile to Rust/binary only when isolated native host bridges are needed.
---

# AgentScript Native Project Directive

This project is built and maintained under the **AgentScript Native Policy**:

## 1. Pure ASL Source Code Plane
- **All primary source logic, modules, schemas, and tests MUST be written in `.asl`** (`packages/**/*.asl`).
- Python, TypeScript/Node, and Rust are **compilation targets, execution runtimes, or foreign host bridges**, NEVER primary source code.
- Zero boilerplate: write clean, compact, executable ASL S-expressions. Architectural rationales and invariants live in the Knowledge Plane (`asl-mem` ADRs: `@adr:d-xxxx`, `@rule:l-xxxx`).

## 2. WebAssembly-First Default
- By default, all modules and workloads target **WebAssembly** (`wasm32-wasip1` and pure in-memory WASI preview1).
- Execution is sub-millisecond (<0.04ms), zero-cold-start, and sandboxed with zero host filesystem leaks.

## 3. Polyglot Native & Rust Ecosystem Integration
- When external ecosystems (e.g., Rust crates, C systems libraries, high-performance SIMD/GPU) are required:
  1. Author the business logic, orchestration, and types in **AgentScript (`.asl`)**.
  2. Transpile and compile via the native pipeline:
     ```bash
     asl build <module.asl> --target rust -o dist/native_bin
     ```
  3. Keep foreign syscalls and host bindings strictly isolated behind abstract capability ports (`asl-bridge`).

## 4. Native Toolchain Verification
Always use the built-in `asl` toolchain for execution and code intelligence:
- `asl run <file.asl>`: Evaluates in sandboxed Wasm/native isolate.
- `asl test <file.asl>`: Runs native test suites.
- `asl lint <file.asl>`: Enforces quality, size ceiling (150–500 lines), and anti-fragmentation rules.
- `asl graph --callers <symbol>`: Finds callers across all packages.
- `asl graph --impact <symbol>`: Traces transitive change impact radius.
- `asl registry <pkg>`: Inspects packages across npm, PyPI, crates.io, Go, and ASL.
- `asl gate`: Runs full pre-commit verification chain.
