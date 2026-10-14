# One Source Across Rust, TypeScript, Python & Wasm: The Case Against Multi-Language Glue Drift
*By GenSEAM | September 2026*

Modern architectures are polyglot by necessity.

Latency-critical services and data engines are built in **Rust**. Web frontends and interactive tools run in **TypeScript**. Machine learning pipelines, evaluation harnesses and orchestration scripts live in **Python**. Edge compute and client sandboxes execute in **WebAssembly**.

This creates the **Multi-Ecosystem Glue Tax**: teams spend real time writing, debugging and maintaining "glue code" that keeps business logic synchronized across languages.

---

## 1. The Anatomy of Multi-Language Semantic Drift

When the same data structures or validation rules are re-implemented in several ecosystems, small semantic differences appear:

1. **Numeric Precision and Serialization:** JavaScript's `Number` is an IEEE 754 double that loses integer precision beyond 2^53 - 1. A 64-bit ID passed from a Rust service through a TypeScript gateway can be silently truncated.
2. **Nullable and Optional Representation:** Python has `None`; Rust has `Option<T>`; TypeScript has both `undefined` and `null`. Nested optionals serialized between them are a steady source of runtime errors.
3. **Integer Division and Remainders:** `-7 / 2` floors to `-4` in Python and truncates to `-3` in Rust, C and JavaScript's `Math.trunc`; `-7 % 3` is `2` in Python and `-1` in the others. Logic ported by hand inherits whichever rule the porter's language uses.

Protocol Buffers, OpenAPI and JSON Schema standardize data transfer formats. They do not standardize **executable logic**. When algorithms, business rules or state machines need to run identically everywhere, teams rewrite them in each language.

```text
                                  ┌────────────────────────┐
                                  │   Pure AgentScript     │
                                  │   Algorithm & Models   │
                                  └───────────┬────────────┘
                                              │
                    ┌─────────────────────────┴─────────────────────────┐
                    │                                                   │
                    ▼                                                   ▼
         ┌─────────────────────┐                             ┌─────────────────────┐
         │     Rust source     │                             │   TypeScript / JS   │
         └─────────────────────┘                             └─────────────────────┘
                    │                                                   │
                    └─────────────────────────┬─────────────────────────┘
                                              │
                    ┌─────────────────────────┴─────────────────────────┐
                    ▼                                                   ▼
         ┌─────────────────────┐                             ┌─────────────────────┐
         │    Python source    │                             │ WebAssembly module  │
         └─────────────────────┘                             └─────────────────────┘
```

---

## 2. One Source, Many Targets: Where It Stands

AgentScript (ASL) is designed to be the shared semantic layer. Instead of writing bindings and manual translations, developers and agents write core logic once:

```agentscript
(module math/vector :x [Vec2 dotProduct scale runTests] :i [])

schema Vec2
  x: Float64
  y: Float64

fn dotProduct a: Vec2 b: Vec2 -> Float64
  (+ (* a.x b.x) (* a.y b.y))

fn scale v: Vec2 k: Float64 -> Vec2
  (Vec2 :x (* k v.x) :y (* k v.y))

fn runTests -> Bool
  (do
    (assert (= (dotProduct (Vec2 :x 1.0 :y 2.0) (Vec2 :x 3.0 :y 4.0)) 11.0) "dot")
    (assert (= (scale (Vec2 :x 1.0 :y 2.0) 2.0).y 4.0) "scale")
    true)
```

`asl-host test` on this module reports 2 assertions executed, 2 passed.

The language already fixes the edge cases that cause drift, instead of inheriting them from a host language: integer `/` and `mod` floor (`(/ -7 2)` is `-4`, `(mod -7 3)` is `2`), Int64 overflow and division by zero trap (`ERR_INT_OVERFLOW`, `ERR_DIV_ZERO`) rather than wrap, and an Int never mixes with a Float without an explicit conversion (`(+ 1 2.0)` is rejected with `ERR_TYPE_MISMATCH`). Each of those answers was checked with `asl-host eval` on the stage-0 host.

What runs today:
* **The reference host.** The stage-0 host is a C program that checks and runs ASL directly, and `asl-host build FILE -o OUT` embeds a program's modules, with the interpreter, into a standalone executable. On 2026-10-14, a hello-world built this way in a Linux x86_64 container was a 449,248-byte executable (not stripped).
* **LLVM IR, native and WebAssembly.** The `asl-target-llvm` package lowers linked ASL programs to LLVM IR, for native code and for `wasm32-unknown-unknown`, with its own allocator and garbage collector. On wasm32 the module imports four functions (`asl.write`, `asl.exit`, `asl.nowNs`, `asl.trap`), and the only host builtin a program can call is `print`; clocks, files, environment and sockets are rejected with `ERR_CAPABILITY_ABSENT`. This website is an ASL program compiled that way and run in your browser as `site.wasm`. A self-hosted native compiler, `asl1`, exists as an LLVM IR seed for `arm64-apple-darwin` only; self-hosting is in progress.
* **SQL.** The `asl-sql` package builds queries and schema definitions as SQL text for PostgreSQL, SQLite, MySQL and ClickHouse; its four suites pass on the host and check the emitted text.

What we are building:
* **Source-level lowerings** to Rust, Python, Go, C, Swift and TypeScript. Emitter packages exist under `asl/packages/asl-target-*`, and their unit suites pass on the host, but those suites check the emitted text; none of them compiles and runs the output against the host's answers. The TypeScript emitter is an AST-level prototype that fails on real multi-module programs, the WebAssembly text emitter (`asl-target-wat`) handles only arithmetic, and the C target's run-parity suite currently fails because its corpus is missing. `asl target` lists these targets but does not compile to them.

---

## 3. The Differential Verification Gate: Proving Parity

Cross-compilation without verification is wishful thinking. Runtimes differ on integer overflow, rounding, string encoding and map key order.

The gate we intend to hold every target to is differential:

1. **Function-level:** run pure ASL functions on identical inputs on the reference host and on each target, and require equal results.
2. **Program-level:** run whole programs on each target and compare standard output, exit codes and file effects byte for byte.

A target joins the supported set only when it passes this gate against the stage-0 host. None of the source-level targets has yet; that is the work ahead.

---

## 4. What This Would Mean for Engineering Teams

If one ASL source becomes the shared logic layer across a polyglot architecture:

* **Less glue code:** fewer hand-written FFI wrappers, SWIG layers and duplicated type definitions.
* **Fewer cross-stack bugs:** logic checked once on the reference host behaves the same when lowered to a Rust service or a Python worker, because the gate says so.
* **Refactoring once:** an agent can change an algorithm in one ASL module, verify it on the host, and regenerate every target.

Today one source runs on the reference host and, through LLVM, as native code and as WebAssembly in the browser. The source-level targets are the roadmap, and we will say so until each passes its gate.
