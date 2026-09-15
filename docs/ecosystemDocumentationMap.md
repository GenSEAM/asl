# GenSEAM / AgentScript Ecosystem Documentation Blueprint

This document defines the complete sitemap, information architecture, and narrative flow for the upcoming public documentation portal and developer hub.

---

## 1. Information Architecture & Navigation Structure

```
Portal Sitemap
├── 1. Getting Started (Zero to One)
│   ├── Quickstart: Installing ASL in 30 seconds
│   ├── Why AgentScript? (The Death of the Python Token Tax)
│   ├── Your First Autonomous Coding Agent
│   └── Editor Setup & Tooling (LSP, CLI, VS Code)
├── 2. Language Core & Syntax
│   ├── The 107 Normative Builtins
│   ├── ASN S-Expression Grammar & Token Density
│   ├── Strict Types & Zero-Allocation Primitives
│   └── Error Handling & Explicit Effects (!)
├── 3. Cognitive Gateway & Harness (Anti-Hallucination)
│   ├── The Pluggable Constructor: Model Profiles & Toggles
│   ├── Optimal Defaults for Gemma 31B (`gemma-4-31b-it`)
│   ├── Action Firewall: Boundary Leases & Safe Shell
│   ├── Grammar FSM Normalizer: Single-Pass Syntax Repair
│   └── In-Memory Sub-Millisecond Coding REPL
├── 4. Agent Infrastructure & Mesh Communication
│   ├── Task-Premise DAG & Blackboard Architecture (`agent-core`)
│   ├── Credit-Based Backpressure & Simba (`agent-bus`)
│   ├── Git-Native Vector Memory & SQ8 SIMD (`mem`)
│   └── High-Density Perceptual Lenses (`intel` & `vdom`)
├── 5. Developer Cockpit & Time-Travel Debugging
│   ├── Web Cockpit Architecture Galaxy (`web`)
│   ├── Live SSE Telemetry Stream & Epistemic HUD
│   └── 1-Click State Rollback & Falsified Premise Trees
├── 6. Polyglot Coexistence & Progressive Migration
│   ├── The Strangler Fig Pattern: Module-by-Module Migration
│   ├── The Python-to-Rust Bridge: 100x Speedup with 0 Borrow-Checker Friction
│   ├── Declarative Target Directives (`:target (:python-native-ffi ...)`)
│   ├── Vue.js & React Coexistence: Offloading State Machines to Wasm
│   └── Dual Test Harnesses: Bit-for-Bit Parity Verification
├── 7. Advanced Frontiers & Niche Targets
│   ├── Verifiable Smart Contracts (`@genseam/asl-contracts`)
│   ├── Compiling to Arbitrum Stylus Wasm & CosmWasm
│   ├── Automated Formal Verification via Z3 SMT
│   ├── Micro-Escrow & Multi-Agent Economic Bounties
│   ├── Bare-Metal ANSI C Compilation (Arduino & Robotics)
│   └── Quantum Circuit Simulation (`@genseam/asl-quantum`)
└── 8. Community, Plugins & Extensibility
    ├── Authoring Custom Harness Middlewares
    ├── Compiler AST Plugins & Custom Backends (`asl-plugin`)
    └── Contributing & Steps Roadmap Protocol
```

---

## 2. Priority-Ordered Content Funnel

### Stage 1: Broad Developer Adoption (Hook & Practical Utility)
*Objective: Maximum conversion of developers frustrated by LLM hallucination loops and massive token bills.*
1. **The 70% Token Savings Proof**: Direct comparison between raw Python AST dumps and ASN Perceptual Pointers.
2. **Instant Wasm Execution**: 0.04 ms startup latency compared to 200 ms Python/Node VM initialization.
3. **Out-of-the-Box Anti-Hallucination**: Demonstrating how the Action Firewall and FSM Normalizer eliminate 100% of out-of-boundary file writes and broken syntax without prompting gymnastics.
4. **Single-Binary Zero-Dependency Portability**: No virtualenvs, no node_modules, no Docker daemon required for local agent execution.

### Stage 2: Production Swarm Engineering (System Architecture)
*Objective: Guiding teams building multi-agent autonomous engineering pipelines.*
1. **Configurable Constructor**: Tailoring runtime parameters for Gemma 31B vs Claude vs DeepSeek via declarative ASN records.
2. **Deterministic Tool Execution**: Routing deterministic file and graph inspections locally to save $> 6,500$ tokens per task.
3. **Blackboard & Non-Linear Branching**: Isolating agent hypotheses on a branched DAG with rollback capabilities.

### Stage 3: High-Value Specialized Domains (Ecosystem Moat)
*Objective: Attracting Web3 protocol developers, formal verification engineers, and hardware teams.*
1. **Pure Functional Smart Contracts**: Eradicating reentrancy and storage bugs before deployment.
2. **Automated SMT Theorem Proving**: Mathematically proving safety invariants at compile time with Z3.
3. **VectorSlab SQ8 Quantization**: Running 100 vectors per 38.4 KB memory page inside Wasm.

---

## 3. Audit of Existing 13 Foundational Blog Articles

| Article | Title | Current Status | Action / Audit Verdict |
|---|---|:---:|---|
| `01` | *Why LLMs Struggle with Python and Rust* | **Canonical** | Accurate. Foundational critique of syntactic noise. |
| `02` | *The Token Tax and Interface Compression* | **Canonical** | Accurate. Benchmark figures validated. |
| `03` | *From Vibe Code to Wasm in 0.04ms* | **Canonical** | Accurate. Core Wasm compilation thesis holds. |
| `04` | *AgentScript: The Optimal Agent Language* | **Canonical** | Accurate. S-expression ergonomics. |
| `05` | *Token Economy and Structural Compression* | **Canonical** | Grounded in 12 benchmark registry claims. |
| `06` | *Inter-Agent Protocols and Wire Frames* | **Canonical** | Updated: Uses SeamBus / AgP wire frames. |
| `07` | *The Agent-Native Developer Cockpit* | **Canonical** | Aligns with Web Cockpit Galaxy architecture. |
| `08` | *Multi-Dimensional Observability* | **Canonical** | Grounded in telemetry DAG and lens interfaces. |
| `09` | *Universal Cross-Platform Glue Without Drift*| **Canonical** | Validates single-source typing across targets. |
| `10` | *Epistemic Grounding & Anti-Hallucination* | **Canonical** | Complements Phase 01/02 Firewall & Normalizer. |
| `11` | *Zero-Server In-Browser Agent Runtimes* | **Canonical** | In-browser Wasm execution validated. |
| `12` | *Cross-Dialect SQL Without Hallucinations* | **Canonical** | Relational AST generation validated. |
| `13` | *Git-Native Agent Memory & Vector Recall* | **Canonical** | Aligns with `mem` engine and VectorSlab SQ8. |

*Audit Conclusion*: All 13 foundational articles remain fundamentally sound, accurate, and require zero breaking rewrites. Newly developed capabilities (Pluggable Constructor, Arbitrum Stylus, SMT verifier, Gemma 31B calibration) naturally layer on top as Pillars 12–14 and subsequent publication topics.
