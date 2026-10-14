# Debugging Autonomous Swarms Without Reading Their Logs
*By GenSEAM | September 2026*

A common failure mode of scaling autonomous coding swarms is the **Observability Inversion Trap**.

When humans debug applications, they read terminal logs, scan stack traces and inspect local variables. When teams deploy multi-agent swarms, they replicate this pattern: they capture every subagent's `stdout`, stream JSON tool invocations into a dashboard, and ask a coordinator agent to "read the logs and diagnose the problem."

After a few execution cycles, the coordinator's context window is full of raw console output. Attention is spread over noise, the actual point of failure is buried hundreds of lines in, and the tokens spent on parsing text are tokens not spent on the task.

Autonomous agents do not think in scrolling terminal text. To govern swarms, observability has to move up the stack: from character streams to **structured queries over the code's topology, its token cost, and what it is allowed to touch**.

---

## 1. The Three Failure Dimensions of Agent Execution

Monitoring autonomous software generation means watching three orthogonal dimensions:

1. **Topological Dimension (the dependency graph):** Which modules does the agent touch, what interfaces does it consume, and does the result introduce cycles or reach into private code?
2. **Resource Dimension (token telemetry):** Where are tokens being spent in the tool-calling loop, and which files cause context bloat?
3. **Execution Dimension (capability boundaries):** What did the agent's operations touch, and did they stay inside the paths they were given?

```text
               ┌────────────────────────────────────────────────────────┐
               │         Multi-Dimensional Observability Plane          │
               └───────────────────────────┬────────────────────────────┘
                                           │
         ┌─────────────────────────────────┼────────────────────────────────┐
         ▼                                 ▼                                ▼
┌───────────────────┐             ┌───────────────────┐            ┌───────────────────┐
│  Topological DAG  │             │  Token Telemetry  │            │ Capability Bounds │
│  - Imports/exports│             │  - Cost by kind   │            │ - Workspace jail  │
│  - Cycle audit    │             │  - Costliest files│            │ - Owned paths     │
│  - Call sites     │             │  - Per scope      │            │ - Gate receipts   │
└───────────────────┘             └───────────────────┘            └───────────────────┘
```

---

## 2. AST Topology: Catching Architectural Rot Before It Runs

In human software engineering, architectural drift happens over months. An autonomous agent can tangle a clean module graph in minutes.

In AgentScript (ASL), every module declares its exports (`:x`) and imports (`:i`) in its header. Because the header is data, the dependency graph can be read without executing a line of code:

```agentscript
(module store/checkout :x [processCheckout] :i [(store/cart :a cart) (store/payment :a pay)])

fn processCheckout prices: (List Int64) -> (Result Int64 String)
  (pay/charge (cart/total prices))
```

The stage-0 host resolves every import by the module name a file declares before anything runs: an import of a module no file declares is `ERR_UNRESOLVED_IMPORT`, and a call to a name that is neither bound, imported nor a builtin is `ERR_UNKNOWN_SYMBOL`. Both are reported with file, line and column, so the coordinator gets the exact location rather than a log to search. (With two small `store/cart` and `store/payment` modules beside it, this example passes `asl-host check`.)

Cycles are audited at the package level. `asl coupling` reads the import declarations across the repository and reports cohesion, fan-in, fan-out and inter-package cycles. Run on 2026-10-14, it reported 66 packages, 718 modules and 22 inter-package cycles, plus 70 imports of a package the importer's manifest does not declare. Those are real findings, not a clean bill of health: the audit is how we see them, and the count is what has to come down. Module-level cycles inside a package are not rejected by the host checker today.

For a single symbol, `(:observe :dim callers :symbol s)` returns its call sites with path, line and kind, which is what an agent needs before it changes a signature.

---

## 3. Token Telemetry: Measuring Where Context Goes

Context windows are finite buffers, and in multi-agent swarms token spending is uneven: a few large files take a disproportionate share of every prompt that loads them.

Traditional application performance monitoring tracks CPU cycles and memory. For agents, the scarce resource is tokens, so we measure them directly. `(:observe :dim tokenCost :scope path)` counts tokens by file kind with a named tokenizer and lists the costliest files. It needs the tokenizer tables under `data/tokenizers`; without them it refuses with `ERR_NO_ENCODER` rather than guess, which is what it does in a checkout that lacks them.

That tells a coordinator which modules to hand over as interfaces or symbol slices instead of whole files. What we do not have yet is per-turn telemetry that attributes a running agent's context to the files it loaded; that is the next step.

---

## 4. Capability Boundaries: Auditing What an Agent Touches

Letting an autonomous agent run arbitrary shell or Python commands on a host is a security hazard, and remote containers add latency to every test run.

What exists today is a path boundary at the tool layer. Every path an `asl` op receives resolves against the workspace root; a path outside it is rejected with `ERR_BOUNDARY_VIOLATION` before anything is read or written. The agent loop, `(:agent ...)`, adds a declared ownership list: it edits only inside `:owns` and returns a receipt listing status, findings and the gates it ran.

The language adds the second half: effects are marked and checked. A function that calls an effectful builtin such as `println` must be marked (`fn ! main ...` or a name ending in `!`); otherwise `asl-host check` rejects it with `ERR_EFFECT_UNMARKED` before anything runs. And when a program is compiled to `wasm32-unknown-unknown` through `asl-target-llvm`, the module imports only four host functions (`asl.write`, `asl.exit`, `asl.nowNs`, `asl.trap`), and a program that calls a file, environment or socket builtin fails to compile with `ERR_CAPABILITY_ABSENT` naming it. What we do not have yet is a per-run capability envelope that grants a generated program a chosen subset of the host.

---

## 5. Observability for Humans and Models

The same queries serve both audiences. A human reads the receipt; an agent parses it:

* **Module graph:** `asl coupling` for the package DAG and cycles; `(:observe :dim callers)` for one symbol.
* **Token cost:** `(:observe :dim tokenCost)` by kind, file and scope.
* **Working state:** `(:observe :dim session)` for running agent sessions and overlapping ownership; `(:observe :dim memory)` for the size of the `.asl/mem` ledgers.
* **Correctness:** `asl-host check` for names, arity, enum coverage and effect marking, and `asl-host test` for executed assertions.

By treating observability as structured queries over the code rather than string logging, we give coordinators something they can act on without reading the logs first. Per-turn token attribution and per-run capability grants are the parts still under construction.
