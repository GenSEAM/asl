<div align="center">

<img src="assets/logo.svg" alt="AgentScript Chameleon Logo" width="100" height="100" />

# ⚡ AgentScript (ASL)
### *Stop forcing LLMs to write Python & parse bloated JSON.*

[![Website](https://img.shields.io/badge/website-aslang.dev-9333ea.svg)](https://aslang.dev)
[![Token Savings](https://img.shields.io/badge/tokens--80%25%20bloat-4ade80.svg)](https://aslang.dev)
[![Syntax Errors](https://img.shields.io/badge/syntax%20retries-0-emerald.svg)](https://aslang.dev)
[![LLM Context](https://img.shields.io/badge/LLM-llms.txt-blue.svg)](https://aslang.dev/llms.txt)
[![Differential Targets](https://img.shields.io/badge/compiles%20to-Wasm%20%7C%20Rust%20%7C%20TS%20%7C%20Go%20%7C%20Py%20%7C%20SQL-purple.svg)](https://aslang.dev/ecosystem)
[![License: MIT](https://img.shields.io/badge/License-MIT-gray.svg)](LICENSE)

**AgentScript** is the world's first programming language and structured wire substrate engineered from first principles for **Autonomous AI Agents, Swarms, and LLM Tooling**.

[Explore Website](https://aslang.dev) · [Interactive Playground](https://aslang.dev/playground) · [LLM Spec (llms.txt)](https://aslang.dev/llms.txt) · [Architecture Roadmaps](https://aslang.dev/roadmap)

</div>

---

## 🤯 Why are we still forcing AI models to write 1990s human code?

Every major programming language was designed for human typists sitting at keyboards:
- **Python / YAML**: Fragile whitespace. One hallucinated space indentation throws a fatal `TabError` that burns 3 recursive repair turns.
- **JSON / Tool-Calling**: Syntactic bloat. Repetitive `"keys":`, quotes, colons, and commas waste **up to 80% of prompt token budgets** before the model even starts reasoning.
- **Docker / Containers**: Heavy cold-starts. Spinning up a container just to run a math check takes seconds and megabytes of memory.

**AgentScript solves this at the language substrate layer:**
- 🛡️ **Balanced LL(1) Parentheses**: Whitespace is irrelevant. Parentheses balance deterministically in a single pass. **0 syntax repair loops.**
- 📉 **-80% Token Reduction**: Clean S-expression nano projections strip syntactic clutter. No quotes around keys, no commas, no braces.
- ⚡ **0.038ms In-Memory MicroVM**: Sandboxed `wasm32-wasip1` runtime with strict capability-jailed I/O and zero host directory traversal.
- 🎯 **Mathematical Differential Equivalence**: One canonical `.asl` AST compiles with proven cross-target equivalence to **WebAssembly, Rust, TypeScript, Go, Python, and SQL**.

---

## 🪜 The Zero-Friction Gradual Adoption Funnel

You don't need to rewrite your entire project to reap the benefits. Adopt AgentScript at whichever layer fits your workflow:

```text
┌─────────────────────────────────────────────────────────────────────────┐
│ 1. COMPACT AGENT DATA FORMAT (-80% Prompt Tokens)                       │
│    Use it purely as a token-saving alternative to JSON/YAML for LLMs.   │
│    Zero-dependency SDKs for Python, TypeScript, Rust, Go, and Wasm.     │
└────────────────────────────────────┬────────────────────────────────────┘
                                     │
                                     ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ 2. AGENT-TO-AGENT WIRE PROTOCOL (0.04ms Swarm Mesh)                     │
│    Coordinate multi-agent swarms with typed (loom:handoff ...) frames.  │
│    Eliminates natural-language chatter and guarantees zero context leak.│
└────────────────────────────────────┬────────────────────────────────────┘
                                     │
                                     ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ 3. AGENTIC TOOLING SUBSTRATE (Sandboxed Subprocesses & DOM)             │
│    Safely run structured shell pipelines (asl-sh) and compress DOM     │
│    trees by 78% (asl-vdom) without path leaks or shell injection.       │
└────────────────────────────────────┬────────────────────────────────────┘
                                     │
                                     ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ 4. FULL AGENTSCRIPT CORE LANGUAGE                                       │
│    Write verified autonomous logic that compiles deterministically      │
│    into Wasm, Rust, TypeScript, Go, Python, and SQL.                    │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## 🥊 The Face-Off: JSON vs TOON vs AgentScript

Here is what happens when an AI agent issues a structured command or task handoff:

### The Old Way: Verbose JSON (42 tokens, fragile quotes)
```json
{
  "action": "execute_command",
  "payload": {
    "binary": "git",
    "arguments": ["status", "--short"],
    "working_dir": "/app",
    "timeout_ms": 5000
  }
}
```

### The Intermediate Way: TOON (Tabular YAML/CSV, ~25 tokens, whitespace-sensitive)
```yaml
action: execute_command
payload: [binary, working_dir, timeout_ms]
  git, /app, 5000
arguments: [status, --short]
```

### The Native Agent Way: AgentScript Nano (11 tokens, -73.8% savings, LL(1) verified)
```lisp
(! cmd :bin "git" :args ["status" "--short"] :cwd "/app" :timeout 5000)
```
*Or positional zero-key form (9 tokens, **-78.6% tokens**):*
```lisp
(! cmd "git" ["status" "--short"] "/app" 5000)
```

---

## 🚀 Quickstart

### 1. Install Universal CLI Toolchain
```bash
# macOS / Linux zero-dependency install
curl -fsSL https://aslang.dev/install.sh | bash

# Verify CLI installation
asl --version
```

### 2. Scaffold and Run in 10 Seconds
```bash
# Initialize a new AgentScript project
asl init my-agent

# Run single-pass static verification
asl check

# Test in-memory with sub-millisecond Wasm runner
asl test

# Transpile verified source to any host target
asl build --target wasm -o dist/agent.wasm
asl build --target rust -o dist/agent.rs
asl build --target ts   -o dist/agent.ts
asl build --target go   -o dist/agent.go
asl build --target py   -o dist/agent.py
```

### 3. Native Progressive Slicing & Compaction
```bash
# Extract targeted AST subtrees without heavy jq/yq
asl slice packages/asl-sh/asl.json .dependencies

# Proxy noisy terminal/test commands (-80% terminal log bloat)
asl filter npm test
```

---

## 📦 Modular GenSEAM Ecosystem

| Package | Role | Description |
| :--- | :--- | :--- |
| **`packages/asl-sh`** | **[Admin Toolkit]** | Structured subprocess pipelines, stream redirection, and process supervision |
| **`packages/asl-skyloom`** | **[A2A Swarm Protocol]** | Sub-millisecond in-memory mesh coordination & context snapshots |
| **`packages/asl-vdom`** | **[UI & DOM Compactor]** | Compresses raw HTML/DOM into intent-first S-expressions (-78% tokens) |
| **`packages/asl-mem`** | **[Vector Memory Matrix]** | Zero-server in-memory vector store running in 64KB Wasm (0.038ms recall) |
| **`packages/asl-codec`** | **[Universal Codec]** | Multi-target serialization SDKs across TS, Python, Rust, Go, and Wasm |
| **`packages/asl-lint`** | **[Quality Doctor]** | Architectural AST linting, structural clone detection, and autonomous `$ asl heal` |

---

## 🤖 LLM & Agent Readability (`llms.txt`)

If you are an AI coding assistant (Cursor, Claude Code, Antigravity, Cline, Windsurf, or ChatGPT), read our machine-optimized specifications:
- Concise Core Spec: [`https://aslang.dev/llms.txt`](https://aslang.dev/llms.txt)
- Full Architecture Spec: [`https://aslang.dev/llms-full.txt`](https://aslang.dev/llms-full.txt)

---

## 📜 License

AgentScript is open-source software licensed under the [MIT License](LICENSE). Built with precision by the **GenSEAM** team.
