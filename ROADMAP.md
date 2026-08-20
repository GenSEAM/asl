# ROADMAP.md — AgentS project state and handoff

Written to be read cold. A session starting from zero should be able to resume from this file
alone, plus `AGENTS.md` for commands and `.pcp/INDEX.md` for recorded intent.

**Last updated:** 2026-08-20 · **Head commit at writing:** `2b80615`

---

## 1. What this project is

AgentS is an S-expression language designed so that LLM agents can generate large, reusable units
of working code in a single pass, transpiled to native Rust and Go (the priority targets), with
TypeScript and Python secondary.

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
| Conformance gate | **green** — 11 fixtures × 2 grammars, 0 failures |
| Closure gate | **green** — no example calls an undefined name |
| Semantic checker | **does not exist** |
| Interpreter | **does not exist** |
| Native backends | **do not exist** |
| Measurement harness | **not started — blocked**, see §5 |

### Documents, in reading order for a newcomer

1. `AGENT_SPEC_CORE.md` — the language. **Normative.** Start here.
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

**Build the semantic checker.** It is the next load-bearing component, ahead of interpreter and
backends. Recorded as PCP `l-78ae`.

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
- reserved `agents-` prefix
- mandatory `:doc` on the module header and on every exported `defun`

Fixtures for semantic-only rules live in `grammar/corpus/semantic/`. They **must parse** — a
grammar that rejects them is over-tight. Today that directory holds one fixture and the gate
reports it as pending; each new check should add fixtures there.

### After the checker

1. **Reference interpreter** — enough to execute the corpus and validate benchmark translations.
   Rust, per the priority target; tree-sitter's Rust bindings are first-class and the code survives
   into the compiler frontend.
2. **I/O surface** — now on the critical path, PCP `r-56bf`. The benchmark is whole programs that read
   and write, and Core has no I/O at all. Decide at the same time whether effects are tracked in
   the type system; leaving that implicit is cheap now and is what forces function colouring later.
3. **Python and JavaScript backends** — the measurement targets. Rust and Go remain the compiler's
   own self-hosting targets and are unchanged as a product goal.
4. **Benchmark harness** — terminal-bench, comparing generated AgentS transpiled to Python/JS
   against real Python/JS solutions to the same tasks.
5. **Measurement** — see §5. Blocked.
6. **Native backends** — Rust and Go, for self-hosting. Gated behind the checker *and* an
   unrecorded ownership decision (PCP `l-880d`).
7. **Self-hosting probe** — write the AgentS lexer in AgentS. Prediction on record: it needs
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

* **Vocabulary coverage ~26%.** Only about a quarter of declared builtins appear in any example.
  The closure gate proves no example uses an *undefined* name; it says nothing about defined names
  no example uses, and that direction is what degrades generation quality. PCP `l-3434`.
* **No semantic checking at all.** See §4.
* **Ownership model unrecorded.** Required before the Rust backend; without it every signature is
  a guess between moving, borrowing and cloning. PCP `l-880d`.
* **Concurrency deliberately absent.** No async, so function colouring has not had to be decided.
  It will have to be before any concurrent construct is added.
* **The core premise remains unmeasured.** No located source evaluates whether LLMs generate
  S-expressions more or less reliably than mainstream languages, and the evidence that generation
  quality tracks training-corpus presence predicts a purpose-built language will underperform. Every
  artifact so far measures internal consistency, which proves nothing about the actual claim.
  `RESEARCH_REPORT.md` §1, PCP `r-7ea3`.

---

## 7. Working agreements

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
