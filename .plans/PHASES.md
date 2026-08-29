# AgentS — Phased execution plan

Derived from `ROADMAP.md` §4/§6, re-prioritised against the stated product goal: a maximally
portable agent-specific language whose primary execution target is **WebAssembly**, running under
several runtimes (compiled and dynamically interpreted) on desktop and mobile.

Baseline at start: all seven gates green, 47 tests pass, head `8679362` + uncommitted work.

## Per-phase protocol (fixed, applies to every phase)

1. **Plan** — one planner agent writes `.plans/phase-N/PLAN.md`.
2. **Plan review** — reviewer agents (one lens each) validate the plan against the spec, the
   recorded PCP decisions, and the gates; orchestrator reconciles into `PLAN.md` v2.
3. **Implement** — implementer agent(s) execute the plan; all gates must stay green.
4. **Implementation review** — reviewer agents in one wave: conformance-to-plan, gap/consistency,
   correctness/regression.
5. **`/code-review`** skill over the phase diff.
6. **Fix** — findings applied.
7. **Gates + tests** run by the orchestrator; PCP entries recorded; commit; next phase.

## Phases

### Phase 1 — Types across the module boundary  (gap `r-ea8c`)
Blocking hole: `:export` admits only lowercase identifiers, so a `defschema`/`defenum` is
permanently module-private and no module can export a function whose signature mentions its own
type. Without this there is no interface contract, and the Wasm thesis (`d-f484`) rests on the
module header *being* the interface contract.
Touches: both grammars, `checker/collect.py`+`resolve.py`+`types_.py`, both backends, corpus.

### Phase 2 — Vocabulary coverage sweep  (gap `l-3434`)
36 of 107 builtins are exercised by any example. The two builtins compiled first after years of
being unexercised both had Rust lowerings that did not compile. Raise coverage to ≥95%, fix every
lowering that falls out, and add a coverage threshold to the closure gate so it cannot regress.

### Phase 3 — WebAssembly target v1  (roadmap 6b, `d-f484`, `c-c759`)
The product goal. Rust output → `wasm32` as a first-class gate; interface contract generated from
the module header; a decision on how a failure crosses the boundary (`d-4b8c` asked again for this
boundary); the module executed in a real runtime and added as an arm of the differential gate.
Rendering/system UI is explicitly out (`c-c759`).

### Phase 4 — JavaScript/TypeScript backend  (roadmap 3)
The browser-side glue for the Wasm story and the second measurement target. Third arm on the
differential gate, which is where portability claims are actually enforced.

### Phase 5 — Go backend  (roadmap 6)
`backend/golang/rt/rt.go` exists; no transpiler. A GC'd native target for desktop/mobile, and a
fourth differential arm.

### Phase 6 — Reference interpreter  (roadmap 1)
Rust, over the tree-sitter AST. The dynamic-execution runtime, and the code survives into the
compiler frontend.

### Phase 7 — Harness whole-program mode  (roadmap 4)
`bench/harness/run.py` still drives a pure entry function; `EXPERIMENT.md` amendment 2026-08-20-b
specifies a terminal-bench shape. Unit-testable without gateway access.

## Not in scope — owner decisions, recorded as blocked

* **Measurement runs** (`l-298e`) — gateway endpoint, model identifier, credential env var.
* **Ownership model** (`l-880d`) — unrecorded; every Rust signature is a guess without it.
* **Concurrency / async** — deliberately absent; function colouring undecided.
