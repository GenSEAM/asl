# ROADMAP.md — AgentScript project state and handoff

Written to be read cold. A session starting from zero should be able to resume from this file
alone, plus `AGENTS.md` for commands and `.pcp/INDEX.md` for recorded intent.

**Last updated:** 2026-09-03 · **Head commit at writing:** `3f0fe6b`, plus an uncommitted
consistency pass over the whole surface — the Nano projection given one source and a §2.1, the
gates widened from the corpus to the shipped packages and the documentation, and several defects
those widened gates immediately found. Every figure below was re-derived by running the command
that produces it.

**Read §6 before trusting anything here.** The gaps listed there are the ones this project knows
about; the ones it did not know about were found by making a gate look somewhere it had not looked.

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
| Conformance gate | **green** — 0 failures across both grammars; `grammar/validate.py` re-derives the fixture counts on every run |
| Closure gate | **green** — no example calls an undefined name: **107/107 builtins evaluated (100%)** against `prelude/coverage.lock` |
| Python backend | **working** — all 32 corpus and benchmark fixtures transpile, `py_compile` accepts every one, participating in differential gate |
| Rust backend | **working** — all 32 corpus and benchmark fixtures transpile, `rustc` accepts every one, `backend/monomorphism.py` compiles all 400 admissible probes |
| TypeScript backend | **working** (Phase 7) — `backend/to_typescript.py` + `backend/ts/rt.ts`, all 32 fixtures transpile, `tsc` accepts every one, participating in differential gate |
| Go backend | **working** (Phase 8) — `backend/to_go.py` + `backend/golang/rt/rt.go`, all 32 fixtures transpile, `go vet` accepts every one, participating in differential gate |
| WebAssembly target | **working** (Phase 4) — `wasm32-wasip1` under `node:wasi`, participating in differential gate in program mode |
| Reference interpreter | **working** (Phase 5) — Rust tree-walking interpreter (`crates/agentscript-interp/`), participating in differential gate in both program and function modes |
| Semantic checker | **working** — all thirteen rules of §9, plus §4.1 construction, type checking, type resolution across a module boundary, and named checks (`type-arity`, `map-key-order`) |
| Semantic gate | **green** — 0 failures: the valid corpus and the search-path modules check clean, every semantic fixture is rejected under the rule its header names, and all 40 `.asl` files under `packages/` check clean |
| I/O surface | **working** — read/write, files, `IoError`, tracked effects, `main` |
| Tier-A monomorphism gate | **green** — `backend/monomorphism.py` compiles all 400 admissible probes through checker, `rustc` and `py_compile` |
| Differential gate | **green** — 129 function cases + 18 whole-program cases across all 6 targets (Python, Rust, Wasm, Interp, TS, Go), 0 disagreements |
| Measurement harness | **working** (Phase 9) — supports whole-program and function modes across all 5 targets (`python`, `typescript`, `rust`, `go`, `interp`) with strict 6-stage lifecycle tracking and offline `--dry-run` |
| In-Memory WASI Runner | **working** (Phase 10) — pure TS zero-dependency in-memory WASI preview1 shim for browser and Node |
| Developer Agent MCP Server | **working** (Phase 11) — stdlib-only JSON-RPC 2.0 MCP server with 78% interface compression |
| Interactive Web Showcase | **working** (Phase 12) — Vite + React 19 + Tailwind technical showcase with live REPL, Quality Doctor, Topology Cockpit, Jailed Sandbox & SQL Studio |
| SkyLoom Mesh & Handoff | **working** — `packages/asl-skyloom`, `asl/coord` nano-format wire default, zero-leak directory jailing, 83.4% token reduction |
| Native ASL Quality Suite | **working** — `packages/asl-lint`, `asl lint` (anti-pattern/smell linter), `asl clone-check` (AST clone detector), `asl fix` (autonomous repair) |
| Native ASL SQL Module | **working** — `packages/asl-sql`, cross-dialect query builder & parameterizer (Postgres, SQLite, MySQL, ClickHouse), DDL/DML generator |
| Native LSP 3.17 Server | **working** — `tools/lsp.py`, `asl lsp`, stdio JSON-RPC 2.0, hover docs, jump-to-definition, virtual projections (@pcp:r-8d8e) |
| Nano projection & transcoder | **working** — short spellings (`df`, `dfs`, `dfe`, `mt`, `:d`, `:x`, `:i`, `:a`, `:f`, `:c`, `Str`, `I64`, `F64`), `asl transcode`, `asl view` (@pcp:d-1eed, `d-ddc2`). **It buys 3.6% of bytes and 0.0% of tokens** — see §6 and `bench/token_projection.py` |
| In-Memory Jailed Sandbox | **working** — `tools/sandbox_runner.py`, `asl run --jail`, strict memory caps, execution deadlines, telemetry |
| Native Schema Codec | **working** — `packages/asl-codec`, algebraic JsonValue serializer, zero-dependency data interchange |
| Self-Hosted ASL Parser | **working** — `packages/asl-parser` lexer/reader/AST in pure ASL; `asl parse` CLI + native-vs-Lark latency/memory benchmark (`tools/native_parser.py`); lexer scanner is iterative (fold over `string-chars`), so all 37 `packages/**/*.asl` parse without recursion overflow (`tools/tests/test_native_parse_all.py`: 38 passed) |
| Nano projection | **one source** — `prelude/prelude.json`'s `projection` section generates §2.1, both grammars' spelling tables, the handbook, both `llms.txt` copies and the harness skill |
| Documentation examples | **gated** — `tools/doc_examples.py` parses every fenced AgentScript block in the repository's Markdown; other languages get their own fence, deliberate non-examples opt out with a stated reason |
| Package sources | **gated** — `checker/gate.py` checks all 40 `.asl` files under `packages/`, not the corpus alone |
| Pre-Commit Verification | **16 gates, and the hook now runs all of them.** It ran six while this table claimed fifteen; the list lives in `tools/hooks/pre-commit` and the banner counts it, so the two cannot disagree again. Added today: the documentation-example gate, two token-measurement locks, and the package half of the semantic gate |
| Unit tests | **838 pass** — `backend/tests`, `bench/algo`, `checker/tests`, `tools/tests`, `packages/asl-parser/tests` |

### Documents, in reading order for a newcomer

0. `prelude/prelude.json` — the vocabulary, authoritative. The specification tables and the
   handbook are generated from it; nothing else may restate it.
1. `AGENT_SPEC_CORE.md` — the language. **Normative** for the forms. Start here.
1b. `prelude/HANDBOOK.md` — generated agent-facing reference, 12,311 characters, ~3,078 tokens at
   the project's chars/4 approximation. This is the artifact that goes into a prompt.
2. `ROADMAP.md` — this file.
3. `EXPERIMENT.md` — pre-registered measurement protocol and pass/fail thresholds. **Read §9
   first**: five amendments supersede parts of the body, and the most recent records that the I/O
   dependency an earlier one called blocking has been met.
4. `RESEARCH_REPORT.md` — evidence on whether the concept is viable at all. Read §3 and §5.
5. `SPEC_REVIEW.md` — critique of the original v0 draft; explains why v0.2 looks as it does.
6. `AGENT_SPEC.md` — the original v0 draft, **frozen, superseded, kept only for provenance**.

### Which document governs what

Several documents have called themselves normative, and until this was written down they could
disagree with no way to say which was wrong.

| Document | Governs |
|---|---|
| `AGENT_SPEC_CORE.md` | the language: forms, types, the projection (§2.1), the vocabulary (§6) |
| `docs/ASN_SPEC.md` | data payloads — AgentScript Notation |
| `docs/AGENTIC_PROTOCOL.md` | the wire: frames, dialects, error codes |
| `prelude/prelude.json` | the vocabulary and the projection, as data; the four above quote it |

`docs/CONTEXT_ECONOMY_GUIDELINES.md`, `docs/DATA_REPRESENTATION_MATRIX.md`, `docs/BEST_PRACTICES.md`,
`docs/NANO_SYNTAX.md` and `docs/COMPACT_SYNTAX.md` are **advisory**. They are normative for nothing,
their examples are gated by `tools/doc_examples.py`, and where one disagrees with a document above,
the document above wins and the advisory one is the bug.

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
* **Deliberately excluded:** agents, UI, async, FFI, JSON serialization. **I/O is in** — nine
  builtins, the closed union `IoError`, effects tracked by a `!` marker on the signature, and
  `main` as the entry point (§4.0). It was excluded while the benchmark was pure functions and
  stopped being defensible when the unit of measurement became a whole working program.

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

**Next: the harness's whole-program mode.** The measurement harness supports whole-program and
function modes across all five targets (see the table in §2), but `bench/harness/run.py` still
drives an entry function with cases and `bench/tasks/histogram.json` is a pure-function task, so
the terminal-bench shape chosen in `EXPERIMENT.md` amendment 2026-08-20-b has no task written
against it. The mode exists; nothing uses it. That is the gap, and it is smaller than the previous
wording ("not implemented yet") suggested.

### Why it came before the backends

The conformance gate proves only that two parsers agree on *shape*. Located evidence puts the large
majority of failures in LLM-generated code at the type level, with grammar-level constraints
capturing only a small fraction of achievable error reduction (`RESEARCH_REPORT.md` §5) — so
building backends first would have optimised the part already known to be small.

Fixtures for semantic-only rules live in `grammar/corpus/semantic/`. They **must parse** — a
grammar that rejects them is over-tight — and each must be *rejected by the checker under the rule
its leading `"expect:"` note names*. A fixture rejected for the wrong reason fails the gate: that is how
the reserved-prefix rule looked defended while nothing enforced it (PCP `c-099a`). A stronger
note, `"expect-only:"`, asserts the fixture reports that code *and nothing else* — 17 of the 34
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
3. ~~**Python and JavaScript backends**~~ — **done**. Python, TypeScript, Go and Rust all
   transpile the corpus and are compile-gated by their own toolchains; all six targets participate
   in the differential gate. Rust and Go remain the compiler's own self-hosting targets and are
   unchanged as a product goal.
4. **Benchmark harness** — terminal-bench, comparing generated AgentScript transpiled to Python/JS
   against real Python/JS solutions to the same tasks.
5. **Measurement** — see §5. Blocked.
6. **Native backends** — Rust and Go **exist and compile the corpus**; what remains gated is not
   the backend but the ownership model behind it (PCP `l-880d`): the Rust output uses a
   conservative clone-at-every-use strategy chosen instead of a model. The cost of that strategy is
   now measurable rather than hypothetical.
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
7. **Self-hosting probe & validation migration (@pcp:d-8d4c)** — **done & active**. The pure ASL lexer, reader,
   and AST (`packages/asl-parser`) are built, passing all 399 parity tests (`test_native_parity.py`) and parsing
   all package sources without stack overflow. Immediate milestone: migrate all ecosystem validation gates
   (`validate.py`, `doc_examples.py`, `closure_audit.py`, `checker/gate.py`) and retiring Lark completely.

---

## 5. Blocked — needs the owner

Measurement cannot start, now for two independent reasons.

**Language:** resolved. Core has I/O (PCP `r-56bf`), and `EXPERIMENT.md` amendment 2026-09-03-a
records it against the amendment that called it blocking. What remains on this side is not the
language but the tasks: the harness has a whole-program mode and no task written against it.

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

Six entries below were added on 2026-09-03 by widening two gates from the corpus to the shipped
packages and the published prose. Every one of them had been green in every gate the project ever
ran, which is the lesson: **a gate that reads one directory measures that directory.**

* **A string literal containing a newline lowers to a syntax error on three of four backends.**
  §2's `string-lit` puts no constraint on the characters between the quotes, and each backend passes
  the source token through verbatim, so a raw newline lands inside the target's quotes. Rust
  survives — it allows multi-line string literals — and Python, TypeScript and Go do not: measured,
  `check_corpus.py` reports `SyntaxError: unterminated string literal`, `tsc rejected the output`
  and `go vet rejected the output` for the same fixture. The checker exits 0 and both grammars
  accept it, so nothing sees it before the target compiler does. It was academic while strings were
  data; it is on the critical path now that a **note is a string literal**, because notes are
  multi-line as a matter of course. **Closed**: the four literal emission sites escape a newline on
  the way out, `grammar/corpus/valid/34-multiline-strings.agentscript` compiles it on every target,
  and `33-notes.agentscript` carries multi-line notes again.
* **`;` comments are retired; a comment is a free-standing string literal bound to nothing.**
  `;` is gone from `AGENT_SPEC_CORE.md` §2 and both core grammars, and the native lexer rejects it.
  A comment is now a **note** — a string literal bound to nothing, admitted at top level and inside
  a declaration body and erased at every backend. The `; expect:`/`; expect-only:` headers that
  drove `checker/gate.py` became leading `"expect:"`/`"expect-only:"` notes, and `; run:` assertions
  moved to `<fixture>.run` sidecars read by `check_corpus.py`. ASN keeps `;` on its own authority —
  a bare string is a data value there, so the note is not unambiguous — with its `COMMENT` terminal
  outside the shared-core block and the divergence documented in `docs/ASN_SPEC.md`. PCP `l-a250`.
* **The website publishes numbers with no gate behind them, which `DESIGN.md` §5 forbids.** A sweep
  of `web/src` finds `80%`, `0.038ms`, `0.05ms`, `78%`, `70%`, `68.4%`, `160%`, `97%` and others.
  Two of them are real — `83.4%` is the SkyLoom handoff reduction and `78%` the MCP interface
  compression, both named in §2 above — and the rest trace to nothing. `bench/token_frames.py` and
  its lock file are the shape a published number has to take: a command anyone can re-run, and a
  gate that fails when the figure moves. **Not fixed here**: a parallel session is editing `web/`
  right now, and two sessions rewriting the same components is how work is lost. The rule already
  exists; what is missing is a gate that enforces it over `web/src` the way `check:tokens` enforces
  the palette.
* **Lark is being retired, and two of this project's rules still assume it is permanent.**
  `AGENTS.md`'s "both grammars must change together" and `grammar/validate.py`'s cross-parser parity
  are written around Lark and tree-sitter as co-equal. Lark drives constrained decoding
  (`EXPERIMENT.md` arm C), tree-sitter drives tooling, and the self-hosted parser in
  `packages/asl-parser` is the one being invested in. `tools/doc_examples.py`, added today, parses
  with Lark and will have to move. Nothing is broken; the rules just describe a world that is
  ending, and whoever retires Lark has to rewrite them rather than discover them.
* **The Nano projection saves bytes and does not save tokens, and the whole justification for it was
  the tokens.** Every document that describes the projection, and the "single-token hygiene"
  standard behind it, argues from token cost. Nothing had measured it. Measured now, under
  `cl100k_base`, over every fixture in `grammar/corpus/valid`, transcoded by the real transcoder:

  | | verbose | Nano |
  |---|---|---|
  | bytes | 58,175 | 56,091 (**-3.6%**) |
  | tokens | 15,931 | 15,931 (**0.0%**) |

  Per spelling it is a tie in all fourteen cases, because a BPE vocabulary already encodes the long
  form cheaply: `(defun` and `(df` are one token each, ` :export` and ` :x` two each, ` Float64`
  and ` F64` two each, ` String` and ` Str` one each. On a realistic hand-written module Nano came
  out **half a percent worse**. `bench/token_projection.py` is the measurement and
  `bench/token_projection.lock` pins it.

  **What this does and does not overturn.** It does not touch the wire and data formats: removing
  *structure* — quotes around keys, commas, braces, field names repeated on every row — genuinely
  saves tokens, and `bench/token_frames.py` measures a command frame at 18 tokens against JSON's 51,
  **-64.7%**. Structural compaction works; abbreviating identifiers does not. Those two claims were
  being made in the same breath and only one of them is true.
  Nano keeps a defensible rationale — fewer bytes on disk and on the wire, less visual noise, and it
  is now what the toolchain generates (PCP `d-ddc2`) — but **the token argument must stop being
  made** until someone re-measures under the tokenizer of the model actually being served. This
  repository has no such measurement, and `cl100k_base` is a GPT vocabulary, not every model's.
* **A module's declared name and the path an importer must write are two different things, and
  nothing checks that they agree.** Measured over all 37 package modules: **all 37 diverge**.
  `packages/asl-sh/src/core/process.asl` declares `asl-sh/process` and is reachable only as
  `core/process`; `packages/asl-parser/src/lexer.asl` declares `asl-parser/lexer` and is reachable
  only as `lexer`; nine modules declare `asl-*/test`. Resolution goes by file path (`grammar/modules.py`
  `find`), while §8 mangles a qualified name by its **defining module path** — so the two notions of
  identity are already both load-bearing and already disagree. Nothing has broken yet because no
  mangling collision has occurred. Closing it means either renaming every package module to match
  its path or making resolution honour the declared name, and the second reintroduces the "one
  definition, two names" problem §8 exists to prevent. **Owner decision owed.** Until then
  `checker/gate.py` and `asl check` both resolve by path across every package's `src/`, so at least
  they grade the same program.
* **A builtin name in value position typed clean and lowered to a name that does not exist.** §6
  gives a builtin a type, not a value, and nothing said so. `(map string-upper xs)` checked clean
  and emitted `string_upper(_x)` on Python and `string_upper.clone()` on Rust — builtins are lowered
  as inline templates, never as functions, so neither name is defined in its own output. The same
  hole silently accepted a common typo: `==` is not an operator, so `(== a 0.0)` lexes as `=` applied
  to `=`, `a` and `0.0`, and lowered to `_agentscript.eq(=, a)` and `(= == a.clone())`. Two packages
  shipped it. **Closed** by the `builtin-reference` check; fixtures `builtin-as-value.agentscript`
  and `doubled-equals.agentscript`. PCP `c-5d55`.
* **Builtin call arity was unchecked, and it dropped arguments rather than reporting.**
  `(and a b c)` checked clean and the Python backend emitted `(a and b)`, discarding the third
  operand. Found in the self-hosted lexer, where four of `is-symbol-char`'s six clauses had never
  run. The exemption was written for `list`, which is variadic as a constructor and nullary as a
  pattern — but a pattern never reaches a call node, so only the variadic case needed it.
  **Closed**; arity now comes from §6's declared signature. Fixture `builtin-arity.agentscript`.
  PCP `c-eddd`.
* **`:json-case` was normative since v0.2 and accepted by neither grammar.** §4.1 specifies it;
  `(defschema Point :json-case camel ...)` did not parse. The specification defined a form that
  could not be written, and no fixture existed to notice. **Closed** in both grammars, in header
  position; fixture `32-json-case.agentscript`, parked on `coverage.lock`'s unexecuted list because
  Core ships no serializer to execute it. PCP `d-1671`.
* **The closure audit did not count a `defenum` case as a definition.** It collected `defun` names
  only, so the first corpus fixture to construct a user union case reported every one of its cases
  as an undefined call head. No fixture had, until one did. **Closed.**
* **Three of four backends emitted Nano type aliases verbatim.** A module written with `I64` lowered
  to `pub v: I64` on Rust, `readonly v: I64` on TypeScript and `v I64` on Go; `rustc`, `tsc` and
  `go vet` reject all three. Only the Python backend resolved aliases. The corpus contained no
  Nano-spelled fixture, so `check_corpus.py`, `differential.py` and `monomorphism.py` had only ever
  seen the long spelling. **Closed**; alias resolution has one source and the corpus now carries
  Nano fixtures.
* **The published prose taught a language that does not exist.** The `llms.txt` the website served
  differed from the repository's and taught `(:export ...)`, `Ok`/`Err`, `len` and `zip-with`;
  `llms.txt` and both skill files listed `sqrt`, `s/concat`, `l/map`, `m/get` and `file/read`, none
  of which are in the vocabulary; `docs/BEST_PRACTICES.md` taught `defextern`; a blog post showed a
  `defun` with no body; the README asserted four token counts that were wrong in every position
  (42 / 25 / 11 / 9 against a measured 51 / 34 / 27 / 18). **Closed**: those artifacts are generated
  from `prelude/prelude.json`, `tools/doc_examples.py` parses every fenced example, and
  `bench/token_frames.py` pins the one figure the README still publishes. PCP `c-1c5a`.
* **`packages/asl-mem` could never have run.** Its `vector-norm` called `sqrt` and `list-zip-with`,
  neither of which exists. It is now written in the vocabulary — a Newton-Raphson square root at a
  fixed iteration count — and agrees with `math.sqrt` to within one ULP across the range tested.
  The underlying gap remains: **the language has no square root**, and a numeric library that needs
  one must write it. Whether §6 should gain one is an open question, not an oversight.


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
