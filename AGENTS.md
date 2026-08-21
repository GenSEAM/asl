# Project Agent Instructions

Activate the `pcp` skill and follow its instructions.

The language is **AgentScript**; every searchable identifier — repository, CLI, skill, tags — is
`as-lang`, and source files are `.as`. The old spellings (`AgentS`, `.agents`) survive only in the
frozen `AGENT_SPEC.md`.

Read `ROADMAP.md` first for project state and the next step. `AGENT_SPEC_CORE.md` is the
normative language definition. `.claude/skills/as-lang/SKILL.md` is the short working loop for
writing `.as` and is the right thing to read before editing source.

## Project Conventions

### Setup

Python tooling runs from a project-local virtualenv; the tree-sitter CLI is a local dev dependency.

```bash
python3 -m venv .venv && .venv/bin/pip install lark pytest
npm install
cd grammar/tree-sitter-as-lang && ../../node_modules/.bin/tree-sitter generate && cd -
.venv/bin/python backend/to_python.py backend/t/smoke.as > backend/t/smoke.py
```

The last line is not optional and was undocumented for a while: `backend/t/smoke.py` is a
generated, git-ignored artifact, and `pytest` fails at import without it.

Rust is installed but the `~/.cargo/bin` shims are broken — they point at a `rustup-init` that no
longer exists. Invoke through `rustup run stable <cmd>`, or fix the shim with
`ln -sf /opt/homebrew/bin/rustup ~/.cargo/bin/rustup`.

Swift comes from the Xcode command line tools; `swiftc` is on `PATH` and needs no wrapper. Kotlin
is a priority target with no toolchain here yet — `brew install kotlin` before writing that
backend, and until then do not add a Kotlin column that reports `skipped` on every row.

### Gates — both must pass before any commit

```bash
.venv/bin/python grammar/validate.py
```

Parses every corpus fixture under **both** grammars. Fails on a wrong verdict, on the two grammars
disagreeing with each other, *and* on them agreeing to accept a file while reading it differently:
it compares the qualified names each grammar finds. That last check is not hypothetical —
`(s/concat a b)` parsed as a four-argument call to `s` under Lark and as a call to `s/concat` under
tree-sitter, and comparing verdicts could never have seen it. `corpus/valid` must parse, `corpus/invalid` must be
rejected, `corpus/semantic` must parse — those fixtures violate rules only a checker can enforce,
and a grammar that rejected them would be over-tight.

It also parses every fenced example in `prelude/HANDBOOK.md`. That artifact goes into a prompt and
nothing used to check it, which is how it came to show `pl/read_csv` — a name the identifier rule
cannot lex. A wrong example in the one document an agent reads is worse than no example.

```bash
.venv/bin/python checker/check.py grammar/corpus/valid examples lib backend/t
.venv/bin/python checker/check.py --coverage --min-coverage 100 grammar/corpus/valid examples lib
.venv/bin/python grammar/closure_audit.py
.venv/bin/python prelude/coverage_audit.py
.venv/bin/python prelude/generate.py --check
.venv/bin/python backend/check_corpus.py
.venv/bin/python backend/differential.py
.venv/bin/python bench/harness/run.py --dry-run
.venv/bin/python -m pytest backend/t bench/algo tools/bindgen/t checker/t -q
```

The dry run exercises the harness without an endpoint or a key, and it is the only gate that
touches the measurement path at all.

The closure gate extracts call heads with the project's own tree-sitter grammar and fails if any
names something neither in the vocabulary nor bound locally. The specification's claim to be closed
is only worth what this gate enforces; it was false once already.

`checker/check.py` enforces the rules of §9 that no grammar can express — name resolution, types,
exhaustiveness, effects, the foreign boundary, import cycles. Fourteen of the fifteen; the
fifteenth is delimiter balance, which the grammars own. `--rules` prints the split, `--json` emits
one diagnostic shape for every tool the CLI grows.

The type layer **fails open**: a construct it cannot type is silent rather than reported, because a
checker that fires on the programs the handbook teaches is worse than none. That makes "checked and
clean" indistinguishable from "declined to look", so `--coverage` measures it and the gate holds
the floor at 100%. Every expression in the corpus is typed today; a new form the layer cannot
handle breaks that gate instead of passing quietly.

Valid corpus and examples must come back with **zero** diagnostics; the nine fixtures in
`grammar/corpus/semantic/` must each be caught by their own rule, which `checker/t` asserts by
rule number rather than by count — a fixture caught by the wrong rule is a test passing for the
wrong reason.

The coverage gate is the converse of the closure gate: it fails when a *declared* builtin appears
in no example. An example is what an agent learns a call shape from, so a name shown only in a
table is close to an absent one (PCP `l-3434`). Sources are `grammar/corpus/valid`, `examples/`,
`bench/` and `backend/t`.

The generator check fails when a generated artifact is stale, and when a lowering template will
not format at its declared arity — literal braces must be doubled in `prelude.json`, or they are
read as placeholders and fail far from their cause.

`check_corpus.py` transpiles every corpus program **and everything under `examples/`**. Parsing
proves a program is well-formed; transpiling proves the backend covers the forms the grammar
admits. Those two drift apart silently otherwise. An example that does not compile teaches a call
shape the target rejects, which is why the example tree is gated and not merely present.

`check_corpus.py` invokes `compile()`, `rustc` and `swiftc` on their backends' output rather than
trusting the transpiler's exit code. It did not, once, and every fixture passed while the backend
emitted a wildcard for list destructuring that `rustc` rejects. The Python column had the same
hole for longer, because Python was the backend with no compiler to invoke: it emitted
`s(/, concat, ...)` for every qualified name and the gate said `ok`. A fixture a backend cannot
lower is skipped whole, in both its columns — a transpile reported `ok` whose output no compiler
ever saw is the same failure wearing a different hat.

A module carrying a `defextern` names one ecosystem, so a backend for another target must refuse
it. `REFUSE` in that file asserts the refusal rather than skipping the fixture: a refusal that
silently stopped happening would read as coverage.

`differential.py` runs one AgentScript source through every backend — Python, Rust and Swift — and
fails if they disagree. Portability is a claim, not a property: Python and JavaScript already
differ on `2**53+1` and on rounding a half, so equivalence exists only where it is enforced. What
it does not reach is arithmetic overflow, where the three backends genuinely differ and no case
exercises it (`EXPERIMENT.md` amendment `2026-08-21-b`).

`backend/t` runs AgentScript source through the transpiler and executes the result, asserting semantics
taken from the specification — not from observing what the transpiler happened to emit.

### The vocabulary has one source

`prelude/prelude.json` is authoritative. The specification's §6 tables and `prelude/HANDBOOK.md`
are **generated** — editing them by hand is wasted work that the `--check` gate will reject.

```bash
.venv/bin/python prelude/generate.py
```

`HANDBOOK.md` is what goes into an agent's prompt, not the full specification, which is several
times longer. Measured at **4,531 tokens** on 2026-08-21, up from about 2,600 before it covered
I/O and the foreign boundary — the prompt is resent on every call, so this number dominates the
cost of a run. Keep it under 5,000, and measure rather than estimate when it changes.

Adding a builtin means a lowering for all four targets (`py`, `js`, `rs`, `sw`) *and* an example,
or the coverage gate fails. Adding a keyword terminal to either grammar also means adding it to
`FORM_KW` in all three backends, or `kids()` leaves it in the child list and the declaration
mis-parses.

### Regenerating the parser

After editing `grammar/tree-sitter-as-lang/grammar.js`:

```bash
cd grammar/tree-sitter-as-lang && ../../node_modules/.bin/tree-sitter generate
```

`src/` is generated and git-ignored. **Both grammars must change together** — `as-lang.lark` drives
constrained decoding, `grammar.js` drives tooling, and silent drift means they enforce different
languages.

### Building a program with an entry point

```bash
.venv/bin/python backend/to_rust.py mod.as > prog.rs
cp backend/rust/rt.rs . && rustup run stable rustc --edition 2021 -o prog prog.rs

.venv/bin/python backend/to_swift.py mod.as > prog.swift
cp backend/swift/rt.swift . && swiftc -o prog rt.swift prog.swift
```

**Never name the generated Swift file `main.swift`.** Swift treats that filename as top-level code
and then rejects the `@main` the backend emits for `defentry`.

### Structural search

```bash
cd grammar/tree-sitter-as-lang
../../node_modules/.bin/tree-sitter query queries/searches.scm ../corpus/valid/06-module.as
```

Queries address node parts by field name, which is why the grammar carries `field()` annotations.

### Conventions

- Language identifiers are kebab-case; types are PascalCase; `as-` is a reserved prefix, and the
  entry point a backend emits (`as-entry`) is its first user.
- A foreign function is named in kebab-case like everything else and reaches the host through §8
  mangling; `:symbol` is for the spellings mangling cannot reproduce. Do not hand-write a
  `defextern` that `tools/bindgen/from_pyi.py` can generate.
- Benchmark task translations are written **by hand**, never generated by a model — a
  model-written translation contaminates the measurement.
- Credentials live in the environment only. Never commit a key, an endpoint with embedded
  credentials, or a `.env`.
- `EXPERIMENT.md` is pre-registered: amendments must be dated and must state whether they were
  made before or after seeing results.
- `bench/tasks/` holds **generation** tasks and nothing else — `bench/harness/run.py` globs it and
  asks a model to solve everything in it. Fixtures with known answers live in `bench/differential/`;
  putting one under `tasks/` spends the cap generating a solution already checked in.
