# Phase 4 — Wasm route, measured not assumed

Probed by the orchestrator on 2026-08-29 before planning. Every line below was executed and its
output read.

## Toolchain — no new installs required beyond one rustup target

| Fact | Result |
|---|---|
| `rustc` | 1.92.0, invoked as `rustup run stable rustc` (cargo shim broken, see AGENTS.md) |
| `wasm32-unknown-unknown` | already installed |
| `wasm32-wasip1` | **installed during this probe** (`rustup target add wasm32-wasip1`) |
| `node` | v22.22.3 |
| `node:wasi` | available (`ExperimentalWarning`, suppress with `--no-warnings`) |
| `wasmtime`, `wasm-tools` | **not installed**, and not needed for the route below |

## Route A — core module, no I/O

```
rustup run stable rustc --target wasm32-unknown-unknown --crate-type=cdylib -O -o out.wasm lib.rs
```
with `#[no_mangle] pub extern "C" fn ...`. Instantiated under plain `WebAssembly.instantiate` in
node; an `i64` export crosses as a JS `BigInt`. Verified: `add(2n, 40n) -> 42n`.
Artifact size unoptimised: **1.3 MB** for a one-function crate.

## Route B — whole program, I/O and exit status

```
rustup run stable rustc --target wasm32-wasip1 -O -o main.wasm main.rs
```
driven from node with `new WASI({version:'preview1', returnOnExit:true})` and `wasi.start(i)`.
Verified: `println!` reached stdout **and** `std::process::exit(3)` was returned as `3`.

This is exactly the pair `backend/differential.py` program mode already compares — stdout and exit
status — so the Wasm arm attaches to the existing gate rather than needing a new one.
Artifact size unoptimised: **1.8 MB**.

## Consequences for the Phase 3 plan

* Both differential modes (function and program) have a working Wasm equivalent today.
* Artifact size is the open question, not feasibility. 1.3-1.8 MB for trivial programs is the
  Rust std baseline; whether the project cares, and whether `panic=abort` / `opt-level=z` /
  `--crate-type=cdylib` with `#![no_std]` is worth pursuing, is a Phase 3 decision, not a blocker.
* The **component model / WIT** path (`wasm32-wasip2`, `cargo component`, `wit-bindgen`) is NOT
  probed and would need new tooling. The interface contract for Phase 3 v1 should therefore be
  designed so it can be emitted as a declared manifest first and lowered to WIT later, rather than
  making WIT the only representation.
* `c-c759` still holds: no rendering or system UI through this route.
