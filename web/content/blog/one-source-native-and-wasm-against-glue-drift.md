# One Source for Native and WebAssembly Targets: The Case Against Multi-Language Glue Drift
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
                                  │   Pure AgentSlang     │
                                  │   Algorithm & Models   │
                                  └───────────┬────────────┘
                                              │
                    ┌─────────────────────────┴─────────────────────────┐
                    │                                                   │
                    ▼                                                   ▼
         ┌─────────────────────┐                             ┌─────────────────────┐
         │ Native (LLVM IR)    │                             │ JavaScript (exp.)   │
         └─────────────────────┘                             └─────────────────────┘
                    │                                                   │
                    └─────────────────────────┬─────────────────────────┘
                                              │
                    ┌─────────────────────────┴─────────────────────────┐
                    ▼                                                   ▼
         ┌─────────────────────┐                             ┌─────────────────────┐
         │ Python (prototype)  │                             │ WebAssembly module  │
         └─────────────────────┘                             └─────────────────────┘
```

---

## 2. One Source, Many Targets: Where It Stands

AgentSlang (ASL) is designed to be the shared semantic layer. Instead of writing bindings and manual translations, developers and agents write core logic once:

```agentslang
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

`asl test` on this module reports 2 assertions executed, 2 passed.

The language already fixes the edge cases that cause drift, instead of inheriting them from a host language: integer `/` and `mod` floor (`(/ -7 2)` is `-4`, `(mod -7 3)` is `2`), Int64 overflow and division by zero trap (`ERR_INT_OVERFLOW`, `ERR_DIV_ZERO`) rather than wrap, and an Int never mixes with a Float without an explicit conversion (`(+ 1 2.0)` is rejected with `ERR_TYPE_MISMATCH`). Each of those answers was checked with `asl eval`.

What runs today:
* **The `asl` CLI.** `asl check`, `asl test` and `asl run` check and run ASL programs directly. This is the reference run that other targets are compared against.
* **LLVM IR, native and WebAssembly.** The `asl-target-llvm` package lowers linked ASL programs to LLVM IR, for native code and for `wasm32-unknown-unknown`, with its own allocator and garbage collector. On wasm32 the module imports four functions (`asl.write`, `asl.exit`, `asl.nowNs`, `asl.trap`), and the only host builtin a program can call is `print`; clocks, files, environment and sockets are rejected with `ERR_CAPABILITY_ABSENT`. This website is an ASL program compiled that way and run in your browser as `site.wasm`. The compiler is written in ASL and compiles itself through LLVM IR; that self-compile is gated on macOS only, and the bootstrap seed exists for `arm64-apple-darwin` only.
* **SQL.** The `asl-sql` package builds queries and schema definitions as SQL text for PostgreSQL, SQLite, MySQL and ClickHouse; its four suites pass and check the emitted text.

What we are building:
* **Source-level lowerings.** JavaScript is experimental, Python and Go are prototypes, and the WebAssembly text emitter (`asl-target-wat`) handles only arithmetic. There is no Rust, TypeScript or C target and no working Swift or shell target. The unit suites of the emitter packages under `asl/packages/asl-target-*` check the emitted text; none of them compiles and runs the output against the reference run's answers. `asl target` lists targets but does not compile to them.

---

## 3. The Differential Verification Gate: Proving Parity

Cross-compilation without verification is wishful thinking. Runtimes differ on integer overflow, rounding, string encoding and map key order.

The gate we intend to hold every target to is differential:

1. **Function-level:** run pure ASL functions on identical inputs in the reference run and on each target, and require equal results.
2. **Program-level:** run whole programs on each target and compare standard output, exit codes and file effects byte for byte.

A target joins the supported set only when it passes this gate against the reference run. None of the source-level targets has yet; that is the work ahead.

---

## 4. What This Would Mean for Engineering Teams

If one ASL source becomes the shared logic layer across a polyglot architecture:

* **Less glue code:** fewer hand-written FFI wrappers, SWIG layers and duplicated type definitions.
* **Fewer cross-stack bugs:** logic checked once in the reference run would behave the same when lowered to a target, because the gate says so. That holds only for targets that pass the gate, and none of the source-level ones does yet.
* **Refactoring once:** an agent can change an algorithm in one ASL module, verify it with the reference run, and regenerate every target.

Today one source runs through the `asl` CLI and, through LLVM, as native code and as WebAssembly in the browser. The source-level targets are the roadmap, and we will say so until each passes its gate.
