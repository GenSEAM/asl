<div align="center">

<img src="assets/logo.svg" alt="AgentScript Chameleon Logo" width="100" height="100" />

# ⚡ AgentScript (ASL)
### *Stop forcing LLMs to write Python & parse bloated JSON.*

[![Website](https://img.shields.io/badge/website-aslang.dev-9333ea.svg)](https://aslang.dev)
[![Status](https://img.shields.io/badge/status-Beta%20(Feature--Complete)-blue.svg)](https://aslang.dev)
[![Token Savings](https://img.shields.io/badge/wire%20frame-64.7%25%20smaller%20than%20JSON-4ade80.svg)](bench/token_frames.py)
[![Syntax Errors](https://img.shields.io/badge/syntax%20retries-0-emerald.svg)](https://aslang.dev)
[![LLM Context](https://img.shields.io/badge/LLM-llms.txt-blue.svg)](https://aslang.dev/llms.txt)
[![Differential Targets](https://img.shields.io/badge/compiles%20to-Wasm%20%7C%20Rust%20%7C%20TS%20%7C%20Py-purple.svg)](https://aslang.dev/ecosystem)
[![License](https://img.shields.io/badge/license-MIT%20OR%20Apache--2.0-gray.svg)](LICENSE)

**AgentScript** is the world's first programming language and structured wire substrate engineered from first principles for **Autonomous AI Agents, Swarms, and LLM Tooling**.

[Explore Website](https://aslang.dev) · [Interactive Playground](https://aslang.dev/playground) · [LLM Spec (llms.txt)](https://aslang.dev/llms.txt) · [Architecture Roadmaps](https://aslang.dev/roadmap)

</div>

---

## 🤯 Why are we still forcing AI models to write 1990s human code?

Every major programming language was designed for human typists sitting at keyboards:
- **Python / YAML**: Fragile whitespace. One hallucinated space indentation throws a fatal `TabError` that burns 3 recursive repair turns.
- **JSON / Tool-Calling**: Syntactic bloat. Repeated `"keys":`, quotes, colons and commas are
  paid for on every object in every array, before the model starts reasoning.
- **Docker / Containers**: Heavy cold-starts. Spinning up a container just to run a math check takes seconds and megabytes of memory.

**AgentScript solves this at the language substrate layer:**
- 🛡️ **Balanced Delimiters**: whitespace carries no meaning, so there is no indentation to get
  wrong and a malformed program is caught by counting rather than by running it.
- 📉 **Smaller On The Wire**: no quotes around keys, no commas, no braces. On the worked example
  below a command frame is **64.7% smaller** than its JSON form, counted by
  `bench/token_frames.py` and pinned by a lock file.
- ⚡ **In-Memory MicroVM**: sandboxed `wasm32-wasip1` runtime with capability-jailed I/O and no
  host directory traversal.
- 🎯 **Differential Equivalence, Enforced**: one `.asl` source compiles to **WebAssembly, Rust,
  TypeScript, and Python**, and a gate runs every corpus program on all of them plus a
  reference interpreter and fails on any disagreement in value, stdout or exit status.

---

## 🪜 The Zero-Friction Gradual Adoption Funnel

You don't need to rewrite your entire project to reap the benefits. Adopt AgentScript at whichever layer fits your workflow:

```text
┌─────────────────────────────────────────────────────────────────────────┐
│ 1. COMPACT AGENT DATA FORMAT (57%–65% Token Reduction)                  │
│    Use it purely as a token-saving alternative to JSON/YAML for LLMs.   │
│    Zero-dependency SDKs for Python, TypeScript, Rust, and Wasm.         │
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
│    into Wasm, Rust, TypeScript, and Python.                             │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## 🥊 The Face-Off: JSON vs AgentScript

Here is what happens when an AI agent issues a structured command or task handoff:

### The Old Way: Verbose JSON
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

### The Native Agent Way: AgentScript (ASL)
Positional zero-key form — delimiter-balanced, zero syntactic overhead:
```agp
(! cmd "git" ["status" "--short"] "/app" 5000)
```

| Frame | `cl100k_base` tokens |
|---|---|
| JSON | 51 |
| AgentScript (ASL) | **18** |

The positional frame is **64.7% smaller** than the JSON one. Re-run the count yourself with
`bench/token_frames.py`; `--check` compares it against `bench/token_frames.lock` so the figure on
this page cannot drift away from the payloads above. This is one example rather than a benchmark —
the project's measured claims are the ones `ROADMAP.md` names beside the gate that produced each.

> **Where positional is not enough:** Positional zero-key notation is optimal when parameter order is fixed and fully specified. For sparse payloads with optional fields or default overrides where positional indexing fails (e.g. overriding only `:timeout-ms` without dummy placeholders for preceding parameters), AgentScript seamlessly supports self-documenting keyed pairs:
> ```agp
> (! cmd :bin "git" :timeout-ms 5000)
> ```
> *(27 tokens — still 47% smaller than JSON, with zero ambiguity).*

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
asl build --target py   -o dist/agent.py
```

### 3. Inspect and Project Without Rewriting Files
```bash
# Read a module as fully spelled-out ASL Verbose (for debugging and human reading, on screen only)
asl view src/main.asl

# Switch a file to ASL Verbose for debugging
asl transcode src/main.asl --to verbose

# Structural search over the AST rather than grep
asl search src/main.asl 'defun'
```

*Planned, not yet shipped:* `asl slice` (native `jq`/`yq` replacement) and `asl filter`
(terminal-output compactor) — see `.plans/universal-codec/PHASES.md`.

---

## 📦 Modular GenSEAM Ecosystem

### Production & Stable Core Toolchain (Beta)
| Package | Role | Status | Description |
| :--- | :--- | :---: | :--- |
| **`packages/asl-sh`** | **[Shell & Pipelines]** | `Beta` | Structured subprocess pipelines, AST stream redirection, safe process supervision |
| **`packages/asl-codec`** | **[Universal Codec]** | `Beta` | Compact ASN S-expressions, multi-target transpilation (JSON, YAML, HTML, Shell) |
| **`packages/asl-vdom`** | **[UI & DOM Compactor]** | `Beta` | React/VDOM integration, compresses raw HTML/DOM into intent S-expressions (-78% tokens) |
| **`packages/asl-mem`** | **[Memory & Pointers]** | `Beta` | Perceptual pointer offloading and git-native vector memory in Wasm |
| **`packages/asl-gates`** | **[Quality & Gates]** | `Beta` | 7-tier verification gate runner and continuous architectural audit engine |
| **`packages/asl-lint`** | **[Quality Doctor]** | `Beta` | AST linting, structural clone detection, and delimiter balance checker |

### In Active Development / Research Roadmap (Alpha)
| Package | Domain | Status | Note |
| :--- | :--- | :---: | :--- |
| **`packages/asl-contracts`** | **[Smart Contracts]** | `Alpha (In Dev)` | Exploratory research for verifiable state transitions, SMT safety proofs & Stylus Wasm |
| **`packages/asl-quantum`** | **[Quantum Circuit]** | `Alpha (In Dev)` | Exploratory circuit AST synthesis and OpenQASM 3.0 compiler prototype |
| **`packages/voice`** | **[Voice Bridge]** | `Alpha (In Dev)` | Prototype 16kHz PCM audio bridge for real-time conversational agent streaming |

---

## 🤖 LLM & Agent Readability (`llms.txt`)

If you are an AI coding assistant (Cursor, Claude Code, Antigravity, Cline, Windsurf, or ChatGPT), read our machine-optimized specifications:
- Concise Core Spec: [`https://aslang.dev/llms.txt`](https://aslang.dev/llms.txt)
- Full Architecture Spec: [`https://aslang.dev/llms-full.txt`](https://aslang.dev/llms-full.txt)

---

## 📜 License

AgentScript is open-source software dual-licensed under [MIT](LICENSE-MIT) or [Apache-2.0](LICENSE-APACHE). Maintained as an open-source project under the **GenSEAM** GitHub namespace.
