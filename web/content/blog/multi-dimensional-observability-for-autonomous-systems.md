# Debugging Autonomous Swarms Without Reading 50,000-Token Logs
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
(module store/checkout :d "Checkout transaction coordinator" :x [processCheckout] :i [(store/cart :a cart) (store/payment :a pay)])

fn processCheckout prices: (List Int64) -> (Result Int64 String)
  (pay/charge (cart/total prices))
```

The stage-0 host resolves every import by the module name a file declares before anything runs: an import of a module no file declares is `ERR_UNRESOLVED_IMPORT`, and a call to a name that is neither bound, imported nor a builtin is `ERR_UNKNOWN_SYMBOL`. Both are reported with file, line and column, so the coordinator gets the exact location rather than a log to search.

Cycles are audited at the package level. `asl coupling` reads the import declarations across the repository and reports cohesion, fan-in, fan-out and inter-package cycles; on 2026-09-24 it reported 46 packages, 340 modules and 0 cycles. Module-level cycles inside a package are not rejected by the host checker today; a detector for them is on our list.

For a single symbol, `(:observe :dim callers :symbol s)` returns its call sites with path, line and kind, which is what an agent needs before it changes a signature.

---

## 3. Token Telemetry: Measuring Where Context Goes

Context windows are finite buffers, and in multi-agent swarms token spending is uneven: a few large files take a disproportionate share of every prompt that loads them.

Traditional application performance monitoring tracks CPU cycles and memory. For agents, the scarce resource is tokens, so we measure them directly. `(:observe :dim tokenCost :scope path)` counts tokens by file kind with a named tokenizer and lists the costliest files. For example, run over `agent-bus` on 2026-09-24 (o200k_base, revision b8fc39a2), it reported 37 ASL files totalling 64,234 tokens, with `asl/packages/asl-agent-bus/src/bus.asl` the largest at 6,499.

That tells a coordinator which modules to hand over as interfaces or symbol slices instead of whole files. What we do not have yet is per-turn telemetry that attributes a running agent's context to the files it loaded; that is the next step.

---

## 4. Capability Boundaries: Auditing What an Agent Touches

Letting an autonomous agent run arbitrary shell or Python commands on a host is a security hazard, and remote containers add latency to every test run.

What exists today is a path boundary at the tool layer. Every path an `asl` op receives resolves against the workspace root; a path outside it is rejected with `ERR_BOUNDARY_VIOLATION` before anything is read or written. The agent loop, `(:agent ...)`, adds a declared ownership list: it edits only inside `:owns` and returns a receipt listing status, findings and the gates it ran.

What we are building is the execution half: effect tracking in the language, so that functions touching disk, network or process state are marked and checked, and an in-memory WebAssembly sandbox whose system calls pass through a capability envelope. Neither is enforced yet: today a function that calls `println` passes the host checker without any effect annotation.

---

## 5. Observability for Humans and Models

The same queries serve both audiences. A human reads the receipt; an agent parses it:

* **Module graph:** `asl coupling` for the package DAG and cycles; `(:observe :dim callers)` for one symbol.
* **Token cost:** `(:observe :dim tokenCost)` by kind, file and scope.
* **Working state:** `(:observe :dim session)` for running agent sessions and overlapping ownership; `(:observe :dim memory)` for the size of the `.asl/mem` ledgers.
* **Correctness:** `asl-host check` for names, arity and enum coverage, and `asl-host test` for executed assertions.

By treating observability as structured queries over the code rather than string logging, we give coordinators something they can act on without reading 50,000 tokens first. The execution dimension is the part still under construction.
