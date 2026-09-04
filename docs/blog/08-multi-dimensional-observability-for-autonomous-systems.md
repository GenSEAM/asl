# Multi-Dimensional Observability: How to Govern Autonomous Swarms Without Reading Raw Logs
*By the ASL Systems & Observability Group*

The standard failure mode of scaling autonomous coding swarms is the **Observability Inversion Trap**.

When humans debug applications, they read line-by-line terminal logs, scan stack traces, and inspect local variables. When teams deploy multi-agent swarms, they naturally replicate this pattern: they capture every subagent's `stdout`, stream JSON tool invocations into an external dashboard, and instruct a coordinator agent to "read the logs and diagnose the problem."

Within five execution cycles, the coordinator agent's context window is clogged with 60,000 tokens of raw console noise. The model experiences severe attention dilution, misses the actual point of failure buried on line 412, and burns dollars of API inference on string parsing.

Autonomous agents do not think in scrolling terminal text. To govern swarms at production scale, observability must move up the stack: from unstructured character streams to **multi-dimensional AST topologies and capability envelopes**.

---

## 1. The Three Failure Dimensions of Agent Execution

Monitoring autonomous software generation requires capturing three orthogonal dimensions simultaneously:

1. **Topological Dimension (The Dependency DAG):** Which modules does the agent touch, what interfaces does it consume, and does the resulting dependency graph introduce circular imports or leak private abstractions?
2. **Resource Dimension (Token & Memory Telemetry):** Where are tokens being consumed in the tool-calling loop, which AST subtrees cause context bloat, and what is the working memory overhead?
3. **Execution Dimension (Capability & Trace Envelopes):** What system calls did the agent execute during test runs, did it attempt unauthorized filesystem traversal, and did effectful operations remain hermetically sealed?

```text
               ┌────────────────────────────────────────────────────────┐
               │         Multi-Dimensional Observability Plane          │
               └───────────────────────────┬────────────────────────────┘
                                           │
         ┌─────────────────────────────────┼────────────────────────────────┐
         ▼                                 ▼                                ▼
┌───────────────────┐             ┌───────────────────┐            ┌───────────────────┐
│  Topological DAG  │             │  Token Telemetry  │            │ Capability Trace  │
│  - AST Hierarchy  │             │  - Context Density│            │ - Jailed Syscalls │
│  - Cycle Guard    │             │  - Prompt Ratios  │            │ - Effect Sigil (!)│
│  - Public APIs    │             │  - Cache Hit Rate │            │ - Proof Contracts │
└───────────────────┘             └───────────────────┘            └───────────────────┘
```

---

## 2. AST Topology: Catching Architectural Rot Before Compilation

In human software engineering, architectural drift happens slowly over months. In agentic swarms, an autonomous agent can turn a clean modular monolith into a tangled dependency graph in forty seconds.

In AgentScript (ASL), every module explicitly declares its exports (`:x`) and imports (`:i`). Because ASL code is an exact representation of its Abstract Syntax Tree, the compiler generates a deterministic dependency DAG without executing a single line of code:

```agentscript
(module store/checkout
  :d "Checkout transaction coordinator"
  :x [process-checkout]
  :i [(store/cart :a cart)
      (store/payment :a pay)
      (sys/time :a time)])
```

### Real-Time Cycle and Boundary Auditing

When a subagent generates or modifies code:
* The AST analyzer immediately projects the module into the global topological graph.
* If the agent introduces a cycle (e.g., `store/payment` importing `store/checkout`), the observability engine flags a **Topological Fault** instantly.
* If a subagent attempts to access an unexported identifier from a peer module, the diagnostic triggers before any expensive test suite is booted.

The coordinator agent does not read compiler output logs. It receives a structured S-expression frame identifying the exact topological edge that violated the architecture:

```agentscript
(fault :type :circular-dependency
       :cycle [store/checkout store/payment store/checkout]
       :action :reject)
```

---

## 3. Token Telemetry: Eliminating Attention Dilution

Context windows are finite physical buffers governed by attention matrices. In multi-agent swarms, token expenditure follows a power-law distribution: 10% of poorly structured files consume 80% of the prompt bandwidth.

Traditional application performance monitoring (APM) tracks CPU cycles and memory allocations. ASL introduces **Token-Aware Telemetry**:

1. **Context Density Scoring:** Measures the ratio of semantic type contracts to implementation noise across all loaded modules.
2. **Attention Decay Indicators:** Flags when a subagent is operating with context windows where critical instructions fall into the low-attention "middle zone".
3. **AST Pruning Suggestions:** Identifies private helper functions that should be stripped before handoff to peer agents.

By measuring token efficiency at the compiler level, swarms maintain an average context density reduction of **78%**, preventing context rot before it degrades reasoning.

---

## 4. Jailed Capability Traces: Auditing Execution in Zero-Trust Runtimes

Allowing an autonomous agent to execute arbitrary Bash or Python commands on a host machine is an unacceptable security hazard. Sandboxing with remote Docker containers introduces hundreds of milliseconds of latency per test run.

ASL resolves this through **In-Memory WebAssembly Capability Isolation**:

* Functions that interact with the external environment (filesystem, network, process execution) are declared with an explicit effect sigil (`!`).
* Pure functions carry mathematical guarantees: they cannot perform I/O, allocate untracked host resources, or mutate global state.
* When effectful code is executed, it runs inside an in-memory WebAssembly sandbox (`wasm32-wasip1`) where all system calls are intercepted by a capability envelope.

```text
Agent Code ──> Wasm Sandbox ──> Jailed VFS ──> Capability Envelope ──> Host
                                    │
                             [Path Jail Guard]
                          Blocks /etc, ~, ../..
```

If an agent attempts to access `/etc/passwd` or read parent directories via `../../`, the capability guard traps the execution in **0.01ms** and logs the exact AST node that initiated the violation.

---

## 5. The Cockpit: Unifying Observability for Humans and Models

The AgentScript web showcase integrates these dimensions into the **Agent Observability Studio**:

* **Visual Module DAG:** Real-time visual graph showing module relationships, import counts, and cycle warnings.
* **Live Token Inspector:** Instant breakdown of byte size vs token count across BPE tokenizers (`cl100k_base`).
* **Quality Doctor:** Automated AST structural clone detection and anti-pattern repair (`asl lint` and `asl fix`).
* **Interactive Sandbox:** Sub-millisecond execution telemetry directly in the browser.

By treating observability as a multi-dimensional compiler property rather than an afterthought of string logging, AgentScript enables teams to deploy autonomous agent swarms with mathematical guarantees of safety, budget predictability, and architectural integrity.
