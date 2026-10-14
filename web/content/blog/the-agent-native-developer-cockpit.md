# Building a Developer Cockpit for Synthetic Intelligences
*By GenSEAM | September 2026*

Software engineering toolchains (language servers, linters, formatters, debuggers, containerized sandboxes) were designed for human ergonomics. They assume a programmer typing at human speed, reading diagnostics in an IDE gutter, and tolerating compilation pauses.

Autonomous AI agents operate under different constraints.

An agentic coding loop may generate, inspect, test and refactor many modules in a few seconds. For an agent:
* Every diagnostic it has to read is paid for in context tokens.
* Reading a whole file to find one function wastes most of what it loads.
* Unconstrained file access risks directory traversal and changes to the host.
* Without a structural view of the project, multiple agents drift out of alignment.

So we build the toolchain for the agent first: every operation takes an S-expression and returns an S-expression receipt, sized to what the agent needs. This post describes the pieces that exist today in the `asl` toolbelt, and where they fall short.

---

## 1. Symbol-Sized Reads Instead of a Language Server

Traditional language servers (such as `rust-analyzer` or TypeScript's `tsserver`) are background daemons that keep AST caches and answer hover and definition requests over JSON-RPC.

An agent rarely needs hover. It needs the one definition it is about to change. The agent plane of `asl` answers that directly:

```text
asl '(:read :file "src/metrics.asl" :symbol "recordTick")'
asl '(:query :text "recordTick" :limit 5)'
```

`(:read)` returns just the symbol, with its kind and line range, or a bounded slice of a file; `(:query)` searches symbol definitions and text across the repository. Forms passed in one call run as one batch, so an agent can fetch several symbols in a single round trip. `asl '(:tools)'` lists every op with its parameters.

---

## 2. Diagnostics the Agent Can Act On

Traditional compilers and linters are passive: they find a fault, print a message, and stop. The agent has to read the error, reopen the file, infer the patch and rerun.

Checking an ASL file has two layers, and `(:check :file f)` runs both, in order:

* Delimiter balance, answered with a structured receipt such as `ERR_UNBALANCED_DELIMITERS` and the byte where the stray delimiter sits.
* The stage-0 host's checker (`host/out/asl-host check f`), on the staged content. It resolves names, checks call arity, checks that a match covers every case of an enum and that effectful functions are marked, all before anything runs. Calling `(add 1)` on a two-argument `add` fails with `ERR_ARITY add expects 2 argument(s), got 1`.

Here is a module that passes both (checked 2026-10-14):

```agentscript
(module telemetry/metrics :x [Counter recordTick])

schema Counter
  name: String
  ticks: Int64

fn recordTick c: Counter -> Counter
  (with c :ticks (+ c.ticks 1))
```

For delimiter slips there is `(:fix :file f)`, which proposes a minimal repair with a diff and the basis for choosing it, and stages it only with `:apply`. It refuses with `ERR_AMBIGUOUS_REPAIR` and a list of candidate byte offsets when more than one repair would balance the file. It balances text, not meaning: on a stray `)` at the end of a function body under a bare `fn` header line, it proposes opening a parenthesis before `fn` rather than deleting the extra closer, so its proposals still go through `asl-host check`.

---

## 3. Staged Edits: A Transaction Instead of a Text Write

Agents edit through a session buffer rather than writing files directly:

```text
asl '(:edit :file "src/metrics.asl" :old "(+ c.ticks 1)" :new "(+ c.ticks 2)") (:diff)'
asl '(:flush)'
asl '(:discard)'
```

`(:edit)` stages a string replacement, `(:diff)` shows staged changes against disk, `(:test :file f)` runs a test file against the staged content, and `(:flush)` writes all staged changes atomically, or `(:discard)` drops them. `(:txn :owns ...)` runs nested edits and gates atomically inside a declared set of paths.

---

## 4. Observability as Queries

When several agents modify different modules, coordinators need a view of project health that does not require reading code. `(:observe :dim d)` projects the workspace along one dimension:

* `tokenCost`: tokens by file kind, and the most expensive files, for a scope (it needs the tokenizer tables under `data/tokenizers` and refuses with `ERR_NO_ENCODER` without them).
* `callers`: call sites of a symbol with path, line and kind.
* `status`: stubs, callers and executing tests of a symbol or path.
* `coverage`: which requirements of a spec are implemented and tested.
* `memory`: sizes of the `.asl/mem` ledgers.
* `session`: running agent sessions and overlapping ownership.

For the package graph, `asl coupling` audits imports across the repository. On 2026-10-14 it reported 66 packages, 718 modules and 22 inter-package cycles: debt the audit makes visible, not a clean result.

---

## 5. Jailed Paths

Agent-generated operations are confined to the workspace. Every path an op receives resolves against the workspace root; a path that escapes it is rejected with `ERR_BOUNDARY_VIOLATION` before anything is read or written. The agent loop, `(:agent ...)`, adds an ownership list: it edits only inside `:owns`, runs the named `:gates`, and returns a receipt with status, findings and gate results.

What we do not have yet is a jailed execution sandbox for running generated programs with time and memory quotas. The nearest thing is the wasm32 target, whose modules import only four host functions, so a program that calls a file, environment or socket builtin does not compile for it. A sandbox with quotas is on the roadmap, not in the toolbelt.

---

## 6. The Closed Loop

Composed, these pieces give a loop in which each step returns structured data instead of prose:

```
   Agent generates ASL
            │
            ▼
   (:read) / (:query)          symbol-sized context
            │
            ▼
   (:edit) + (:diff)           staged, not yet on disk
            │
            ▼
   (:check)                    balance, names, arity, enums, effects
            │
            ▼
   (:test) on staged content   assertions executed
            │
            ▼
   (:flush) or (:discard)
```

### Conclusion

Tools define what systems can achieve. When coding agents use developer tools built for humans, they spend their context reading output that was formatted for eyes.

Building the toolchain for agents first, with symbol-sized reads, receipts instead of logs, staged edits and path jails, gives them tools shaped to how they work. The gaps are real too: the repair op does not know ASL's header syntax, token telemetry depends on tokenizer tables a checkout may not have, and execution sandboxing is still ahead of us.
