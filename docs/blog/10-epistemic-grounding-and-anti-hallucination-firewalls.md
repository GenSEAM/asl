# The Epistemic Grounding Firewall: Halting Agent Hallucinations at the AST Boundary
*By the ASL Systems & Safety Group*

Prompt engineering is an inadequate defense against autonomous agent failure.

In modern agent architectures, developers attempt to enforce safety and accuracy by stuffing negative constraints into the system prompt:
```text
"You must never invent API endpoints. You must always cite sources accurately.
Do not hallucinate parameters. Never touch directories outside /workspace."
```

Under real-world execution conditions—when prompts exceed 30,000 tokens, multiple subagents exchange intermediate data, and context decay sets in—these natural language guardrails inevitably erode. Attention weights dilute, adversarial context injections take effect, and the model begins hallucinating nonexistent function names, fabricating file paths, and making confident assertions that contradict the actual codebase.

To deploy agents on production infrastructure, safety cannot be an advisory suggestion in natural language. It must be an **enforced architectural boundary implemented at the AST compiler and proxy layer**.

---

## 1. The Epistemic Gap in Modern Agent Swarms

Large language models are probabilistic token predictors, not deductive truth engines. When an agent is tasked with synthesizing code or making system mutations, it operates across an **Epistemic Gap**:

1. **Fabricated Identifiers:** The model recalls an identifier from its pre-training data that resembles the current project's naming conventions and emits calls to functions that were never implemented.
2. **Citation Drift:** In RAG workflows, an agent summarizes search results or retrieved documentation, but subtly alters critical parameter units (e.g. interpreting milliseconds as seconds) or attributes claims to the wrong source.
3. **Escaped Capability Boundaries:** An agent tasked with inspecting a test log decides to run a broad shell find or install external packages, mutating the host system without authorization.

```text
                                  Agent Generation
                                         │
                                         ▼
                 ┌───────────────────────────────────────────────┐
                 │          Epistemic Grounding Firewall         │
                 └───────────────────────┬───────────────────────┘
                                         │
                 ┌───────────────────────┼───────────────────────┐
                 │                       │                       │
                 ▼                       ▼                       ▼
      ┌─────────────────────┐ ┌─────────────────────┐ ┌─────────────────────┐
      │ Factual Grounding   │ │  Closure Analyzer   │ │  Path & I/O Jail    │
      │ - Exact Quote Match │ │ - Symbol Existence  │ │ - Traversal Guard   │
      │ - Source Verification││ - Arity Check       │ │ - Effect Sigil (!)  │
      └─────────────────────┘ └─────────────────────┘ └─────────────────────┘
                 │                       │                       │
                 └───────────────────────┼───────────────────────┘
                                         │
                                         ▼
                            Verified Host Execution
```

---

## 2. Structural Grounding: The Closure Audit Gate

In AgentScript (ASL), the language specification guarantees **lexical and symbolic closure**. 

Every call head in an ASL expression must resolve to one of three things:
1. One of the closed 107 standard builtins declared in the normative specification.
2. A locally bound binder (introduced via `df`, `let`, or lambda parameters).
3. An explicitly imported symbol from an upstream module (`:i [(pkg/module :a m)]`).

Before an agent-generated module is permitted to execute, the compiler runs the **Closure Audit (`grammar/closure_audit.py`)**:

* It walks the concrete syntax tree using the native grammar parser.
* It extracts every call head and validates it against the known symbol table.
* If the agent attempts to invoke a hallucinated symbol or calls an imported function that was not declared in the export manifest, the firewall rejects the AST immediately with a structured diagnostic:

```text
closure_audit: undefined symbol 'list-zip-with' at line 24:8
  hint: did you mean 'list-map'?
```

The hallucination is halted in **1.8 milliseconds** at the parser boundary. It never reaches runtime execution, never causes an obscure runtime exception, and never pollutes peer agents' context windows.

---

## 3. Epistemic Citation Verification: Enforcing Source Grounding

When autonomous agents retrieve information from documentation or external search engines, the **Grounding Firewall (`asl-harness`)** enforces quote verification before downstream actions are taken:

* When an agent extracts a fact or API requirement, it must return an epistemic tuple:
  ```lisp
  (claim :statement "Timeout parameter must be specified in milliseconds"
         :source-id "doc-402"
         :exact-quote "timeout-ms: Integer duration in milliseconds"
         :confidence 0.98)
  ```
* The proxy performs a deterministic substring search of `:exact-quote` against the raw retrieved document in memory.
* If the quote does not appear verbatim in the source document, or if the source document has expired, the firewall blocks the claim and flags an **Unverified Assertion**.

This eliminates the "lazy summary" failure mode where agents invent API features that appear plausible but do not exist in the referenced documentation.

---

## 4. Hardware-Enforced Path and Capability Jailing

When an agent executes tests or performs file modifications, AgentScript enforces **Zero-Leak Jailing**:

1. **Isolated Filesystem Sandboxes:** The agent's file access is restricted to an in-memory virtual filesystem or a strictly designated project directory. Attempting to traverse upward (`../../`) or access absolute system paths (`/etc`, `/usr`, `~`) causes an immediate sandbox trap.
2. **Pure vs. Effectful Function Separation:** Pure functions (`df`) cannot perform I/O. Any code that touches disk, network, or console must be declared with an explicit effect sigil (`!`) and must be granted explicit capability tokens by the orchestrator harness.
3. **Subprocess Supervision:** All subprocess executions are executed through structured supervisory pipelines (`asl sh`), capturing stdout/stderr in memory rings and preventing zombie process hangs.

---

## 5. Defense-in-Depth for Autonomous Systems

By replacing natural language prompt suggestions with deterministic compiler gates, closure audits, epistemic quote verification, and in-memory WebAssembly sandboxing, AgentScript provides autonomous engineering swarms with a mathematically verifiable security boundary.

Agents are free to explore, refactor, and generate code at full velocity—knowing that hallucinations, unbounded side effects, and broken contracts will be halted instantly at the firewall.
