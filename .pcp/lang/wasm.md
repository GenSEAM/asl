# Lang / Wasm

This file groups d/c/r/l entries for the lang/wasm module.

### [d-f484] WebAssembly is the target the language is aimed at, and the glue it is for
- **Date**: 2026-08-29
- **Status**: Active
- **Cluster**: lang/wasm
- **Description**: One source, two exits, both kept: a portable bytecode module where portability is
  the point, or emission into a specific native language where a specialised implementation — a
  numeric kernel, a hand-tuned routine — pays for itself. The focus is the first. Its role is a
  typed glue layer between ecosystems
  that meet as compiled modules rather than as source: units written in different languages are
  composed through declared interface contracts, and the language supplies the checked, total layer
  over those contracts. Producing modules for that target is a first-class product goal, not a
  by-product of one backend.
- **Rationale**: The module surface is already private-by-default with an explicit export contract
  and a mandatory doc (d-f99b), which is the same shape an interface contract takes at a module
  boundary. Binding an ecosystem at that boundary therefore reuses a decision already made rather
  than adding a second, parallel notion of a module's public face. The safety argument is that a
  module is confined by the host embedding it and cannot reach anything it was not handed — a
  property of the execution substrate, and separate from the type-level guarantees the language
  itself provides.
- **Route, measured**: the first target costs no new code generation. The existing systems-language
  backend's output is already accepted for the portable target unchanged; every corpus fixture it
  covers produces a valid module. Direct code generation for the target is a distinct and far more
  expensive commitment — memory layout and a reclamation strategy for the recursive unions the
  language is built on — and is not started by this decision.
- **Costs accepted**: the ecosystem reached this way is not the ecosystem reached through host
  bindings (d-4b8c). Host binding buys an existing library corpus; module composition buys typed
  contracts to a set of modules that is comparatively small, and pulling a dynamic host language
  in through it means shipping that language's whole runtime. Both boundaries are now in scope,
  they answer different questions, and neither is a substitute for the other. Portability continues
  to hold for the pure core only — a module bound to one ecosystem's libraries stays with it.
- **Why Non-Obvious**: the target looks like a portability feature to be added at the end, once
  there is something to port. It is instead an interop model, and interop is a language-surface
  question: what a module declares, what crosses the boundary, and what a failure across it looks
  like. Deciding it late means deciding it twice.

### [c-c759] The rendering and system-UI half of the portability story does not exist yet
- **Date**: 2026-08-29
- **Status**: Active
- **Cluster**: lang/wasm
- **Description**: Composing compiled modules is standardised for computation. Reaching a GPU, a
  window, or a system UI through the same mechanism is not: the interface for it is a proposal,
  no host outside the browser implements one, and inside the browser a module reaches the graphics
  API only through the surrounding script host, not through the portable interface. Engines that
  might embed such a module expose no plugin contract for one.
- **Impact**: any plan that treats graphics or UI as another contract to be imported is planning
  against a capability that must first be built by hand, per host, and is therefore neither
  portable nor free. It belongs in the effectful edge that d-4b8c already declares non-portable.
- **Why Non-Obvious**: the computation side works so smoothly that the graphics side is assumed to
  work the same way, and the proposals are public and readable enough to be mistaken for shipped
  standards.

### [d-3c5f] The Wasm arm is the Rust backend compiled to wasm32-wasip1, run under node:wasi
- **Date**: 2026-08-30
- **Status**: Active
- **Cluster**: lang/wasm
- **Description**: The first Wasm target reuses the Rust backend's output unchanged: the same
  `ToRust` program is compiled to `wasm32-wasip1` and run under node's `WASI` preview1, attached as
  a third arm of `differential.py`'s program mode — stdout, stderr and exit status compared against
  the Python and native-Rust arms and against the declared values. The guest's root maps to the
  per-run directory the gate seeds, so relative file I/O lands on the same files the other arms see.
- **Rationale**: the route was measured (`.plans/phase-4/FEASIBILITY.md`) and needs no new tooling:
  `wasm32-wasip1` is one rustup target and `node:wasi` is in the already-present node. Direct code
  generation for the target — the memory-layout and reclamation commitment d-f484 declined to start
  — is still not started; this arm is Rust std on WASI, which is why it reaches stdout, files and
  exit status.
- **Costs accepted**: function-mode Wasm (calling an entry with typed args across the JS boundary,
  `i64` as `BigInt`) is not attached; program mode is the surface the acceptance criterion names.
  Artifact size is the Rust std baseline (~1.8 MB), not optimised.
- **Why Non-Obvious**: the arm looked like a new backend but is the existing backend plus one
  `--target`. What it bought instead of new code was an oracle: running the same Rust program on
  WASI exposed that `rt.rs`'s IoError mapping read `raw_os_error()` as Unix errno, which WASI
  numbers differently (c-7b9e) — a portability defect every previous gate was green through.

### [d-596e] Client-Side In-Browser Agentics: Local SLM Inference & Semantic DOM Compression
- **Date**: 2026-09-02
- **Status**: Draft
- **Cluster**: lang/wasm
- **Description**: Replaces brittle external browser scraping with an in-browser autonomous agent (`packages/asl-browser-plugin`). The agent executes inside the browser process using the AgentScript WASI runtime paired with local 0.5B instruct models via WebGPU for private, zero-latency context analysis. Live DOM trees and reactive component states are compressed into strongly-typed ASL S-expression frames (`(! dom/snapshot ...)`), eliminating 78% of raw HTML token bloat. A bi-directional A2A mesh link streams verified UI anomalies, state mutations, and accessibility trees directly to IDE orchestrators without conversational overhead.

### [d-29ef] WASI Capability-Based Directory Mounting & Zero-Token Pre-Compacted Execution
- **Date**: 2026-09-02
- **Status**: Final
- **Cluster**: lang/wasm
- **Description**: AI agents waste tens of thousands of prompt and generation tokens when performing repository analysis by writing ad-hoc scripts or ingesting raw multi-file search dumps. AgentScript's WASI runtime (`wasm32-wasip1`) leverages capability-based directory pre-opens (`asl run --mount <dir> <tool.wasm>`): (1) The sandbox securely mounts targeted workspace directories with fine-grained read/write capabilities while strictly isolating host filesystems, environment credentials, and raw network sockets; (2) Pre-compiled Wasm tooling (code search, AST graph extraction, semantic diffing) executes in-memory at near-native speed (<15ms vs multi-second container boot) and emits pre-compacted S-expression digests (<100 tokens); (3) In browser environments, the identical Wasm engine binds to the Origin Private File System (OPFS) or virtual memory filesystems, enabling zero-server repository exploration and linting inside client Web Workers.
