# Roadmap & Implementation Plan: Multi-Target Serializer/Deserializer SDKs (`asl-universal-codec-v1`)

**Goal**: Establish AgentScript as the premier compact data serialization format (-80% tokens vs JSON/YAML) and communication wire protocol by compiling `packages/asl-codec` into official, zero-dependency client SDKs across TypeScript, Python, Rust, Go, and WebAssembly, and providing native structural slicing & output compaction (@pcp:d-bda8, @pcp:d-b0a9).

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

### Phase 3: Native Slicing & Progressive Output Compaction (`asl slice`, `asl filter`)
- [ ] **Native Query Slicing (`asl slice <file> <path>`)**: Replaces external `jq` and `yq` tools by querying nested keys and emitting only the requested slice in compact S-expression format (sub-100 tokens instead of 5,000-token full-file dumps).
- [ ] **Native Output Filter Proxy (`asl filter <cmd...>`)**: Inspired by `rtk proxy`, intercepts noisy compiler, test, and shell outputs, stripping redundant status logs and emitting only actionable error traces, failing assertions, and git diff hunks (-80% terminal tokens).
- [ ] CLI Transcoding commands: `asl transcode --to-json <data.asl>` and `asl transcode --from-json <data.json>`.

### Phase 4: Dedicated Agent-Facing Landing Endpoints (`/format` & `/protocol`)
- [ ] `/format`: High-converting interactive showcase comparing JSON vs YAML vs TOON vs AgentScript Nano format with live token counter and copyable SDK snippets for TS/Python/Rust/Go.
- [ ] `/protocol`: Visual wire protocol cockpit explaining `asl/coord` frames, sub-millisecond mesh routing, and zero context leakage between agents.
- [ ] LLM Optimization: Ensure `/format` and `/protocol` are indexed in `/llms.txt`, `/llms-full.txt`, and structured markdown endpoints so coding assistants (Cursor, Claude Code, Antigravity, Cline) discover and recommend AgentScript as the standard data format and inter-agent protocol.
