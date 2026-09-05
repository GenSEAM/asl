# ASL Universal Runtime & Ecosystem Compatibility Matrix

### Cross-Platform WebAssembly, JavaScript Engines, and Python Accelerators

> **Unverified figures.** Every performance number on this page is a projection or a
> vendor claim, not a measurement this repository can reproduce. `DESIGN.md` §5 requires a
> published number to be traceable to a gate; these are not, and are kept only as an order
> of magnitude to design against. `ROADMAP.md` §2 lists the figures that do have a gate,
> and `bench/token_frames.py` is the shape a claim has to take to earn a place here.

> **"Write once in ASL. Execute seamlessly across Browser, Node, Bun, Deno, Edge Workers, and WebAssembly (wasm32-wasip1)."**

---

## 1. WebAssembly Runtimes & Mobile Strategy

Running native code on mobile devices (especially iOS) is strictly constrained by App Store policies:
* **The iOS Challenge:** Apple forbids dynamic JIT compilation (`mprotect` / executable memory allocations) for non-Apple web engines. Native JIT compilers get rejected from the App Store.
* **The ASL Solution:** ASL compiles to standard `wasm32-wasip1` binaries that run through lightweight, certified **WebAssembly interpreters**.

### WebAssembly Engine Tier List:

| Engine | Tier | Primary Use Case | iOS App Store Compliant? | Memory Footprint |
| :--- | :--- | :--- | :--- | :--- |
| **Wasm3** | **Mobile #1 (Interpreter)** | iOS, Android, Embedded C, Microcontrollers | **100% Compliant (Pure C Interpreter, No JIT)** | **< 64 KB** |
| **Browser Native (V8 / JSC / Gecko)** | **Web #1 (Client-Side)** | React, Vue, Svelte, Angular, Canvas, Web Workers | **100% Native** | **0 KB (Built into OS)** |
| **Wasmtime (Bytecode Alliance)** | **Server #1 (WASI Host)** | Cloud edge workers, Fastly Compute, Docker Wasm | Server / Edge only | ~12 MB |
| **Wasmer** | **Universal Plugin VM** | Desktop extensions, Figma/Notion-like plugin hosts | Desktop / Server | ~15 MB |

---

## 2. JavaScript & TypeScript Runtime Matrix

ASL emits pure, zero-dependency ES Modules (`.ts` / `.mjs`) with standard type definitions that work out of the box with all modern bundlers and runtimes:

```
                          ┌────────────────────────┐
                          │   ASL Core (.asl)      │
                          └───────────┬────────────┘
                                      │
        ┌─────────────────────────────┼─────────────────────────────┐
        ▼                             ▼                             ▼
   Node.js (v18+)                   Bun (v1.1+)                  Deno (v2.0+)
  (npm / pnpm / yarn)             (Ultra-fast ESM)            (Native TS / Web APIs)
```

* **Bundler Compatibility:**
  * **Vite & Rollup:** Direct tree-shaking via ES6 named exports (`import { renderBadge } from './generated/ui'`).
  * **esbuild & Webpack 5:** Full dead-code elimination (DCE) — unused schemas and functions are stripped automatically.

---

## 3. Python Reference Runtime

ASL provides a reference lowering into standard PEP 484 type-annotated Python for differential verification and host interop:

| Python Runtime | Compatibility | How ASL Integrates | Execution Role |
| :--- | :--- | :--- | :--- |
| **CPython (3.10 – 3.13)** | **100% Native** | Emits clean PEP 484 type-annotated standard Python | Reference verification baseline |
| **PyPy (JIT)** | **100% Compatible** | Fast JIT compilation of reference AST execution | High-speed alternative Python runner |

---

## 4. The Unified Pipeline: WebAssembly, TypeScript, and Edge

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           THE ASL GLUE ARCHITECTURE                         │
├─────────────────────────────────────────────────────────────────────────────┤
│ 1. Frontend (React / Svelte):   Consumes Wasm binary in-memory (<0.04ms)   │
│ 2. Mobile App (iOS / Android):  Runs Wasm3/WASI interpreter (App Store safe)│
│ 3. Edge / Cloud Services:       Executes wasm32-wasip1 on Cloudflare / Deno │
│ 4. Node / Bun Host Runtimes:    Direct zero-dependency TypeScript modules   │
│                                                                             │
│ ──> ZERO Protobuf/gRPC serialization drift across your entire tech stack    │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 5. AI Agent Platforms & Harness Portability Matrix

AgentScript is engineered as the universal, lightweight, agent-native execution substrate. It eliminates heavy Python virtual environments, multi-gigabyte Docker daemons, and fragile host dependencies, allowing autonomous agents to execute, verify, and reason over code instantaneously.

| Agent Platform / Harness | Integration Mechanism | Cold-Start Launch | Memory Ceiling (RSS) | Code Intelligence & Search | Sandboxed Execution | Verification Suite |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **Google Antigravity (AGY)** | Native Harness Skill (`skills/asl/SKILL.md`) | **< 0.04 ms** (Wasm) | **<= 24 MB** | Native TokenSave + AST Search | In-Memory Jailed WASI | `asl gate` (19 gates) |
| **Claude Code** | Custom Subcommands & Slash Tools | **< 100 ms** (Host CLI) | **<= 24 MB** | `asl context` Sub-Symbol Graph | Directory Traversal Guard | `asl test packages` |
| **OpenAI / Codex Swarm** | Function Calling & System Prompts | **< 0.04 ms** (Wasm) | **<= 16 MB** | Deterministic S-Expr AST | Wasm preview1 isolated memory | Pure ASL self-checker |
| **Factory Droid** | Shell Plugin & Autonomous Sandbox | **< 100 ms** (Host CLI) | **<= 24 MB** | `asl search` (AST-Grep) | Zero-prompt capability jail | `asl gate` |
| **OpenCode** | Open Agent Runner & CLI Toolchain | **< 100 ms** (Host CLI) | **<= 24 MB** | Built-in symbol resolver | In-memory stream reducer (`asl-sh`) | Full differential gate |
| **Cursor / Windsurf / IDEs** | stdio LSP 3.17 (`asl lsp`) + MCP | **< 50 ms** (JSON-RPC) | **<= 20 MB** | Real-time hover docs & AST jump | Virtual Projection (`asl view`) | Instant linter |

---

## 6. Editorial Taxonomy & Blog Category Matrix

To capture the architectural solutions developed across the ASL ecosystem, the technical writing and research publications are organized into the following core categories:

| Category | Core Subject & Theses | Planned / Published Essays |
| :--- | :--- | :--- |
| **Agent Platforms & Portability** | Lightweight, zero-server agent execution across heterogeneous harnesses (AGY, Claude Code, Codex, Factory Droid, OpenCode). Eliminating Python/Docker baggage in agent swarms. | *Universal Portability for Autonomous Agents: Running Pure ASL Across Modern Agent Runtimes* |
| **Dual-Plane Code & Architecture Records** | Complete separation of executable source code from architectural intent, requirements, invariants, and technical debt. Deprecating in-code comment bloat in favor of unified `@adr:`, `@rule:`, `@debt:` records in `asl-mem`. | *The Death of In-Code Comments: Anchoring ADRs and Invariants in External Agent Memory* |
| **Compiler-Native Code Intelligence** | Embedding AST-Grep structural queries (`asl search`) and TokenSave sub-symbol graphs (`asl context`) directly into the `asl` binary for sub-millisecond, token-efficient agent navigation. | *Compiler-Native Code Intelligence: Why Agent Languages Must Self-Host Their Semantic Graphs* |
| **Memory & Vector Systems** | Sub-millisecond in-memory vector recall and Git-native memory matrices (`asl-mem`), eliminating cloud vector DB latency. | *Sub-Millisecond Vector Recall & Git-Native Memory Matrices for Autonomous Agents* (Essay 13) |
| **Relational Data & SQL** | Eliminating SQL hallucinations and injection vulnerabilities via homoiconic relational S-expressions lowering to Postgres, SQLite, MySQL, and Oracle. | *Cross-Dialect SQL Without Hallucinations* (Essay 12) |
| **Browser Technologies** | Zero-server in-browser development via WebAssembly, OPFS, and in-memory WASI with tiered local SLMs. | *Zero-Server In-Browser Agent Runtimes* (Essay 11) |
| **Safety & Grounding** | Compiler-enforced lexical closure audits, deterministic citation verification, and hardware path jailing. | *The Epistemic Grounding Firewall* (Essay 10) |
| **Cross-Platform Runtimes** | Deterministic multi-target lowering across WebAssembly, Rust, TypeScript, and Python without semantic drift. | *Universal Cross-Platform Glue* (Essay 09) |
| **Context Architecture & Token Economy** | Eliminating context rot and structural syntax overhead; achieving 57%–65% token savings over JSON. | *Token Economy and Structural Compression* (Essays 02, 05) |

