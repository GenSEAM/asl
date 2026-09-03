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
.venv/bin/python bench/token_frames.py --check
.venv/bin/python bench/token_projection.py --check
.venv/bin/python tools/doc_examples.py --quiet
.venv/bin/python backend/check_corpus.py
.venv/bin/python backend/monomorphism.py
.venv/bin/python backend/differential.py
.venv/bin/python -m pytest backend/tests bench/algo checker/tests tools/tests -q
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

`checker/gate.py` runs the semantic checker over both corpora **and over every `.asl` file under
`packages/`**: `corpus/valid` must check clean and every `corpus/semantic` fixture must be rejected
**under the rule its leading `"expect:"` note names**. Asserting the code matters more than asserting
rejection — the reserved-prefix fixture once passed because an unrelated lexical rule rejected it,
which removed the pressure to write the real check.

The `packages/` half was added because the corpus is not the shipped code. While the gate read the
corpus alone, `packages/asl-mem` called `sqrt` and `list-zip-with` — neither of which exists — and
two packages contained `(== a b)`, which lexes as `=` applied to `=`, and lowered to
`_agentscript.eq(=, a)` on Python and `(= == a.clone())` on Rust. Every gate was green throughout.
Package sources resolve against their own `src/` and `src/core/`, which is what the test harnesses
already do; a gate that resolved differently would grade a different program than the one that runs.

`doc_examples.py` parses every AgentScript example fenced ```` ```lisp ```` or ```` ```agentscript ````
anywhere in the repository's Markdown. Fenced code is compiled by nothing, so the documentation
drifted away from the language repeatedly and silently: the `llms.txt` the site served taught
`(:export ...)`, `Ok`/`Err` and `zip-with`; `BEST_PRACTICES.md` taught `defextern`;
`COMPACT_SYNTAX.md` taught `(schema Point [x:Num y:Num])`; a blog post showed a `defun` with no
body. None of it parses.

Other languages get their own fence and are not graded against Core's grammar: ```` ```agp ```` for
wire frames, ```` ```asn ```` for data payloads. A block that is deliberately invalid in every
language — a specimen of what JSON does wrong, a sketch of a form Core does not have — opts out with
`<!-- not-agentscript: reason -->` on the line before the fence. **The reason is mandatory**: an
opt-out with no stated cause is how a broken example hides.

`bench/token_frames.py --check` pins the only token figure the README publishes. `DESIGN.md` §5
requires every published number to be reproducible by a command, and the front page carried four
that were not: it claimed 42 / 25 / 11 / 9 tokens where `cl100k_base` gives 51 / 34 / 27 / 18.

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

`backend/tests` runs AgentScript source through the transpiler and executes the result, asserting semantics
taken from the specification — not from observing what the transpiler happened to emit.

`checker/tests` covers the type layer's internals. A unifier that accepts everything leaves every gate
green, so the pieces whose failure is silent are tested directly rather than through a verdict.

### The vocabulary and the projection have one source

`prelude/prelude.json` is authoritative for both the closed vocabulary and the Nano projection.
Seven artifacts are **generated** from it, and editing any of them by hand is work the `--check`
gate rejects:

| Artifact | What it carries |
|---|---|
| `AGENT_SPEC_CORE.md` §2.1 | the projection: every alias and the position it is significant in |
| `AGENT_SPEC_CORE.md` §6 | the builtin tables |
| `prelude/HANDBOOK.md` | the agent-facing reference that goes into a prompt |
| `llms.txt`, `web/public/llms.txt` | the machine-readable card, one text in two locations |
| `skills/asl/SKILL.md` | the same card as a harness skill |
| `grammar/agentscript.lark` | the `BEGIN/END GENERATED PROJECTION` terminal block |
| `grammar/tree-sitter-agentscript/grammar.js` | the `HEAD` and `OPT` spelling tables |

```bash
.venv/bin/python prelude/generate.py
```

The two `llms.txt` copies were separately hand-written once and drifted: the one the site served
taught `(:export ...)`, `Ok`/`Err`, `len` and `zip-with`, none of which the language has. They are
one generated text now for that reason.

`HANDBOOK.md` is what goes into an agent's prompt, not the full specification, and the prompt is
resent on every call, so its size dominates the cost of a run. `prelude/budget.lock` ratchets it;
`asl tokens` re-measures.

### Regenerating the parser

After editing `grammar/tree-sitter-agentscript/grammar.js`:

```bash
cd grammar/tree-sitter-agentscript && ../../node_modules/.bin/tree-sitter generate
```

`src/` is generated and git-ignored.

### The syntax has four encodings, and they must change together

- `grammar/tree-sitter-agentscript/grammar.js` — the reference grammar; drives editor
  tooling and the closure audit.
- `grammar/agentscript.lark` — drives constrained decoding, and is being retired.
- `packages/asl-parser/src/{lexer,reader,ast}.asl` — the self-hosted parser, written in
  AgentScript and executed by transpiling to Python.
- `tools/transcoder.py` — the Nano/Verbose projection, which rewrites token spans the
  reference grammar has already classified.

Silent drift means they enforce different languages, and it is not hypothetical: the
self-hosted parser went four phases without `;` comments, with `89.99` lexed as two tokens,
with `-1` read as a symbol, with a dropped module path, and with no way to fail at all,
because nothing held it against the grammar.

```bash
.venv/bin/python -m pytest tools/tests/test_native_parity.py -q
```

The parity gate. Every fixture under `grammar/corpus/{valid,semantic,modules}` and every
`packages/**/*.asl` must be accepted by the self-hosted parser wherever the reference grammar
accepts it, and its verbose rendering must re-parse under it — a render that loses a form
fails here even when the parse succeeded. Every `grammar/corpus/invalid` fixture must be
*rejected*, with a diagnostic carrying a line and a column, so "accepts everything" cannot
satisfy the first claim vacuously. It hard-fails on zero files. It also pins the Nano alias
tables duplicated into `src/ast.asl` — a parser written in AgentScript cannot read
`prelude/prelude.json` — to the readers in `prelude/vocab.py`, for heads, options and types.

Where the language is in flux the gate asks the reference grammar rather than writing an
answer down, so the self-hosted parser follows a language change without the test needing an
edit. `;` comments are the live case: the gate parses a `;` source with tree-sitter and holds
the lexer to whichever verdict comes back.

A Nano alias is an alias **for a position**, never a global rewrite: `:x` is `:export` in a
module option slot and an ordinary record key in `(P :x 1)`. Every consumer resolves it
positionally, and `prelude/prelude.json`'s `projection` section is the one source.

### Structural search

```bash
cd grammar/tree-sitter-agentscript
../../node_modules/.bin/tree-sitter query queries/searches.scm ../corpus/valid/06-module.agentscript
```

Queries address node parts by field name, which is why the grammar carries `field()` annotations.

### Multi-Repo Workspace Orchestration (`GenSEAM/*`)

The GenSEAM ecosystem is distributed across focused modular repositories:
- `GenSEAM/asl` (Core Language, AST, Checker, Transpiler targets, WASI runner, Web Showcase)
- `GenSEAM/harness` (Autonomous Agent Orchestration Engine)
- `GenSEAM/skills` (Universal AI Agent Coding Skills Hub)
- `GenSEAM/agent-bus` (High-frequency in-memory Unix Socket & SSE Mesh Bus)
- `GenSEAM/browser-plugin` (Browser Extension Companion & Visual DOM Context Extractor)
- `GenSEAM/in-browser-dev` (Zero-server WebAssembly hot-reloading IDE & OPFS Git runtime)
- `GenSEAM/search` (Multi-engine decentralized search & markdown RAG context compressor)
- `GenSEAM/mem` (Git-native hierarchical memory matrix & Wasm vector recall)

**Workspace Rules**:
1. **Direct Main Branch Policy**: Work directly on `main` across all repositories.
2. **Deterministic Build Pipeline**: Always verify `npm run build:web` with Node.js 22 LTS (`.nvmrc`).
3. **Cloudflare Pages Deployment**:
   - Build command: `cd web && npm install && npm run build`
   - Deploy command: `npx wrangler pages deploy web/dist --project-name=asl`
   - Config file: `wrangler.toml` with `pages_build_output_dir = "web/dist"`.

### Conventions

- Language identifiers are kebab-case; types are PascalCase; `agentscript-` is a reserved prefix.
- Benchmark task translations are written **by hand**, never generated by a model — a
  model-written translation contaminates the measurement.
- Credentials live in the environment only. Never commit a key, an endpoint with embedded
  credentials, or a `.env`.
- `EXPERIMENT.md` is pre-registered: amendments must be dated and must state whether they were
  made before or after seeing results.

### Dual-Projection Protocol (@pcp:d-1eed, @pcp:d-ddc2, @pcp:c-adc8, @pcp:r-8d8e)

- **The projection saves bytes, not tokens (@pcp:c-e5aa)**: measured over the whole valid corpus
  under `cl100k_base`, Nano is 3.6% fewer bytes and **0.00% fewer tokens** — 15,931 either way.
  `(defun` and `(df` are one token each; ` :export` and ` :x` are two each. Do not repeat the token
  argument for the projection; `bench/token_projection.py --check` pins the figure. The *wire and
  data* formats are a different claim and a true one: removing structure takes a command frame from
  51 tokens to 18 (`bench/token_frames.py`).
- **Storage, wire and generation default (@pcp:d-1eed, @pcp:d-ddc2)**: `.asl` files on disk, inter-agent
  frames, and every agent-facing artifact the toolchain generates use the compact **Nano** spelling —
  `df`, `dfs`, `dfe`, `mt`, `:d`, `:x`, `:i`, `:a`, `:f`, `:c`, `I64`, `F64`, `Str`. The handbook,
  both `llms.txt` copies and the harness skill are emitted that way, so a model generates the stored
  form rather than the long form plus a conversion.
- **Human-facing projection**: in chat, explanations and teaching examples, present the long
  spelling. `asl view` and `asl transcode --to verbose` produce it without touching the file.
- **An alias is positional (@pcp:d-ddc2)**: a short spelling means something only in the position
  `AGENT_SPEC_CORE.md` §2.1 names, and is an ordinary atom everywhere else. **A record whose field is
  called `x` is built with `(P :x 1)` and no tool may rewrite that key.** Every projection tool must
  therefore work on the parse tree. A regex turned `(P :x 1 :d 2 :a 3 :i 4)` into
  `(P :export 1 :doc 2 :as 3 :import 4)`, and the self-hosted parser's `norm-atom` did the same.
- **Reserved width names (@pcp:d-3504)**: `F32` resolves to `Float64` and carries none of a narrower
  type's behaviour — no narrowing, no wrapping, no trap at the narrower boundary. It exists so source
  written against a host that has the width parses today. Do not reach for one to get a smaller
  number.
- **Comments are string literals (@pcp:l-a250)**: `;` line comments are retired; a comment is a
  free-standing string literal bound to nothing — a **note**. Both grammars admit one at top level
  and inside a declaration body, every backend erases the top-level form, and the native lexer
  rejects `;`. Newlines inside a note are safe: the backends escape them.
- **Non-mutating virtual inspection (@pcp:r-8d8e)**: do not use Git clean/smudge filters or on-save
  hooks that mutate files under the user's focus. Use `asl view`, a virtual IDE scheme, or an
  explicit `asl transcode`.
- **Control-flow linearization (@pcp:c-adc8)**: keep control nesting at four levels or fewer. Prefer
  `try` early returns and local helpers over deep `match`/`if` trees.
