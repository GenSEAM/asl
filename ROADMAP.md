# ROADMAP.md — as-lang (AgentScript) project state and handoff

Written to be read cold. A session starting from zero should be able to resume from this file
alone, plus `AGENTS.md` for commands and `.pcp/INDEX.md` for recorded intent.

**Last updated:** 2026-08-21 · **Head commit at writing:** `970568c`

---

## 1. What this project is

AgentScript — every searchable identifier is `as-lang`, and source files are `.as` — is an
S-expression language designed so that LLM agents can generate large, reusable units of working
code in a single pass, transpiled to native Rust, Kotlin and Swift (the priority targets), with
TypeScript and Python secondary.

Since v0.3 the language also has a reason to exist that is not about syntax: a **total foreign
boundary**. A host library is declared with types and every foreign call yields `(Result T
String)`, which is strictly more than the host's own checker can express, because host type stubs
carry no exception information at all (PCP `d-4b8c`). Go was a priority target until 2026-08-21 and is
now best-effort: wanted eventually, gated and planned for by nothing. `EXPERIMENT.md` amendment
`2026-08-21-b` and PCP `d-bf87` carry the reasoning; mobile access is the motive and is deferred
(PCP `l-720b`).

Four goals, in the owner's order of priority:

1. **Type safety** — errors caught before runtime.
2. **Transpilability** — deterministic, byte-reproducible native output.
3. **Coverage** — expressive enough for most ordinary programs.
4. **Agent legibility** — maximise the work an agent completes per pass. The unit of one pass is
   defined as **a whole working module**, not a function.

Modularity and reusability are treated as first-class requirements, not later features, because
goal 4 collapses without them: nothing produced in one pass can be built on by the next.

---

## 2. Current state — verified, not asserted

Everything below was checked by a command whose output was read, not inferred.

| Area | State |
|---|---|
| Language specification | **v0.3 complete** — `AGENT_SPEC_CORE.md`; adds I/O (§10) and FFI (§11) |
| Grammars | **two, agreeing** — Lark (Earley) and tree-sitter |
| Tooling (AST, structural search) | **working** — queries return real captures |
| Conformance gate | **green** — 11 fixtures × 2 grammars, 0 failures |
| Closure gate | **green** — no example calls an undefined name |
| Python backend | **working** — corpus transpiles, tests execute |
| Rust backend | **working** — corpus transpiles and `rustc` accepts it |
| Swift backend | **working** — corpus transpiles and `swiftc` accepts it |
| Differential gate | **green** — Python, Rust and Swift agree on every case |
| Kotlin backend | priority target, no transpiler — toolchain not installed |
| WebAssembly | **works via the Rust backend** — pure modules only; effectful ones refused by capability |
| JavaScript backend | lowering rules exist in the prelude, no transpiler |
| I/O surface | **working** — 11 builtins, all total; executed by `backend/t/test_io.py` |
| Foreign boundary | **specified and lowered** — `defextern`/`defopaque`/`:extern`, Python target |
| Binding generator | **working** — `tools/bindgen/from_pyi.py`, 8 tests |
| Coverage gate | **green** — 103/103 builtins appear in an example |
| Handbook example gate | **green** — every fenced block parses under both grammars |
| Grammar shape gate | **green** — both grammars find the same qualified names, not just the same verdict |
| Overflow parity | **green** — all three backends trap; Rust checked under `-O`, where it used to wrap |
| Semantic checker | **12 of 15 §9 rules** — `checker/check.py`; rules 3 and 6 need inference |
| Reference interpreter | **not built, deliberately** — see below |
| Measurement harness | **not started — blocked**, see §5 |

### Documents, in reading order for a newcomer

0. `prelude/prelude.json` — the vocabulary, authoritative. The specification tables and the
   handbook are generated from it; nothing else may restate it.
1. `AGENT_SPEC_CORE.md` — the language. **Normative** for the forms. Start here.
1b. `prelude/HANDBOOK.md` — generated agent-facing reference, 4,531 measured tokens. This is the
   artifact that goes into a prompt, and every example in it is now parsed by a gate.
1c. `.claude/skills/as-lang/SKILL.md` — the short working loop: what to read, what to run, what
   the four rules are. Read before editing `.as`; it is not a substitute for the handbook.
1d. `README.md` — the front door, including an explicit list of what is not true yet.
2. `ROADMAP.md` — this file.
3. `EXPERIMENT.md` — pre-registered measurement protocol and pass/fail thresholds. **Read §9
   first**: two amendments supersede parts of the body.
4. `RESEARCH_REPORT.md` — evidence on whether the concept is viable at all. Read §3 and §5.
5. `SPEC_REVIEW.md` — critique of the original v0 draft; explains why v0.2 looks as it does.
6. `AGENT_SPEC.md` — the original v0 draft, **frozen, superseded, kept only for provenance**.

---

## 3. What the language is, in one page

Full detail in `AGENT_SPEC_CORE.md`. This is orientation only.

* **Modules by default.** Every file is a module. Visibility is **private by default**; the
  `:export` list is a deliberate contract. A module header carries a mandatory `:doc`, an export
  list, and aliased imports — and is readable without the body, which is the property goal 4 needs.
* **Type parameters** bound explicitly in `{ }` on `defun`, `defschema`, `defenum` — a name is a
  type variable because it was declared one, never because of how it is spelled.
* **Closed unions** via `defenum`, with mandatory exhaustive `match`. Recursive and parameterisable.
* **Totality throughout** — `if` needs both branches, `cond` needs `:else`, `match` must be
  exhaustive, lookups return `Option` rather than trapping.
* **No implicit conversion**, fixed numeric widths (`Int32`/`Int64`/`Float64`), trapping overflow.
* **`Result` + `try`** for fallible code: `match` eliminates, `try` propagates without nesting.
* **Deliberately excluded:** agents, UI, async, FFI, JSON serialization, I/O.

### The one evidence-backed argument for S-expressions

Do not claim others. Format restriction damages reasoning mainly when the grammar **commits a
result before the reasoning that produced it**: constraining by instruction costs ~1 point on the
measured benchmark, while constrained decoding that forces answer-before-reason costs ~27. A Lisp
body is a sequence whose value is its tail expression, so derivation structurally precedes result.
Claims about parser convenience or token efficiency are **not supported** by located evidence.
Source: `RESEARCH_REPORT.md` §3.

---

## 4. Immediate next step

**Finish the type layer of the checker.** `checker/check.py` now decides twelve of §9's fifteen
rules and sits in the gate sequence; `--rules` prints the split. What is left is the part that
needs a type system and cannot be faked structurally:

* **rule 3/6 — types.** Inference at call sites, and the judgement that no numeric operation mixes
  `Int64` with `Float64`. This is the half the located evidence says matters most
  (`RESEARCH_REPORT.md` §5), and it is the reason a clean check still does not mean well-typed.

Everything else §9 lists is enforced. Written in Python deliberately, as the oracle the eventual
Rust frontend must agree with (PCP `d-c4a1`).

Why this and not backends: the conformance gate proves only that two parsers agree on *shape*.
Nothing currently rejects a program that imports a cycle, calls a function with the wrong arity,
uses an unbound type variable, references an unexported member, or fails to handle a union case.
Located evidence puts the large majority of failures in LLM-generated code at the type level, with
grammar-level constraints capturing only a small fraction of achievable error reduction
(`RESEARCH_REPORT.md` §5) — so building backends first would optimise the part already known to be
small.

Checks it must implement — these are `AGENT_SPEC_CORE.md` §9 rules 2, 5, 7–11, none of which any
grammar can express:

- name resolution, including `alias/member` against the alias's `:export` list
- import cycle detection
- type checking, with inference at call sites
- type-variable binding and scope
- `match` exhaustiveness, and arity of enum-case patterns
- `try` only inside a `defun` returning a compatible `Result`
- reserved `as-` prefix
- mandatory `:doc` on the module header and on every exported `defun`
- **`:effects [io]` declared wherever an effectful builtin is reached, transitively** (§9 rule 12)
- **a foreign result used as a value rather than a `Result`** (§9 rule 5 over §11)
- **`:target` present on every `defextern`** (§9 rule 13) — the *transpile* half of this rule is
  already enforced by the backends and asserted by `check_corpus.py`
- **no `defopaque` value inspected** (§9 rule 14)
- **at most one `defentry`** (§9 rule 15)

Fixtures for semantic-only rules live in `grammar/corpus/semantic/`. They **must parse** — a
grammar that rejects them is over-tight. Today that directory holds one fixture and the gate
reports it as pending; each new check should add fixtures there.

### After the checker

1. **Reference interpreter** — enough to execute the corpus and validate benchmark translations.
   Rust, per the priority target; tree-sitter's Rust bindings are first-class and the code survives
   into the compiler frontend.
2. ~~**I/O surface**~~ — **done** in v0.3 (§10), and the effect question was decided rather than
   deferred: effects are **declared and checked**, not inferred and not carried in the return type
   (§4.6). The failure type is the host's `String` message; a structured union was rejected for now
   because its cases could not be made identical across three hosts, which the differential gate
   would have caught as a disagreement.
3. **Python and JavaScript backends** — the measurement targets. Rust, Kotlin and Swift are the
   native targets and are unchanged as a product goal.
4. **Benchmark harness** — terminal-bench, comparing generated AgentScript transpiled to Python/JS
   against real Python/JS solutions to the same tasks.
5. **Measurement** — see §5. Blocked.
6. **Native backends** — Rust and Swift exist; Kotlin is next and needs a toolchain installed
   first. Only Rust raises the ownership question (PCP `l-880d`); the other two are
   reference-counted or garbage-collected, which is part of why they are the cheaper targets.
7. **Self-hosting probe** — write the AgentScript lexer in AgentScript. Prediction on record: it needs
   closed unions, which v0.2 now has, so the probe is newly worth running.

---

## 5. Blocked — needs the owner

Measurement cannot start, now for two independent reasons.

**Language:** the benchmark is whole programs that read and write, and Core has no I/O
(PCP `r-56bf`). This blocks every arm regardless of access.

**Access** (PCP `l-298e`) — required:

1. **LLM Gateway endpoint** — is it OpenAI-compatible (`/v1/chat/completions`)?
2. **Exact model identifier**, as the API accepts it. A model was named verbally as
   "gpt 5 6 luna"; this was not resolvable to a real identifier and has deliberately **not** been
   guessed at.
3. **Environment variable name** holding the credential. Credentials go in the environment only —
   never the repository, never a committed artifact.
4. **Harness** — terminal-bench was chosen as the driving agent/benchmark over Factory Droid and
   over SWE-bench. SWE-bench was rejected because its tasks are edits inside existing Python
   repositories and require interoperating with arbitrary host code, which Core cannot express
   without FFI; measuring there would report a deliberate scope boundary as a language failure.
   Needed: the headless invocation and how a specification is supplied to it.

The harness can be written and unit-tested without any of this. It cannot be run.

---

## 6. Known gaps — do not mistake green gates for a validated language

* **Vocabulary coverage 23%.** Only 22 of 92 declared builtins appear in any example.
  The closure gate proves no example uses an *undefined* name; it says nothing about defined names
  no example uses, and that direction is what degrades generation quality. PCP `l-3434`.
* **No type checking.** See §4. Twelve of §9's fifteen rules are enforced; the two that need
  inference are not, so a `.as` file that parses and checks is **not** known to type-check. The
  target compilers are still the strongest signal there.
* **The foreign boundary is lowered only for the Python target.** Rust and Swift refuse a foreign
  module by name, which is correct and asserted, but it means the total-boundary claim is
  demonstrated in one ecosystem so far.
* **Cross-module resolution does not exist.** `alias/member` flattens to a single mangled name, so
  a module importing another does not link; `06-module.as` is skipped by every backend for that
  reason.
* **Ownership model unrecorded.** The Rust backend was built anyway, on the conservative
  strategy of cloning at every use site, so the open question is now the cost of that rather than
  whether it compiles. It is a Rust-only question: the Swift backend never had to answer it.
  PCP `l-880d`.
* **Concurrency deliberately absent.** No async, so function colouring has not had to be decided.
  It will have to be before any concurrent construct is added.
* **The core premise remains unmeasured.** No located source evaluates whether LLMs generate
  S-expressions more or less reliably than mainstream languages, and the evidence that generation
  quality tracks training-corpus presence predicts a purpose-built language will underperform. Every
  artifact so far measures internal consistency, which proves nothing about the actual claim.
  `RESEARCH_REPORT.md` §1, PCP `r-7ea3`.

---

## 7. Roles in measurement

Qualitative critique of transpiled output is in scope for this assistant. Scoring is not
(PCP `c-9af5`).

* **Mechanical, no judgement:** tests pass or fail, the target compiles or does not, reference
  implementation and backends agree or do not. This is the gate.
* **Judged, reported alongside, never scored:** idiomaticity of the generated Python/JavaScript,
  readability, and transpiler artifacts such as redundant copies or awkward encodings of language
  constructs the target lacks.

The separation is structural rather than a matter of care: a judge who designed the language
resolves every ambiguous case toward the design they already chose, and those errors correlate
instead of cancelling.

## 8. Working agreements

* **The first run is a pilot, not a measurement.** 2-3 borderline tasks under a $0.20 cap enforced
  in the harness. It can detect catastrophic failure; it cannot evaluate the 15 pp threshold, and
  must not be reported as if it could.
* **Pre-registration is binding.** `EXPERIMENT.md` §9 requires amendments to be dated and to state
  whether they were made before or after seeing results. Editing a threshold after seeing a result
  invalidates it — say so rather than quietly changing it.
* **The primary gate is fixed:** generated code must land within **15 percentage points** of the
  baselines named in the current `EXPERIMENT.md` amendment — real Python/JavaScript solutions to
  the same terminal-bench tasks, per `2026-08-20-b`, not the Go and Rust baselines the body of that
  document still names. If missed, stop and report; do not iterate prompts until it passes.
* **Benchmark translations are written by hand.** A model-generated translation contaminates the
  thing being measured.
* **Both grammars change together.** They are separate artifacts that can drift silently; a drift
  means the constrained-decoding arm enforces a different language than the tooling parses. The
  gate fails on disagreement, not only on a wrong verdict.
* **Closure is checked, never asserted.** The specification claims to be closed; that claim is only
  worth anything because a gate enforces it. It was false once already.
* **Record intent in PCP, implementation in code.** Entries carry motivation and decisions, never
  code, schemas, or file maps.
