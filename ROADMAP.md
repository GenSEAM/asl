# ROADMAP.md — AgentScript project state and handoff

Written to be read cold. A session starting from zero should be able to resume from this file
alone, plus `AGENTS.md` for commands and `.pcp/INDEX.md` for recorded intent.

**Last updated:** 2026-09-03 · **Head commit at writing:** `c88c7ed`, plus the self-hosted-parser
completion (`asl-selfhosted-runtime-v1` Phases 3–5, uncommitted): `asl parse` CLI + native-vs-Lark
benchmark, iterative (fold-based) lexer scanner, parse-all-packages gate. Every figure below was
re-derived after that work by running the command that produces it.

---

## 1. What this project is

AgentScript is an S-expression language designed so that LLM agents can generate large, reusable units
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
| Tooling (AST, structural search, fmt, bindgen, distributor) | **working** (Phase 6) — queries return real captures, formatter idempotent on corpus, bindgen text-level verified |
| Conformance gate | **green** — 74 fixtures × 2 grammars (69 must parse, 5 must be rejected), 0 failures, plus 7 token-identity probes compared across both parsers |
| Closure gate | **green** — no example calls an undefined name: **107/107 builtins evaluated (100%)** against `prelude/coverage.lock` |
| Python backend | **working** — all 32 corpus and benchmark fixtures transpile, `py_compile` accepts every one, participating in differential gate |
| Rust backend | **working** — all 32 corpus and benchmark fixtures transpile, `rustc` accepts every one, `backend/monomorphism.py` compiles all 400 admissible probes |
| TypeScript backend | **working** (Phase 7) — `backend/to_typescript.py` + `backend/ts/rt.ts`, all 32 fixtures transpile, `tsc` accepts every one, participating in differential gate |
| Go backend | **working** (Phase 8) — `backend/to_go.py` + `backend/golang/rt/rt.go`, all 32 fixtures transpile, `go vet` accepts every one, participating in differential gate |
| WebAssembly target | **working** (Phase 4) — `wasm32-wasip1` under `node:wasi`, participating in differential gate in program mode |
| Reference interpreter | **working** (Phase 5) — Rust tree-walking interpreter (`crates/agentscript-interp/`), participating in differential gate in both program and function modes |
| Semantic checker | **working** — all thirteen rules of §9, plus §4.1 construction, type checking, type resolution across a module boundary, and named checks (`type-arity`, `map-key-order`) |
| Semantic gate | **green** — 34 fixtures clean, 40 semantic fixtures each rejected under declared rule header |
| I/O surface | **working** — read/write, files, `IoError`, tracked effects, `main` |
| Tier-A monomorphism gate | **green** — `backend/monomorphism.py` compiles all 400 admissible probes through checker, `rustc` and `py_compile` |
| Differential gate | **green** — 120 function cases + 15 whole-program cases across all 6 targets (Python, Rust, Wasm, Interp, TS, Go: 135 runs each), 0 disagreements |
| Measurement harness | **working** (Phase 9) — supports whole-program and function modes across all 5 targets (`python`, `typescript`, `rust`, `go`, `interp`) with strict 6-stage lifecycle tracking and offline `--dry-run` |
| In-Memory WASI Runner | **working** (Phase 10) — pure TS zero-dependency in-memory WASI preview1 shim for browser and Node |
| Developer Agent MCP Server | **working** (Phase 11) — stdlib-only JSON-RPC 2.0 MCP server with 78% interface compression |
| Interactive Web Showcase | **working** (Phase 12) — Vite + React 19 + Tailwind technical showcase with live REPL, Quality Doctor, Topology Cockpit, Jailed Sandbox & SQL Studio |
| SkyLoom Mesh & Handoff | **working** — `packages/asl-skyloom`, `asl/coord` nano-format wire default, zero-leak directory jailing, 83.4% token reduction |
| Native ASL Quality Suite | **working** — `packages/asl-lint`, `asl lint` (anti-pattern/smell linter), `asl clone-check` (AST clone detector), `asl fix` (autonomous repair) |
| Native ASL SQL Module | **working** — `packages/asl-sql`, cross-dialect query builder & parameterizer (Postgres, SQLite, MySQL, ClickHouse), DDL/DML generator |
| Native LSP 3.17 Server | **working** — `tools/lsp.py`, `asl lsp`, stdio JSON-RPC 2.0, hover docs, jump-to-definition, virtual projections (@pcp:r-8d8e) |
| Ultra-Nano Syntax & Transcoder | **working** — single-token density (`:f`, `:c`, `:d`, `:x`, `:i`, `Str`, `I64`, `dfs`, `dfe`, `df`, `mt`), `asl transcode` (@pcp:d-1eed) |
| In-Memory Jailed Sandbox | **working** — `tools/sandbox_runner.py`, `asl run --jail`, strict memory caps, execution deadlines, telemetry |
| Native Schema Codec | **working** — `packages/asl-codec`, algebraic JsonValue serializer, zero-dependency data interchange |
| Self-Hosted ASL Parser | **working** — `packages/asl-parser` lexer/reader/AST in pure ASL; `asl parse` CLI + native-vs-Lark latency/memory benchmark (`tools/native_parser.py`); lexer scanner is iterative (fold over `string-chars`), so all 37 `packages/**/*.asl` parse without recursion overflow (`tools/tests/test_native_parse_all.py`: 38 passed) |
| Pre-Commit Verification | **15/15 gates green** (re-measured 2026-09-03) — Grammar, Closure (107/107), Prelude, Checker, check_corpus, monomorphism, differential, pytest (369), parser tests (8), ASL Lint (37/37 files), Clone Check (10.02% < 15%), check-tokens, deploy_check, PCP actualize (0 breaches), `npm run build:web` |
| Unit tests | **377 pass** — `backend/tests`, `bench/algo`, `checker/tests`, `tools/tests` (369, incl. 38 parse-all + 6 native-parser CLI), `packages/asl-parser/tests` (8) |

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

1. ~~**Reference interpreter**~~ — **done** (Phase 5). The corpus executes under a Rust tree-walking
   interpreter over the tree-sitter AST and agrees with python/rust/wasm on stdout/stderr/exit via
   `differential.py`; the code survives into the compiler frontend.
2. ~~**I/O surface**~~ — done, PCP `r-56bf`. Effects are tracked by a marker rather than left
   implicit, so the concurrency question stays open instead of being foreclosed.
3. **Python and JavaScript backends** — the measurement targets. Rust and Go remain the compiler's
   own self-hosting targets and are unchanged as a product goal.
4. **Benchmark harness** — terminal-bench, comparing generated AgentScript transpiled to Python/JS
   against real Python/JS solutions to the same tasks.
5. **Measurement** — see §5. Blocked.
6. **Native backends** — Rust and Go, for self-hosting. Gated behind the checker *and* an
   unrecorded ownership decision (PCP `l-880d`).
6b. **WebAssembly target** — the cheap half is already reachable: the Rust backend's output is
   accepted for `wasm32-unknown-unknown` unchanged, and every rustc-gated corpus fixture produces
   a valid module (magic `0061736d`), so a target arrives with no new code generation. That route
   runs through `backend/rust/rt.rs` and therefore inherited its numeric gap; Phase 2's repairs and
   the Tier-A sweep close it for this target too, and any new numeric helper it needs is compiled
   at every admissible instantiation by the same gate. What is not
   free is everything that makes it *glue*: an interface contract generated from the module header,
   and a decision on how a foreign call's failure crosses that boundary — the same question
   `d-4b8c` answers for host bindings, asked again for a different boundary. Direct Wasm code
   generation, bypassing Rust, is a separate and much larger commitment: it owns memory layout and
   reclamation for recursive unions.
7. **Self-hosting probe** — write the AgentScript lexer in AgentScript. Prediction on record: it needs
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

* **Vocabulary coverage is 107/107 executed, and the metric changed to make that mean
  something.** The old figure counted a call head found by a static scan over the corpus and the
  specification's markdown: it read 38 of 107 while the executed set was 33, and only 21 builtins
  were in both — wrong in both directions, and blind to a call in a branch no case takes.
  `backend/exec_coverage.py` now wraps every Python lowering template in a recorder and runs every
  program the gates execute, so a builtin counts only when its emitted expression is *evaluated*.
  The floor (95%), the ratchet, the per-builtin executed instantiations and the Tier-A probe set
  live in `prelude/coverage.lock`, and every `N`-typed builtin is required to execute at `Int64`
  **and** at `Float64` — the rule that would have caught `/` and `mod`. What is still not proven:
  execution is recorded on the Python side only (the Rust side is compile-gated by
  `monomorphism.py` and compared by `differential.py`), the host errno mappings for
  `already-exists`, `invalid-path`, `interrupted` and `other` are unreachable from a deterministic
  case, and the eight builtins listed under `unproven` have no `defenum`-typed instantiation until
  Phase 1's derives land. PCP `l-3434`.
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
  produced it. Type-application arity was the first such check; `map-key-order` is the second. Both
  are enforced, and §9 has an item for neither. Closing the gap means adding checklist items, which
  is a specification change. PCP `d-bad1`.
* **A `Map` key must be orderable, and the rule is enforced where the key is *determined*, not
  where it is written.** `(Map Float64 V)` type-checked and could lower to no backend: `BTreeMap`
  needs `Ord`, `f64` has no total order, and §6 specifies `map-keys` as sorted. `map-key-order`
  first shipped as a scan over declared type trees, which reads no key that inference supplies —
  `(defun b [(ps (List (Pair Float64 Int64)))] -> Int64 (map-size (map-from-pairs ps)))` checked
  clean and then failed at `rustc` with `error[E0277]: the trait bound f64: Ord is not satisfied`.
  The check now runs in the type layer (`checker/types_.py:map_key_rules`) over every type the walk
  attaches to a source node, so it sees the inferred key, a key fixed by instantiating a generic
  function's type variable at a call site, and a key reached through a user declaration: a record or
  union holding a `Float64` — transitively — derives no `Ord` either, and neither does `IoError`.
  One declaration reaching one unorderable type reports once; the old pass reported a nested
  `(Map (Map Float64 V) W)` twice at the same token.
  **The residual hole, stated rather than described away:** a key that is a *rigid type variable*.
  `(defun {K} build [(ps (List (Pair K Int64)))] -> Int64 (map-size (map-from-pairs ps)))` checks
  clean (`checker/check.py` exit 0) and `rustc` rejects it with `the trait bound K: Ord is not
  satisfied` at the definition, before any instantiation — the backend emits the generic with no
  bound, and the language has no way to write one. Closing it means either emitting `Ord` bounds in
  `backend/to_rust.py` (which moves the error to the caller, where the checker still admits it) or
  narrowing §3 so a `Map` key may not be a type variable. The second is normative text and is owed.
  Forty instantiations across the ten `Map` builtins are narrowed away by `map-key-order` rather
  than repaired, which is what lets Tier A's floor be 100% rather than 100% minus a skip list;
  `.venv/bin/python backend/monomorphism.py` re-derives `candidates: 440 / narrowed: 40 / probes:
  400`. Measured blast radius: `check_file` over all 82 `.agentscript` files in the tree reports
  `map-key-order` on the six `grammar/corpus/semantic/map-*.agentscript` fixtures and nothing else.
  `prelude/HANDBOOK.md:81` carries the headline — "A `Map` key must be orderable: `Float64` is not a
  legal key type" — so the narrowing reaches the artifact a model actually reads, but it does not
  yet say that a record or union reaching a `Float64`, or `IoError`, is refused for the same reason.
  The handbook is generated by `prelude/generate.py`; that widening is owed.
* **"Admissible" means "the checker accepts it", and that is a weaker floor than it reads as.** The
  checker's type system models the specification's types; it does not model the trait obligations a
  lowering carries. Where a backend needs a property of a type argument that §3 never wrote down,
  the checker has no reason to ask for it, and the gate that would catch the difference only
  *compiles* — `py_compile` is a parser, so a Python-side obligation is invisible to it entirely.
  Measured today, on top of the `Map`-key type-variable hole above: `(defun store [(k (List Int64))]
  -> Int64 (map-size (map-set (map-empty) k 1)))` checks clean, `rustc` accepts it (`Vec<i64>` is
  `Ord`), and the Python lowering — a `dict` keyed by a `list` — raises `TypeError: unhashable type:
  'list'` when the function is called. A `Map` key must therefore be *hashable in Python* as well as
  ordered in Rust, and nothing states or checks the first. The narrowing decision is normative and
  is owed; so is the question of whether Tier B should execute a probe rather than compile it.
* **Every operation at `Int32` ignores the width, because the Python lowering table is keyed on the
  builtin name alone.** `backend/to_python.py`'s `LOWER` maps `+` to one template regardless of the
  operand type, so `Int32` arithmetic is emitted as unbounded Python integer arithmetic while Rust
  emits `i32` and traps. §3.1 says an operation whose exact result is not representable in the
  operand type traps, and `Int32` "never wraps and never widens" — the Rust side obeys it and the
  Python side cannot see the question. Measured with `differential.run_python` and
  `differential.run_rust` over a scratch file, all three arithmetic forms diverge at the boundary:
  `(defun bump [(n Int32)] -> Int32 (+ n 1))` at `2147483647` answers `[2147483648]` on Python and
  `panicked at rt.rs:46:1: overflow in addition` on Rust; `(* n n)` at `100000` answers
  `[10000000000]` against `overflow in multiplication`; `(neg n)` at `-2147483648` answers
  `[2147483648]` against `overflow in negation`. The checker accepts all three (`checker/check.py`
  exit 0) and is right to — the program is well-typed and the divergence is in the lowering. Note
  what is *not* broken: an `Int32` **literal** outside the width is now rejected statically
  (`literal-range`, `checker/types_.py:literal_ranges`), which is the half that needed no type
  information at the backend. Closing the rest means `to_python.py` learning the operand type at
  each call site — the checker already computes it and records instantiations for
  `exec_coverage.py`, so the type is available; threading it into the emitter is a phase, not a
  cleanup. The differential gate cannot catch this today because it compares values and a Rust trap
  is not a value; `grammar/corpus/valid/23-numeric.agentscript` asserts the Int64 traps by construction
  and has no Int32 leg. PCP `l-4d92`.
* **`list-sort` over a user union, a `Result` or a record orders by different things on each
  backend, and over a record or a `Map` only one backend can order at all.** Python lowers a union
  case to a tuple whose head is the case *name*, so sorting compares tag strings; Rust lowers it to
  an `enum` whose derived order is *declaration order*. The two agree only when the two orders
  coincide. Measured: `(list-sort (list (err "E") (ok n)))` answers `['errE', 'ok1']` on Python and
  `['ok1', 'errE']` on Rust; with `(defenum Tag (:case zed [] "Z") (:case alpha [] "A"))`,
  `(list-sort (list (alpha) (zed)))` answers `['alpha', 'zed']` on Python and `['zed', 'alpha']` on
  Rust. A record is worse than disagreement: it lowers to a `dict`, and
  `(list-sort (list (P :x n) (P :x 0)))` answers `[0, 3]` on Rust and raises
  `TypeError: '<' not supported between instances of 'dict' and 'dict'` on Python; two `Map` values
  raise the same `TypeError` while Rust sorts `BTreeMap` by its derived order. The mirror case is
  `IoError`, which §3 says has no order: a record holding one sorts fine on Python and `rustc`
  refuses it with `error[E0277]: can't compare Failure with Failure`. The checker accepts every one
  of these (`checker/check.py` exit 0) because `UNORDERED` is consulted for `Map` keys only. Fixing
  it needs a decision — one sort order for user types, presumably declaration order, written into
  §3.2 — and then a Python record representation that *has* an order, which is the same
  type-awareness phase as the `Int32` gap above. Until then `backend/to_rust.py` derives `PartialOrd`
  separately from `Eq, Ord` so the Rust half is at least correct at `Float64`
  (`backend/t/test_float_ordering.py`), and no differential case sorts a user type. PCP `l-5c47`,
  `d-6c04`.
* **A `:field`'s `:default` is type-checked and then lowered by neither backend.** §4.1 says the
  default stands in for a value the constructor omits; `checker/types_.py:field_defaults` checks it
  against the field type, and that is the whole of its life. `(defschema C (:field at Int64 "P"
  :default -1))` with `(.-at (C))` passes `checker/check.py` with exit 0, emits `def C(at)` called
  as `C()` — `TypeError: C() missing 1 required positional argument: 'at'` — and emits `C {  }`,
  which `rustc` rejects with `error[E0063]: missing field at in initializer of C`. No fixture had
  ever omitted a defaulted field: `grammar/corpus/valid/01-basics.agentscript` declares `:default 3` and
  always supplies the field, so both gates stayed green over a feature neither backend has. Closing
  it is a design item on the Rust side, where a struct literal cannot omit a field and the choice is
  between a generated constructor function and `Default` plus functional update. PCP `l-9e13`.
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
