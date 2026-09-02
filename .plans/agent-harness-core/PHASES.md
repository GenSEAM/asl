# Unified Agent Core, Pluggable Shells & Plugin Architecture (`asl-agent-harness-core-v1`)

> **Goal**: Establish the unopinionated, modular AgentScript Agent Architecture: a single unified Agent Core (`asl-agent-core`) with pluggable operational shells (In-Browser Extension, Dev CLI, Terminal TUI) and modular ecosystem plugins (optional PCP, Toolbelt, and Custom Harnesses) powered by **Meaningful Defaults**.

---

## 1. Architectural Principles

### 1. Unopinionated Core, Modular Ecosystem
- **AgentScript is the universal substrate**: The language core does NOT mandate a specific development methodology, constitution, or governance system.
- **PCP and Toolbelt as Optional Plugins**:
  - `asl-plugin-pcp`: Architecture Decision Records (ADR), constitution rules, and `@pcp:d-xxxx` verification.
  - `asl-plugin-toolbelt`: Specialized developer automation and code intelligence tools.
  - Communities can build their own harnesses, plugins, and workflows.

### 2. Meaningful Defaults Out of the Box
- `asl agent init` works instantly with zero configuration:
  - Default S-expression token-saving mode (-80% bloat).
  - Default sandboxed execution in `wasm32-wasip1`.
  - Default AST linter and safety boundaries.
- Power users and enterprise teams can customize every layer via plugins and configuration distributions.

### 3. One Agent Core, Pluggable Shells
```
               ┌─────────────────────────────────────────┐
               │    Unified Agent Core (asl-agent-core)  │
               │  - Context Extraction & Compaction      │
               │  - S-Expression Planning & AST Tools   │
               │  - Sandboxed Runner (WASI / MicroVM)    │
               │  - Multi-Model Router (Local & Cloud)   │
               └────────────────────┬────────────────────┘
                                    │
         ┌──────────────────────────┼──────────────────────────┐
         │                          │                          │
         ▼                          ▼                          ▼
 ┌───────────────┐          ┌───────────────┐          ┌───────────────┐
 │ Browser Shell │          │ Dev/CLI Shell │          │   TUI Shell   │
 │ (Extension)   │          │ (Coding Agent)│          │(Terminal UI)  │
 │ - Render Check│          │ - Git & Files │          │ - Interactive │
 │ - DOM & Visual│          │ - Testing     │          │   Pair-Prog   │
 │ - WebGPU SLM  │          │ - Diff Checks │          │ - In-terminal │
 └───────────────┘          └───────────────┘          └───────────────┘
```

---

## 2. Phased Roadmap

### Phase 1: Unified Agent Core (`packages/asl-agent-core`)
- Extract common agent loop logic from existing experiments into a standalone, pure ASL/WASI package:
  - Structured prompt compiler & ASN frame generator.
  - Capability negotiator & tool registry.
  - In-memory event bus & message framing.

### Phase 2: Meaningful Defaults & Plugin Lifecycle (`asl plugin`)
- Define the plugin interface:
  - Hooks: `on_init`, `on_tool_call`, `on_context_compile`, `on_verify`.
- Implement `asl-plugin-pcp` as an external optional package:
  - Translates `@tag :arch "..."` into Project Constitution checks without touching core compiler logic.

### Phase 3: In-Browser Companion Shell (`packages/asl-browser-plugin`)
- Mounts `asl-agent-core` into Chrome / Firefox extension runtime.
- Exposes DOM render-status, layout metrics, and WebGPU local SLM integration.

### Phase 4: Dev CLI & Coding Shell (`asl dev`)
- Mounts `asl-agent-core` for local repository engineering tasks:
  - Native differential test running, file edits under ownership fences, and gate verification.

### Phase 5: Terminal User Interface (TUI) Shell (`asl tui`)
- Interactive, keyboard-driven terminal dashboard written in AgentScript / native TUI:
  - Live token counter & prompt budget meter.
  - Streaming tool execution logs.
  - Multi-agent swarm topology graph right in your terminal.
