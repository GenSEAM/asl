# Universal Cross-Platform Glue: One Source Across WebAssembly, Rust, Go, TypeScript & Python
*By GenSEAM | September 2026*

Modern enterprise architectures are polyglot by necessity. 

High-frequency services and data engines are built in **Rust** or **Go** for latency and raw compute efficiency. Web frontends and interactive tools run in **TypeScript** and modern reactive frameworks. Machine learning data pipelines, evaluation harnesses, and orchestration scripts live in **Python**. Edge compute and secure client sandboxes execute in **WebAssembly**.

This polyglot reality creates the **Multi-Ecosystem Glue Tax**: engineering organizations spend thousands of engineering hours writing, debugging, and maintaining fragile "glue code" to keep business logic synchronized across five different programming languages.

---

## 1. The Anatomy of Multi-Language Semantic Drift

When the same core data structures or business validation rules are re-implemented across different language ecosystems, subtle semantic discrepancies inevitably arise:

1. **Numeric Precision and Serialization Incompatibilities:** JavaScript's `Number` is an IEEE 754 double-precision float that loses integer precision beyond $2^{53} - 1$. Passing a 64-bit ID from a Rust microservice through a TypeScript API gateway frequently results in silent truncation.
2. **Nullable and Optional Representation Disparities:** Python treats `None` as a singleton object; Go uses typed `nil` pointers with zero-value structs; Rust enforces `Option<T>` with strict ownership semantics; TypeScript allows both `undefined` and `null`. Serializing nested optionals between these ecosystems regularly causes runtime panics.
3. **Validation and Parsing Inconsistencies:** A regular expression or string normalization rule that passes in Python 3.12 may behave differently in Go's `regexp` package (which uses RE2 and rejects backtracking) or JavaScript's V8 engine.

The standard industry attempt to solve this—Protocol Buffers, OpenAPI schemas, or JSON Schema generators—only standardizes data transfer formats. They do not standardize **executable logic**. When algorithms, business rules, or state machines need to run identically across ecosystems, teams are forced to rewrite the logic in each target language.

```text
                                  ┌────────────────────────┐
                                  │   Pure AgentScript     │
                                  │   Algorithm & Models   │
                                  └───────────┬────────────┘
                                              │
                    ┌─────────────────────────┼─────────────────────────┐
                    │                         │                         │
                    ▼                         ▼                         ▼
         ┌─────────────────────┐   ┌─────────────────────┐   ┌─────────────────────┐
         │  Native Rust Crate  │   │   Native Go Module  │   │  TypeScript Library │
         │  - Zero overhead    │   │  - Idiomatic structs│   │  - Strict TS types  │
         │  - High throughput  │   │  - Cloud microserv. │   │  - Web frontend/Node│
         └─────────────────────┘   └─────────────────────┘   └─────────────────────┘
                    │                         │                         │
                    └─────────────────────────┼─────────────────────────┘
                                              │
                    ┌─────────────────────────┴─────────────────────────┐
                    ▼                                                   ▼
         ┌─────────────────────┐                             ┌─────────────────────┐
         │  Python Extension   │                             │ WebAssembly Module  │
         │  - ML data pipelines│                             │ - In-browser / WASI │
         │  - Fast NumPy bridge│                             │ - Sandboxed edge    │
         └─────────────────────┘                             └─────────────────────┘
```

---

## 2. One Source, Six Deterministic Backends

AgentScript (ASL) was designed to act as the universal semantic substrate. Instead of writing custom bindings and manual translations, developers (and autonomous agents) author core logic in pure ASL:

```agentscript
(module math/vector
  :d "2D vector transformations and geometry"
  :x [Vec2 dot-product magnitude normalize])

(dfs Vec2
  (:f x F64 "X coordinate")
  (:f y F64 "Y coordinate"))

(df dot-product [(a Vec2) (b Vec2)] -> F64
  :d "Calculates the dot product of two vectors"
  (+ (* (.-x a) (.-x b)) (* (.-y a) (.-y b))))

(df magnitude [(v Vec2)] -> F64
  :d "Calculates Euclidean length"
  (sqrt (+ (* (.-x v) (.-x v)) (* (.-y v) (.-y v)))))

(df normalize [(v Vec2)] -> Vec2
  :d "Returns unit vector or zero vector if length is zero"
  (let [(m (magnitude v))]
    (if (= m 0.0)
      (Vec2 :x 0.0 :y 0.0)
      (Vec2 :x (/ (.-x v) m) :y (/ (.-y v) m)))))
```

From this single source file, the ASL compiler deterministically emits native code across priority targets:

* **To Rust (`backend/to_rust.py`):** Emits idiomatic, zero-allocation Rust structs with `#[derive(Clone, Debug, PartialEq)]` and native math functions.
* **To Go (`backend/to_go.py`):** Emits idiomatic Go structs, typed error returns, and packages compatible with standard `go build`.
* **To TypeScript (`backend/to_typescript.py`):** Emits strict TypeScript interfaces and ES module exports ready for browser and Node.js consumption.
* **To Python (`backend/to_python.py`):** Emits clean, typed Python dataclasses compatible with `mypy --strict`.
* **To WebAssembly (`wasm32-wasip1`):** Emits compact WebAssembly bytecode running in-browser or edge runtimes with sub-millisecond instantiation.
* **To Cross-Dialect SQL (`asl-sql`):** Parameterized queries and schema migrations compilable to Postgres, SQLite, MySQL, and Oracle.

---

## 3. The Differential Verification Gate: Proving Parity

Cross-compilation without rigorous verification is merely wishful thinking. Different runtimes handle edge cases differently: integer overflows, rounding halves, string encoding, and map key order.

AgentScript enforces portability through a mandatory **Differential Test Gate (`backend/differential.py`)**:

1. **Function-Level Differential Testing:** Takes pure ASL programs, executes identical test inputs across the Rust, Python, TypeScript, and Go runtimes, and asserts bit-for-bit return value equivalence.
2. **Program-Level I/O Differential Testing:** Compiles whole programs across native binaries and WebAssembly (`node:wasi`), capturing standard output, error codes, and filesystem mutations to guarantee byte-for-byte agreement.

If an arithmetic operation behaves differently in Python than in Rust or WebAssembly, the gate halts immediately. Portability is treated as a formal compiler invariant, not an aspiration.

---

## 4. Real-World Impact for Engineering Teams

By adopting AgentScript as the shared logic and protocol layer across polyglot architectures:

* **Zero Glue Code Overhead:** Teams no longer write hand-crafted C-FFI wrappers, SWIG layers, or redundant TypeScript types.
* **Elimination of Cross-Stack Bugs:** Logic tested and verified in an agent's browser playground behaves identically when deployed to a high-throughput Go microservice or Python data worker.
* **Accelerated Multi-Agent Refactoring:** An autonomous agent can refactor an algorithmic module once in ASL, run local WebAssembly verification in 0.04ms, and deploy the verified update across the entire polyglot infrastructure.

AgentScript transforms cross-platform development from an endless chore of manual translation into a unified, automated, and mathematically verified pipeline.
