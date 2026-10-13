# One Source Across Rust, TypeScript, Python & Wasm: The Case Against Multi-Language Glue Drift
*By GenSEAM | September 2026*

Modern architectures are polyglot by necessity.

Latency-critical services and data engines are built in **Rust**. Web frontends and interactive tools run in **TypeScript**. Machine learning pipelines, evaluation harnesses and orchestration scripts live in **Python**. Edge compute and client sandboxes execute in **WebAssembly**.

This creates the **Multi-Ecosystem Glue Tax**: teams spend a large share of their time writing, debugging and maintaining "glue code" that keeps business logic synchronized across languages.

---

## 1. The Anatomy of Multi-Language Semantic Drift

When the same data structures or validation rules are re-implemented in several ecosystems, small semantic differences appear:

1. **Numeric Precision and Serialization:** JavaScript's `Number` is an IEEE 754 double that loses integer precision beyond $2^{53} - 1$. A 64-bit ID passed from a Rust service through a TypeScript gateway can be silently truncated.
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
(module math/vector :d "2D vector geometry" :x [Vec2 dotProduct scale] :i [])

schema Vec2
  x: Float64
  y: Float64

fn dotProduct a: Vec2 b: Vec2 -> Float64
  (+ (* (.-x a) (.-x b)) (* (.-y a) (.-y b)))

fn scale v: Vec2 k: Float64 -> Vec2
  {:x (* k (.-x v)) :y (* k (.-y v))}
```

The language already fixes the edge cases that cause drift, instead of inheriting them from a host language: on the stage-0 host, integer `/` and `mod` floor (`(/ -7 2)` is `-4`, `(mod -7 3)` is `2`), Int64 overflow and division by zero trap rather than wrap, and an Int never mixes with a Float without an explicit conversion.

What runs today:
* **One native binary.** The stage-0 host is a C program that runs ASL directly, and `asl-host build FILE -o OUT` embeds a program's modules into a standalone executable. On 2026-09-24, a hello-world program built this way was a 194,496-byte arm64 executable.
* **SQL.** The `asl-sql` package builds queries and schema definitions for PostgreSQL, SQLite, MySQL and ClickHouse.

What we are building:
* **Source-level lowerings** to Rust, Python, Go, C, Swift, WebAssembly text and shell. Emitter packages exist under `asl/packages/asl-target-*`, and the `(:target)` op lists them, but they are not a working pipeline yet: today `(:target)` answers `:compiled true` even for a file that does not exist, so its answer is not evidence of output. The C11 and LLVM emitters are marked absent in our capability ledger.
* **WebAssembly** as a first-class target, so the same source runs in a browser tab.

---

## 3. The Differential Verification Gate: Proving Parity

Cross-compilation without verification is wishful thinking. Runtimes differ on integer overflow, rounding, string encoding and map key order.

The gate we intend to hold every target to is differential:

1. **Function-level:** run pure ASL functions on identical inputs on the reference host and on each target, and require equal results.
2. **Program-level:** run whole programs on each target and compare standard output, exit codes and file effects byte for byte.

A target joins the supported set only when it passes this gate against the stage-0 host. None has yet; that is the work ahead.

---

## 4. What This Would Mean for Engineering Teams

If one ASL source becomes the shared logic layer across a polyglot architecture:

* **Less glue code:** fewer hand-written FFI wrappers, SWIG layers and duplicated type definitions.
* **Fewer cross-stack bugs:** logic checked once on the reference host behaves the same when lowered to a Rust service or a Python worker, because the gate says so.
* **Refactoring once:** an agent can change an algorithm in one ASL module, verify it on the host, and regenerate every target.

Today that promise holds for one target, the native host. The rest is the roadmap, and we will say so until each target passes its gate.
