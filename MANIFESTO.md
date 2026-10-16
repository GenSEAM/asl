# ASL Language Technical Manifesto

> **"A language for models to write, for checkers to prove, and for engineers to govern."**

---

## 1. Why AgentSlang exists

Production languages were designed for human keyboards and eyes. Each has a trap for a model that writes left to right: invisible indentation, non-local lifetimes, silently missing properties, repeated error boilerplate. Agents spend their budget on the repair loops these cause, and their attention on syntax that carries no meaning.

**ASL removes that layer.** It is a language whose main author and reader is a language model, and whose syntax is chosen by measurement: tokens per idea and how often models generate it correctly. People work above it, on architecture, intent and evidence, with tools built for that.

---

## 2. Principles

### 1. Structure that cannot be misread
Forms are balanced trees. The written form mirrors the tree, so parse and print round-trip and a model never has to guess where a form ends.

### 2. Every choice is measured on models
A keyword, a marker or a naming scheme stays only while models write correct code better with it than without it. Builtins carry no effect marker because models wrote correct programs about twice as often without one; predicates keep `?` because models do better with it. When a measurement refutes a choice, the choice goes.

### 3. Whole words, no ceremony
camelCase whole words the model already knows, the module carries the domain, and among names that carry the meaning the measured cheapest wins.

### 4. No silent failure
No null and no exceptions. Optional values are `(some v)` / `(none)`, failures `(ok v)` / `(err e)`, matched exhaustively. Side effects are visible to the checker, so a refactor cannot add one unseen.

### 5. One notation for code and messages
Code, contracts, tool payloads, wire messages and ledgers are all ASN, so nothing is translated between them.

### 6. Fast where it matters
Native code with reference counting and no tracing collector as the goal, buffers and data structures close to C, and a sandboxed WebAssembly build that can only do what its host hands it.

---

## 3. One language that glues the others

ASL is meant to describe and generate a whole system from one place:

- **Embedded languages.** SQL, JavaScript, HTML, CSS and others live inside ASL as checked blocks, not opaque strings.
- **Self-compiling.** The compiler is written in ASL and compiles itself to native code and WebAssembly.
- **Transpiling.** Source-to-source targets produce other languages where an ecosystem needs source, with the same semantics checked by differential tests.
- **Foreign calls.** A foreign-function interface makes any library or binary usable from ASL without a rewrite.

---

## 4. Tools for agents and for engineers

The language comes with a toolset in the same notation:

- **For agents:** read by symbol and slice, batch independent operations into one call, stage edits in memory and flush them as a transaction, get typed receipts that say what to do next, and learn the language from a small index in one request.
- **For engineers:** lenses over the code base (topology, coupling, complexity, effect boundaries, intent coverage), audits whose every claim can be rerun, and gates that count only after they have failed on a seeded defect.

---

## 5. Evidence

Every figure the project publishes is a row in `bench/publishedClaims.asn` with its status and what stands behind it. An unmeasured figure is not cited as a result.

*ASL is dual-licensed under MIT or Apache-2.0.*
