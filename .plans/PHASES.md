# AgentScript — Phased execution plan

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

### Phase 2 — Vocabulary coverage  (gap `l-3434`)  — **DONE**, commit `b6b43ff`
Executed coverage 33/107 → 107/107, proven by a tracer rather than a scan and mutation-tested at
101/107. Ten lowerings repaired. Three portability blockers found in review and fixed, and the
coverage gate hardened against the fake-it attacks the reviewers demonstrated.

### Phase 3 — Rename AgentS → AgentScript  (owner directive 2026-08-30)  — **DONE**
The language, grammar, module namespace, file extension, reserved prefix, CLI and docs move to the
new name. The fork's `.as` extension / `as-lang` identifier are re-used only where they fit; the
target is **AgentScript**, not `as-lang`. The fork's committed tooling and the stashed TypeScript
backend are re-integrated in their own phases, not here. All gates stay green; no string of the old
name survives where it names the language.
*Acceptance:* `rg` finds no `AgentS`/`.agents`/`agents.lark`/`agents-`/`asex` naming the language;
all seven gates + pytest green.

### Phase 4 — WebAssembly target v1  (roadmap 6b, `d-f484`, `c-c759`)  — **DONE**
The commercial target. Route already measured in `.plans/phase-4/FEASIBILITY.md`: AgentScript →
Rust → `wasm32-wasip1` → `node:wasi`, with stdout and exit status both observable, so the Wasm arm
attaches to the existing differential gate. The glue that is not free: an interface contract
generated from the module header, and a decision on how a foreign call's failure crosses the
boundary. Rendering and system UI are out (`c-c759`).
*Acceptance:* a corpus program runs on the Wasm target; its stdout/exit match the other arms.

### Phase 5 — Reference interpreter  (roadmap 1, promoted)  — **DONE**
Rust, over the tree-sitter AST, and the dynamic-execution runtime. This phase also serves the
development loop the owner named: write a test, run it in the interpreter immediately, no
transpilation to a host language. The code survives into the compiler frontend.
*Acceptance:* every `corpus/valid` program executes under the interpreter in `differential.py`'s **program mode** and agrees with the compiled arms on stdout/stderr/exit. Function-mode agreement is deferred (a Phase-5 follow-up or Phase 9).

### Phase 6 — The agent-facing surface, measured (tooling)
Goal 4 has no gate; this phase gives it numbers that can regress. The three existing axes —
ambiguity, observability, token budget — plus the editing surface the owner named: structured edit
operations (point and range), AST access and structural search, wired into the distributor, so an
agent edits or replaces blocks without emitting large outputs. The fork's formatter (`tools/fmt/`)
and bindgen (`tools/bindgen/`) are re-integrated and adapted to the new name here.
*Acceptance:* ambiguity is surfaced and driven to zero or recorded; edit/AST/search covered by
tests; the formatter is idempotent on the corpus.

### Phase 7 — TypeScript backend  (roadmap 3)
The browser-side glue for the Wasm story and a measurement target. The stashed
`backend/to_typescript.py` + `backend/ts/rt.ts` + the `prelude.json` `ts` templates are the starting
point, re-integrated and gated by `tsc`. Third arm on the differential gate.
*Acceptance:* a third arm on `differential.py` runs and agrees; `tsc` accepts the emitted output.

### Phase 8 — Go backend  (roadmap 6)
`backend/golang/rt/rt.go` exists; no transpiler. A GC'd native target and a fourth differential arm.

### Phase 9 — Harness whole-program mode  (roadmap 4)
`bench/harness/run.py` drives a pure entry function; `EXPERIMENT.md` amendment 2026-08-20-b
specifies a terminal-bench shape.

## Not in scope — owner decisions, recorded as blocked

* **Measurement runs** (`l-298e`) — gateway endpoint, model identifier, credential env var.
* **Concurrency / async** — deliberately absent; function colouring undecided.
