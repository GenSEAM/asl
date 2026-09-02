# Roadmap & Implementation Plan: Multi-Target Serializer/Deserializer SDKs (`asl-universal-codec-v1`)

**Goal**: Establish AgentScript as the premier compact data serialization format (-80% tokens vs JSON/YAML) by compiling `packages/asl-codec` into official, zero-dependency client SDKs across TypeScript, Python, Rust, Go, and WebAssembly directly from a single canonical ASL source (@pcp:d-bda8).

## Status: PLANNED (Scheduled for execution alongside `asl-agent-efficiency-v1`)

---

### Phase 1: Core S-Expression Serializer/Deserializer in Pure ASL (`packages/asl-codec`)
- [ ] Implement robust bidirectional S-expression parser/serializer in `packages/asl-codec/src/core/codec.asl`.
- [ ] Support algebraic schema serialization: numbers, booleans, strings, keywords (`:key`), vectors (`[...]`), and maps (`{...}`).
- [ ] Roundtrip fidelity assertions: verify lossless JSON/YAML <-> ASL conversions with 0 semantic loss.
- [ ] Token reduction verification gate: assert $\ge 75\%$ prompt token reduction against standard JSON across benchmark payloads.

### Phase 2: Multi-Target Compilation & Packaging Pipeline
- [ ] Leverage AgentScript's differential backend transpilers to compile `packages/asl-codec` into:
  - **TypeScript/JavaScript**: `@genseam/asl-codec` (npm package, ESM/CJS + types).
  - **Python**: `asl-codec` (PyPI package, wheels with zero dependencies).
  - **Rust**: `asl-codec` (crates.io crate, `no_std` compatible).
  - **Go**: `github.com/GenSEAM/asl-codec-go` (idiomatic Go module).
  - **WebAssembly**: standalone `asl-codec.wasm` with JS/WASI bindings.
- [ ] Differential equivalence verification: run identical test suites across all 5 generated SDKs using `differential.py`.

### Phase 3: Adoption Tooling & CLI Transcoding
- [ ] CLI command: `asl transcode --to-json <data.asl>` and `asl transcode --from-json <data.json>`.
- [ ] Fast streaming bridge for AI agent tool harnesses (convert tool call arguments to ASL on the fly).
- [ ] Documentation, benchmarks, and interactive web playground demo showing live JSON/YAML -> ASL token savings.
