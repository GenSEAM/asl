# Project Agent Instructions

Activate the `pcp` skill and follow its instructions.

Read `ROADMAP.md` first for project state and the next step. `AGENT_SPEC_CORE.md` is the
normative language definition.

## Project Conventions

### Setup

Python tooling runs from a project-local virtualenv; the tree-sitter CLI is a local dev dependency.

```bash
python3 -m venv .venv && .venv/bin/pip install lark
npm install
```

Rust is installed but the `~/.cargo/bin` shims are broken — they point at a `rustup-init` that no
longer exists. Invoke through `rustup run stable <cmd>`, or fix the shim with
`ln -sf /opt/homebrew/bin/rustup ~/.cargo/bin/rustup`.

### Gates — both must pass before any commit

```bash
.venv/bin/python grammar/validate.py
```

Parses every corpus fixture under **both** grammars. Fails on a wrong verdict *and* on the two
grammars disagreeing with each other. `corpus/valid` must parse, `corpus/invalid` must be
rejected, `corpus/semantic` must parse — those fixtures violate rules only a checker can enforce,
and a grammar that rejected them would be over-tight.

```bash
.venv/bin/python grammar/closure_audit.py
.venv/bin/python prelude/generate.py --check
.venv/bin/python checker/gate.py
.venv/bin/python backend/check_corpus.py
.venv/bin/python backend/monomorphism.py
.venv/bin/python backend/differential.py
.venv/bin/python -m pytest backend/t bench/algo checker/t -q
```

The closure gate extracts call heads with the project's own tree-sitter grammar and fails if any
names something neither in the vocabulary nor bound locally. The specification's claim to be closed
is only worth what this gate enforces; it was false once already.

It also reports **executed** vocabulary coverage, computed by `backend/exec_coverage.py` rather than
by a scan: every Python lowering template is wrapped in a recorder and every program the gates run is
run, so a builtin counts only when its emitted expression is evaluated. A call head in a branch no
case takes counts for nothing — the previous, scanned figure could be moved by eleven with nothing
executed. The floor, the ratchet, the per-builtin executed instantiations and the Tier-A probe set
are data in `prelude/coverage.lock`; run `backend/exec_coverage.py --write` to record a new figure
deliberately, in the commit that earns it.

`monomorphism.py` is the other half. It generates every admissible (builtin × concrete
instantiation) from `prelude.json`, checks them in one pass and compiles them with one `rustc` and
one `py_compile`. "Exercised" never meant "the lowering works" — it meant "the lowering works at the
one type someone happened to use": `/` and `mod` were inside the exercised set while their runtime
helpers took `i64` alone. Effectful, variadic and higher-order builtins are excluded, each recorded
with its reason in the lock, because an exclusion nothing writes down is a skip list.

The generator check fails when a generated artifact is stale, and when a lowering template will
not format at its declared arity — literal braces must be doubled in `prelude.json`, or they are
read as placeholders and fail far from their cause.

`check_corpus.py` transpiles every corpus program. Parsing proves a program is well-formed;
transpiling proves the backend covers the forms the grammar admits. Those two drift apart
silently otherwise.

`checker/gate.py` runs the semantic checker over both corpora: `corpus/valid` must check clean and
every `corpus/semantic` fixture must be rejected **under the rule its `; expect:` header names**.
Asserting the code matters more than asserting rejection — the reserved-prefix fixture once passed
because an unrelated lexical rule rejected it, which removed the pressure to write the real check.

`check_corpus.py` invokes `rustc` on the Rust output, and `py_compile` on the Python output, rather
than trusting the transpiler's exit code. It did not, once, and every fixture passed while the Rust
backend emitted a wildcard for list destructuring that `rustc` rejects — and the Python side had
the same hole until the module fixture was caught lowering a qualified name to `s/concat(...)`.

`differential.py` runs one AgentScript source through every backend and fails if they disagree.
Portability is a claim, not a property: Python and JavaScript already differ on `2**53+1` and on
rounding a half, so equivalence exists only where it is enforced.

It has two modes. The function mode calls an entry and compares returns; the **program mode** runs a
whole program and compares stdout *and* exit status, including a failing path. That second mode is
what checks the I/O surface: each runtime derives its `IoError` case independently — from `errno` on
Python, `ErrorKind` on the Rust targets (native and the `wasm32-wasip1` arm under `node:wasi`) — so
nothing but running them proves they agree; the Wasm arm caught a raw-errno mapping that is Unix on
one target and WASI on the other (PCP `c-7b9e`). It is also the only gate that has ever caught a
defect in how one form nests inside another (PCP `c-15f3`).

`backend/t` runs AgentScript source through the transpiler and executes the result, asserting semantics
taken from the specification — not from observing what the transpiler happened to emit.

`checker/t` covers the type layer's internals. A unifier that accepts everything leaves every gate
green, so the pieces whose failure is silent are tested directly rather than through a verdict.

### The vocabulary has one source

`prelude/prelude.json` is authoritative. The specification's §6 tables and `prelude/HANDBOOK.md`
are **generated** — editing them by hand is wasted work that the `--check` gate will reject.

```bash
.venv/bin/python prelude/generate.py
```

`HANDBOOK.md` is what goes into an agent's prompt, not the full specification: it is the same
vocabulary at roughly 2,600 tokens against 6,500, and the prompt is resent on every call, so this
dominates the cost of a run.

### Regenerating the parser

After editing `grammar/tree-sitter-agentscript/grammar.js`:

```bash
cd grammar/tree-sitter-agentscript && ../../node_modules/.bin/tree-sitter generate
```

`src/` is generated and git-ignored. **Both grammars must change together** — `agentscript.lark` drives
constrained decoding, `grammar.js` drives tooling, and silent drift means they enforce different
languages.

### Structural search

```bash
cd grammar/tree-sitter-agentscript
../../node_modules/.bin/tree-sitter query queries/searches.scm ../corpus/valid/06-module.agentscript
```

Queries address node parts by field name, which is why the grammar carries `field()` annotations.

### Conventions

- Language identifiers are kebab-case; types are PascalCase; `agentscript-` is a reserved prefix.
- Benchmark task translations are written **by hand**, never generated by a model — a
  model-written translation contaminates the measurement.
- Credentials live in the environment only. Never commit a key, an endpoint with embedded
  credentials, or a `.env`.
- `EXPERIMENT.md` is pre-registered: amendments must be dated and must state whether they were
  made before or after seeing results.
