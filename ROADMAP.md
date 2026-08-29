# ROADMAP.md — AgentS project state and handoff

Written to be read cold. A session starting from zero should be able to resume from this file
alone, plus `AGENTS.md` for commands and `.pcp/INDEX.md` for recorded intent.

**Last updated:** 2026-08-29 · **Head commit at writing:** `8679362`, plus uncommitted phase-1 work
(module-boundary types). Every figure below was re-derived after that work and after the two review
passes that followed it.

---

## 1. What this project is

AgentS is an S-expression language designed so that LLM agents can generate large, reusable units
of working code in a single pass, transpiled to native Rust and Go (the priority targets), with
TypeScript and Python secondary.

**WebAssembly is the target the language is aimed at** (PCP `d-f484`): the role is a typed glue
layer between ecosystems that meet as compiled modules rather than as source, with the module's
existing export contract doubling as its interface contract. Source emission is unchanged and not
withdrawn — one source has two exits, a portable module or a specialised native implementation,
and which one a program takes is a deployment choice rather than a rewrite. What that target does *not* yet offer is rendering or system UI — PCP `c-c759`.

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
| Language specification | **v0.2 complete** — `AGENT_SPEC_CORE.md` |
| Grammars | **two, agreeing** — Lark (Earley) and tree-sitter |
| Tooling (AST, structural search) | **working** — queries return real captures |
| Conformance gate | **green** — 63 fixtures × 2 grammars (58 must parse, 5 must be rejected), 0 failures, plus 7 token-identity probes compared across both parsers |
| Closure gate | **green** — no example calls an undefined name |
| Python backend | **working** — 18 corpus fixtures transpile, `py_compile` accepts every one, 10 also run a declared expression |
| Rust backend | **working for `Int64`** — all 18 fixtures transpile and `rustc` accepts them, but seven arithmetic builtins declared over the numeric type variable `N` are lowered `i64`-only and do not compile at the other two numeric types; see §6. Phase 2 owns the repair |
| JavaScript backend | lowering rules exist in the prelude, no transpiler |
| Semantic checker | **working** — all thirteen rules of §9, plus §4.1 construction, type checking, and type resolution across a module boundary |
| Semantic gate | **green** — 24 fixtures clean (18 programs, 6 modules), 34 semantic fixtures each rejected under the rule they declare, 17 of them asserted to report that code *and nothing else* |
| I/O surface | **working** — read/write, files, `IoError`, tracked effects, `main` |
| Differential gate | **green** — 7 function cases and 7 whole-program cases, Python and Rust; 2 of the program cases also assert a declared expected output rather than only cross-backend agreement |
| Unit tests | **79 pass** — `backend/t`, `bench/algo`, `checker/t` |
| Reference interpreter | **not built, deliberately** — see below |
| Measurement harness | **built, never run** — `--dry-run` exercises the whole path with canned responses; a real run is blocked, see §5 |

### Documents, in reading order for a newcomer

0. `prelude/prelude.json` — the vocabulary, authoritative. The specification tables and the
   handbook are generated from it; nothing else may restate it.
1. `AGENT_SPEC_CORE.md` — the language. **Normative** for the forms. Start here.
1b. `prelude/HANDBOOK.md` — generated agent-facing reference, 12,311 characters, ~3,078 tokens at
   the project's chars/4 approximation. This is the artifact that goes into a prompt.
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

**The semantic checker is built** (PCP `l-78ae`, `d-4e72`). `checker/` resolves names across module
boundaries, detects import cycles, checks type-variable binding, `match` exhaustiveness, arity, the
reserved prefix and the mandatory docs, and then type-checks: unification with declaration-only
generalisation, instantiation at call sites, the numeric constraint that makes rule 6 fall out, and
`try`'s enclosing-`Result` rule. It runs as `checker/gate.py` and as the harness's `check` stage.

**Types cross the module boundary** (PCP `r-ea8c`, resolved by `d-5837`, `d-c912`, `d-d06b`,
`d-b47d`). `:export` admits type names alongside function names, an importer writes
`alias/TypeName` and `alias/case-name`, identity is nominal and keyed by the module that declared
the type rather than by the alias reaching it, and rule 13 forbids an exported signature from
naming a private type. That last part is what closes the requirement rather than half of it: without
it a module can still export a function whose parameter type no importer can write. Three holes were
left open deliberately — they are in §6.

**Lambda annotations are now elidable** (PCP `r-a624`). Both grammars accept a bare parameter and
an absent return type; the checker infers them from the position and reports `annotation` where the
position does not determine them; both backends lower either form. The predicted saving — 1.83x →
1.66x against typed Python on the first benchmark task — is now testable rather than hypothetical,
and testing it means **hand-writing an elided variant of the benchmark translation**, which is the
owner's to write: a model-written translation contaminates the measurement.

**The I/O surface is built** (PCP `r-56bf`, `d-4533`). Nine builtins in a new §6 group, failures as
the closed union `IoError`, effects tracked by a `!` marker on the signature, and `main` as the
entry point a program declares. Both backends lower it, and the differential gate now runs whole
programs and compares stdout *and* exit status, including a failing path — the error mapping is
derived independently on each target from errno and from `ErrorKind`, so agreement there is checked
rather than assumed.

The handbook, which is resent on every model call, grew from ~2,642 to ~3,012 tokens (10,569 →
12,048 characters at the project's chars/4 approximation): **+14%** on the dominant per-call cost.
Typed module boundaries took it to 12,311 characters, ~3,078 tokens. Measured against the head
commit's 10,599 characters, the uncommitted work is **+16%** in total on that cost.

**Next: the harness's whole-program mode**, ROADMAP item 4 below. `bench/harness/run.py` still
calls an entry function with cases and `bench/tasks/histogram.json` is a pure-function task, so the
terminal-bench shape chosen in `EXPERIMENT.md` amendment 2026-08-20-b is not implemented yet.

### Why it came before the backends

The conformance gate proves only that two parsers agree on *shape*. Located evidence puts the large
majority of failures in LLM-generated code at the type level, with grammar-level constraints
capturing only a small fraction of achievable error reduction (`RESEARCH_REPORT.md` §5) — so
building backends first would have optimised the part already known to be small.

Fixtures for semantic-only rules live in `grammar/corpus/semantic/`. They **must parse** — a
grammar that rejects them is over-tight — and each must be *rejected by the checker under the rule
its `; expect:` header names*. A fixture rejected for the wrong reason fails the gate: that is how
the reserved-prefix rule looked defended while nothing enforced it (PCP `c-099a`). A stronger
header, `; expect-only:`, asserts the fixture reports that code *and nothing else* — 17 of the 34
carry it, because a rule can otherwise fire correctly while a stale failure from an earlier pass is
still reported alongside it (PCP `c-c6a3`). Every new check adds fixtures there.

What the checker does **not** do, deliberately: it has no scrutinee-independent view of a `match`
in the resolve pass (the type layer supplies that), and it does not check builtin call arity
separately from typing them. It *does* now resolve types across a module boundary, and the arity of
a call reached through an alias is checked — that was open until the review passes and is not a gap
any more.

Two blind spots the review passes found, kept here because they are one lesson and a cold session
will otherwise repeat it. **A pass that recurses on one node type silently skips every form whose
children are of another, and no gate sees it.** The resolve pass descended through expressions only,
and a `cond`'s children are clauses rather than expressions — so rules 2 and 12, arity and the
construction checks were disabled inside every `cond` in the corpus, silently, for as long as `cond`
has existed. The second instance is the same shape one layer down: a `defschema` field's `:default`
is a value of the field's type, and it was never typed against it. Both were found by reading, not
by a gate; both were green in every gate before and after. PCP `c-2d38`.

### After the checker

1. **Reference interpreter** — enough to execute the corpus and validate benchmark translations.
   Rust, per the priority target; tree-sitter's Rust bindings are first-class and the code survives
   into the compiler frontend.
2. ~~**I/O surface**~~ — done, PCP `r-56bf`. Effects are tracked by a marker rather than left
   implicit, so the concurrency question stays open instead of being foreclosed.
3. **Python and JavaScript backends** — the measurement targets. Rust and Go remain the compiler's
   own self-hosting targets and are unchanged as a product goal.
4. **Benchmark harness** — terminal-bench, comparing generated AgentS transpiled to Python/JS
   against real Python/JS solutions to the same tasks.
5. **Measurement** — see §5. Blocked.
6. **Native backends** — Rust and Go, for self-hosting. Gated behind the checker *and* an
   unrecorded ownership decision (PCP `l-880d`).
6b. **WebAssembly target** — the cheap half is already reachable: the Rust backend's output is
   accepted for `wasm32-unknown-unknown` unchanged, and every rustc-gated corpus fixture produces
   a valid module (magic `0061736d`), so a target arrives with no new code generation. What is not
   free is everything that makes it *glue*: an interface contract generated from the module header,
   and a decision on how a foreign call's failure crosses that boundary — the same question
   `d-4b8c` answers for host bindings, asked again for a different boundary. Direct Wasm code
   generation, bypassing Rust, is a separate and much larger commitment: it owns memory layout and
   reclamation for recursive unions.
7. **Self-hosting probe** — write the AgentS lexer in AgentS. Prediction on record: it needs
   closed unions, which v0.2 now has, so the probe is newly worth running.

---

## 5. Blocked — needs the owner

Measurement cannot start, now for two independent reasons.

**Language:** resolved. Core has I/O (PCP `r-56bf`). What remains on this side is the harness,
which still drives a pure entry function rather than a whole program.

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

* **Vocabulary coverage is reported as 35%, and the number that means anything is 19%.**
  `grammar/closure_audit.py` reports 38 of 107 builtins "exercised". It counts a builtin as
  exercised when it appears as a call head in a scanned file — the valid corpus and the
  specification's own code blocks — so *exercised* means mentioned, never run. Wrapping each
  builtin's Python lowering in a recorder and running every program the gates actually execute puts
  the executed set at 33 of 107; of the 38 the gate counts, only **21 are ever executed** (19%).
  Seventeen of the counted builtins have never run, `/` and `mod` among them — which is exactly how
  they sit inside the "exercised" set while being broken for two of the three numeric types on the
  Rust backend. Twelve more execute in files the gate does not scan (the module fixtures and the
  benchmark variants), so the scan root is wrong in both directions; 57 builtins are neither
  mentioned nor executed. Even "executed" is weaker than it sounds: it means the lowering worked at
  the one type someone happened to use, not that it works. A coverage floor has to be defined over
  (builtin × type) and over lines that ran, or it measures the wrong thing. PCP `l-3434`.
* **Types cross the module boundary; three holes were left open.** `:export` admits type names, an
  importer writes `alias/TypeName` and `alias/case-name`, identity is nominal and keyed by the
  defining module, and rule 13 forbids an exported signature from naming a private type. PCP
  `r-ea8c` **Resolved** (`d-5837`, `d-c912`, `d-d06b`, `d-b47d`). Deliberately not closed: **opaque
  export** — every exported type publishes its cases or its fields (`d-d06b`); **separate
  compilation** — a program and its transitive imports are linked into one target artifact
  (`d-84a9`); and **cycle detection keyed on a module's declared name rather than on its path**, so
  two files declaring the same name are one node to the detector. The arity of a call reached
  through an alias was a fourth, and is now checked.
* **The checklist and the checker's diagnostic set no longer correspond one-to-one.** A check with
  no §9 entry is coded by name rather than given the next free rule number, so that a fixture's
  declared rule is assertable against the specification and not merely against the code that
  produced it. Type-application arity is the first such check: it is enforced, and §9 has no item
  for it. Closing the gap means adding a checklist item, which is a specification change. PCP
  `d-bad1`.
* **The Rust backend is numerically `Int64`-only.** `/`, `mod`, `checked-div`, `checked-mod` and
  `list-sum` lower to runtime helpers whose parameters are `i64`, and `min`/`max` lower to the
  standard total-ordering functions. All seven declare `N N -> N` or `(List N) -> N`, and `N` is
  `Int32`, `Int64` or `Float64` in both the specification and the checker. Compiling a probe that
  calls them at `Float64` and at `Int32` gives three `rustc` errors: the ordering trait is not
  implemented for the floating type, and the integer widths are not the declared parameter type. The
  corpus never reaches any of these at a type other than `Int64`, so every gate is green. **Phase 2
  owns the repair.**
* **The entry point's signature is unconstrained by the language.** Both host runtimes require it
  to take the argument vector and return a result failing with `IoError` — Rust structurally at
  compile time, Python by an explicit runtime check — and nothing in the specification or the
  checker says so. The two therefore reject the wrong shape at different times. PCP `l-e33e`.
* **The Lark grammar carries dead pattern productions.** It spells out a separate alternative for
  each prelude union case; the Earley parse resolves every such pattern to the general
  user-declared-case alternative instead. Both emitters cope, because they treat a prelude case
  exactly as a user case — but the grammar reads as though those alternatives fire. PCP `l-b1b8`.
* **The checker is hosted in Python, the compiler is to be hosted in Rust.** The rules will be
  written twice; the fixture corpus, not the code, is the durable artifact. PCP `d-4e72`.
* **Ownership model unrecorded.** The Rust backend exists and its output compiles, but on a
  conservative strategy — clone at every use site — chosen instead of a model, not derived from one.
  What is open is the cost of that strategy, which is now measurable rather than hypothetical. PCP
  `l-880d`, partly resolved.
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
  Go and Rust baselines on identical tasks and models. If missed, stop and report; do not iterate
  prompts until it passes.
* **Benchmark translations are written by hand.** A model-generated translation contaminates the
  thing being measured.
* **Both grammars change together.** They are separate artifacts that can drift silently; a drift
  means the constrained-decoding arm enforces a different language than the tooling parses. The
  gate fails on disagreement, not only on a wrong verdict.
* **Closure is checked, never asserted.** The specification claims to be closed; that claim is only
  worth anything because a gate enforces it. It was false once already.
* **Record intent in PCP, implementation in code.** Entries carry motivation and decisions, never
  code, schemas, or file maps.
