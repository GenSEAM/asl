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

Order revised 2026-08-29 on the owner's direction: WebAssembly is the commercial target and moves
up; a phase is added for the agent-facing surface, because goal 4 of `ROADMAP.md` — *maximise the
work an agent completes per pass* — is the only one of the four goals with no gate behind it.

### Phase 1 — Types across the module boundary  (gap `r-ea8c`)  — **DONE**, commit `a635ab4`
`:export` admits type names, an importer writes `alias/TypeName`, identity is nominal and keyed by
the defining module, and rule 13 forbids an exported signature from naming a private type. That last
rule is what makes a module header usable as an interface contract, which is what the Wasm thesis
rests on.

### Phase 2 — Vocabulary coverage  (gap `l-3434`)  — **DONE**, commit `d69c331`
Executed coverage 33/107 → 107/107, proven by a tracer rather than a scan and mutation-tested at
101/107. Ten lowerings repaired. Three portability blockers found in review and fixed, and the
coverage gate hardened against the fake-it attacks the reviewers demonstrated.

### Phase 3 — WebAssembly target v1  (roadmap 6b, `d-f484`, `c-c759`)
The commercial target. Route already measured in `.plans/phase-3/FEASIBILITY.md`: AgentS → Rust →
`wasm32-wasip1` → `node:wasi`, with stdout and exit status both observable, so the Wasm arm attaches
to the existing differential gate rather than needing a new one. No new tooling required.
What is not free is what makes it *glue*: an interface contract generated from the module header,
and a decision on how a foreign call's failure crosses that boundary. Rendering and system UI are
explicitly out (`c-c759`).

### Phase 4 — The agent-facing surface, measured
Goal 4 has no gate. This phase gives it three, each a number that can regress:

* **Unambiguous.** `grammar/parse.py` sets `ambiguity="resolve"`, so ambiguity is never surfaced —
  and the base grammar is already ambiguous for `(s/concat …)` and for every `match`. For a language
  whose thesis is constrained decoding, an unsurfaced ambiguity is not cosmetic: the token mask goes
  wrong rather than the parse. Surface it, count it, drive it to zero or record each one.
* **Observable.** Every rejection is a coded diagnostic with a position and a fixture that pins the
  code — no traceback escapes, no defect reported under two codes, no code that fires for a reason
  other than the one it names. Phases 1 and 2 found all three of those.
* **Token-efficient.** `prelude/HANDBOOK.md` is resent on every model call and has grown every
  phase. Put it under a budget with a recorded number, and measure source density against typed
  Python on the benchmark task — the 1.83x → 1.66x prediction from lambda elision is still untested.

### Phase 5 — JavaScript/TypeScript backend  (roadmap 3)
The browser-side glue for the Wasm story and the second measurement target. Third arm on the
differential gate. Note `d-e5a1`: the `js` `min`/`max` templates are known-wrong for NaN and were
left alone because no JS runtime was available to check against.

### Phase 6 — Go backend  (roadmap 6)
`backend/golang/rt/rt.go` exists; no transpiler. A GC'd native target and a fourth differential arm.

### Phase 7 — Reference interpreter  (roadmap 1)
Rust, over the tree-sitter AST. The dynamic-execution runtime, and the code survives into the
compiler frontend.

### Phase 8 — Harness whole-program mode  (roadmap 4)
`bench/harness/run.py` drives a pure entry function; `EXPERIMENT.md` amendment 2026-08-20-b
specifies a terminal-bench shape.

## Not in scope — owner decisions, recorded as blocked

* **Measurement runs** (`l-298e`) — gateway endpoint, model identifier, credential env var.
* **Concurrency / async** — deliberately absent; function colouring undecided.
