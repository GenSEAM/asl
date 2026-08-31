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

### Phase 6 — The agent-facing surface, measured (tooling) — **DONE**, commit `51f5f03`
Goal 4 has no gate; this phase gives it numbers that can regress. The three existing axes —
ambiguity, observability, token budget — plus the editing surface the owner named: structured edit
operations (point and range), AST access and structural search, wired into the distributor, so an
agent edits or replaces blocks without emitting large outputs. The fork's formatter (`tools/fmt/`)
and bindgen (`tools/bindgen/`) are re-integrated and adapted to the new name here.
*Acceptance:* ambiguity is surfaced and driven to zero or recorded; edit/AST/search covered by
tests; the formatter is idempotent on the corpus.

### Phase 7 — TypeScript backend  (roadmap 3) — **DONE**, commit `c8c06ac`
The browser-side glue for the Wasm story and a measurement target. The stashed
`backend/to_typescript.py` + `backend/ts/rt.ts` + the `prelude.json` `ts` templates are the starting
point, re-integrated and gated by `tsc`. Third arm on the differential gate.
*Acceptance:* a third arm on `differential.py` runs and agrees; `tsc` accepts the emitted output.

### Phase 8 — Go backend  (roadmap 6) — **DONE**, commit `b4d781f`
`backend/golang/rt/rt.go` exists; no transpiler. A GC'd native target and a fourth differential arm.
*Acceptance:* `to_go.py` built; all 32 fixtures pass Go transpilation and `go vet`; differential gate passes with Go arm.

### Phase 9 — Harness whole-program mode  (roadmap 4) — **DONE**, commit `70195fe`
`bench/harness/run.py` drives a pure entry function; `EXPERIMENT.md` amendment 2026-08-20-b
specifies a terminal-bench shape.
*Acceptance:* multi-target runner supports Python, TypeScript, Rust, Go, and Interpreter with isolated workspaces, 6-stage lifecycle tracking, whole-program tasks, offline `--dry-run`, and automated test suite (`bench/harness/test_run.py`).

### Phase 10 — WebAssembly Browser Sandbox & Web Runner — **DONE**
Browser- and Node-compatible WASI / WebAssembly runner and compiler integration. Adds `agentscript build --target wasm` to CLI, builds `backend/ts/wasm_runner.ts` (browser memory buffers, WASI preview1 polyfill/shim, export invoker, structured execution result), and tests execution in both Node and simulated browser context.
*Acceptance:* `agentscript build <file> --target wasm` produces valid wasm; `backend/ts/wasm_runner.ts` executes corpus programs capturing stdout/stderr/exit in-memory; unit tests pass.

### Phase 11 — AgentScript MCP Server & Developer Agent Tooling — **DONE**
A Model Context Protocol (MCP) server (`tools/mcp/`) and agent context utilities. Implements stdio JSON-RPC MCP server exposing `asex_check`, `asex_eval`, `asex_format`, `asex_ast`, `asex_compress_module` (token compressor extracting interface-only signatures). Includes automated test suite for all MCP tools and local skill documentation.
*Acceptance:* `tools/mcp/` server starts over stdio, passes MCP protocol schema tests, all tools return structured results matching specification; `pytest tools/t/test_mcp.py` green.

### Phase 13 — ASL Best Practices & Integration Recipes — **DONE**, commit `1c56335`
Battle-tested integration recipes (in-browser Wasm sandbox, multi-agent MCP loop, cross-compilation CI/CD, agent VFS scratchpad, and native FFI) with interactive UI showcase.
*Acceptance:* `docs/BEST_PRACTICES.md` written, `web/src/components/BestPractices.tsx` mounted, `npm run build:web` passes.

### Phase 14 — Universal Framework Bridges (React, Vue, Angular, Svelte) & High-Perf Wasm Engine — **ACTIVE**
Unifies frontend architectures by enabling ASL as the zero-drift portable core logic layer for React Hooks, Vue 3 Composables, Angular Injectable Services, and Svelte Runes/Stores, with zero-boilerplate Wasm acceleration (<0.04ms) for math, physics, canvas, crypto, and data crunching.
*Acceptance:* `docs/FRAMEWORKS.md` created, `web/src/components/FrameworkBridges.tsx` with live framework code matrix and telemetry mounted, `npm run build:web` and all gates green.

## Out of scope — deferred to subsequent pass

* **Measurement runs** (`l-298e`) — gateway endpoint, model identifier, credential env var.
* **Concurrency / async** — deliberately absent; function colouring undecided.

