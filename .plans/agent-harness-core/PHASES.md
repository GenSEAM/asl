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

### Phase 2: Onion Middleware & Reorderable Plugin Engine (`asl plugin`, `packages/asl-harness`)
- **Extensible Onion Pipeline**:
  - Middleware hooks wrapping tool dispatch, prompt assembly, and inference:
    - `pre_tool_call`: validate or mutate arguments before execution.
    - `post_tool_call`: inspect, audit, or sanitize tool results before returning to context.
    - `filter_tool_call`: block unauthorized or dangerous actions.
    - `on_error`: auto-retry or fallback handlers.
  - **Topological Sorting & Priority Stacking**:
    - Numeric priority (`priority: I64`, e.g. 100 for auth, 500 for logging, 900 for final sanitize).
    - Relative dependency ordering (`before: ["plugin-id"]`, `after: ["plugin-id"]`).
    - Deterministic DAG topological resolution: third-party plugins can seamlessly slot between existing standard plugins without tight coupling.
- **Anti-Hallucination & Epistemic Grounding Plugin**:
  - Validates factual claims against exact source quotes `(source-id, quote, confidence)`.
  - Blocks hallucinations and flags contradictions before committing actions.
- **Implement `asl-plugin-pcp` as an external optional package**:
  - Translates `(:tag :arch "...")` nodes into Project Constitution checks without touching core
    compiler logic. (`:tag`, not `@tag` — `@` is not an identifier character and costs a second
    BPE token; see `.plans/decoupled-meta/PHASES.md` Phase 1.)

### Phase 2.5: CDP Browser Automation & Web Research Tooling (`packages/asl-harness/bridges/browser_cdp.py`)
- Immediate browser automation tools without waiting for full in-extension runtime:
  - Connects to existing Chrome debugging session (`--remote-debugging-port`) or launches headless Chromium via CDP.
  - Generates token-compact accessibility tree snapshots (`@eN` refs) via `asl-vdom` parser.
  - Purpose-built workflows: interacting with Gemini Chat, NotebookLM, deep research papers, ChatGPT web UI, extracting code and research specs.
  - Serves as the driver protocol that the in-browser extension (`packages/asl-browser-plugin`) will adopt natively.

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

### Phase 6: Headless CI Shell & Distributed Swarm Mesh (`asl ci`, `asl-agent-bus`)
- Deterministic batch CI runner with structured machine reports (JSON / JUnit).
- Integration with `@genseam/asl-agent-bus` Unix socket & SSE bus for multi-agent negotiation.

### Phase 7: Polyglot AST Code Intelligence & MCP Tool Export
- Tree-sitter AST symbol & call-graph analysis for Python, Rust, Go, C, JS/TS.
- Exposes ASL tools to external agents (Antigravity, Claude Code, Cursor) via MCP server and local socket proxy.

