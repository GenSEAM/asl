# Gap Audit: Embedded Hardware & Arduino Frontier

**Verdict**: `APPROVE-WITH-AMENDMENTS`
**Focus**: Microcontroller memory limits, Arduino `setup()`/`loop()` lifecycle contracts, and kernel `:k` FFI directives.

---

## 1. Gap Analysis (Completeness & Edge Cases)

| Target Area | Identified Gap / Risk | Architectural Remedy |
|---|---|---|
| **MCU Memory Model** | Microcontrollers (e.g. ATmega328P with 2KB SRAM) cannot support dynamic garbage collection or large heap frames. | In `:trg c-embedded`, avoid heap-allocating temporary values; lower record instances and primitive arrays to stack variables or static buffers. |
| **Lifecycle Entrypoints** | Generic C requires `int main()`, whereas Arduino toolchains mandate `void setup()` and `void loop()`. | Support both lifecycle styles via module annotation or top-level functions `setup` and `loop`. Codegen emits Arduino-conforming function headers. |
| **Kernel/FFI Directives** | Direct hardware control (GPIO registers, UART, PWM, delays) needs low-level access without host overhead. | Standardize hardware calls via the single-token kernel directive `:k`: `(:k pinMode [pin mode])`, `(:k digitalWrite [pin state])`, `(:k delay [ms])`. |
| **Identifier Hygiene** | ASL parser enforces strict kebab-case and rejects underscores `_` in module paths. | Strictly name all new files and tests using hyphens: `gpio.asl`, `serial.asl`, `c-codegen-test.asl`, `arduino-test.asl`. |

---

## 2. Consistency Analysis (Invariants & Protocols)

* **Invariant: Single-Token Directives**:
  - Direct hardware access uses `:k` (1 BPE token).
  - Target declaration uses `:trg c-embedded` or `:trg arduino` (1 BPE token prefix).
* **Invariant: Native Manifest Specification**:
  - `packages/asl-arduino/manifest.asn` declared in pure S-expression format conforming to the GenSEAM manifest specification.
* **Invariant: Gate Coverage**:
  - Every item in the roadmap has a standalone gate command verifiable in < 5 seconds without external hardware dependencies (using simulated hardware state registers).

---

## 3. Adequacy & Anti-Overengineering (Critic Filter)

* **Rejection of Heavy C++ Abstractions**:
  - Generating complex object hierarchies for Arduino is **REJECTED**.
  - Direct emission of clean, idiomatic ANSI C / Arduino `.ino` functions is minimal, human-readable, and compiles seamlessly under `gcc`, `clang`, and `arduino-cli`.
* **Zero New Dependencies**:
  - The C code generator integrates cleanly into the existing `packages/asl-codegen` pipeline without pulling in third-party transpiler libraries.

---

## 4. Prioritized Execution Phases

1. `Phase 1: embedded-c-codegen` — Core C emission in `packages/asl-codegen/src/emit-c.asl`.
2. `Phase 2: asl-arduino-package` — `@genseam/asl-arduino` package with GPIO, Serial, and Blink example.
3. `Phase 3: embedded-simulator-gate` — In-memory signal simulation test suite.
4. `Phase 4: editorial-embedded-topic` — Topic 34 in `editorial-matrix/CONTENT_ROADMAP_30_TOPICS.md`.
