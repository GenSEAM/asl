# AgentScript (ASL) v0.1.0 Release Notes

We are proud to announce the **v0.1.0 release of AgentScript (ASL)** — the first purpose-built S-expression programming language engineered from first principles for autonomous AI agents, multi-agent swarms, and high-performance WebAssembly edge execution.

## Highlights

### 1. Zero-Drift Multi-Target Compilation & Differential Verification
- **6 Cross-Platform Execution Targets:** Native Rust, Go, Python, TypeScript, Wasm (`wasm32-wasip1`), and a Reference Tree-Walking Interpreter.
- **Strict Differential Verification Gate:** 135 continuous test runs across all 6 targets with **0 disagreements** on return values, stdout, stderr, and exit codes.
- **100% Executed Vocabulary Coverage:** 107/107 standard library builtins evaluated and mutation-tested.

### 2. In-Browser WASI Preview1 Engine & Sandbox
- Pure TypeScript zero-native-dependency WASI snapshot_preview1 runner (`backend/ts/wasm_runner.ts`).
- Detached memory buffer safety, 8-byte ciovec unpacking, and direct export calling for zero-server in-browser execution.

### 3. High-Frequency Swarm Bus & EDDIE Orchestrator
- **Inter-Agent Bus Daemon (`@genseam/asl-agent-bus`):** Sub-millisecond IPC over Unix domain sockets and SSE mesh streams.
- **3-Layer EDDIE Architecture (`@genseam/asl-eddie`):** Layer 1 Fast Triage (<0.012ms), Layer 2 Consultative Ambiguity Resolver, and Layer 3 DAG Task Pool.

### 4. Real-Time Audio & Voice Stream Assistant
- **16kHz PCM Audio Stream Bridge (`@genseam/voice`):** Web Audio API streaming with sub-millisecond intent synthesis (<0.025ms).
- Live 60fps Canvas audio telemetry cockpit in the interactive technical showcase.

### 5. Developer Agent MCP Server
- Stdlib-only JSON-RPC 2.0 MCP server exposing `asex_check`, `asex_eval`, `asex_format`, `asex_compress_module`, and `asex_ast_query`.
- Reduces LLM context token consumption by 70–85% through AST signature compression.

## Verification & Metrics
- **Conformance:** 74 fixtures × 2 grammars (Lark Earley + Tree-sitter) clean.
- **Semantic Safety:** 13 §9 semantic rules enforced statically.
- **Monomorphism:** 400 concrete probes compiled through `rustc` and `py_compile`.
- **Unit & Integration Suite:** 280+ tests passing.

## Getting Started
```bash
# Start the developer MCP server
asl mcp

# Run code in Wasm target
asl run --target wasm program.asl
```
