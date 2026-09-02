# Phase 2 — `packages/asl-parser`: genuine self-hosted lexer + reader, verified by execution

Phase acceptance gate:

```bash
.venv/bin/python -m pytest packages/asl-parser/tests/test_reader.py packages/asl-parser/tests/test_lexer.py -q
```

**Baseline (measured this session, `main` @ bb0ccaa):** the gate is **green — 4 passed in 0.24s**.
That is the defect: every assertion in the two files is a Python mirror
(`test_lexer.py:22-56` `classify_atom`, `test_reader.py:20-44` `parse_sexpr`), and the `.asl`
fixtures are stubs returning `true` (`tests/lexer_test.asl:6-7`, `tests/reader_test.asl:6-7`).
Therefore no item's gate below may reuse an existing test node ID: every gate targets a **new**
test that fails today by absence (collection error / `no tests ran`) and passes only when real
transpiled-ASL execution asserts the result. The final item re-runs the phase gate and additionally
greps for the mirrors, so "green" can no longer mean "mirror passed".

**Naming.** The compact dialect is called **Ultra-Nano** throughout this plan (`tools/transcoder.py:to_ultra_nano`
is the reference implementation of the projection). "Verbose" is the other dialect.

## Verified builtin surface (recorded per orchestrator decision 1)

Confirmed present in `prelude/prelude.json` **with Python lowerings** (`b["py"]`), by direct read
this session and re-confirmed by the backend-feasibility review. The parser must stay inside this list:

| Builtin | Lowering |
|---|---|
| `string-length` | `len({0})` |
| `string-slice` | `_agentscript.str_slice({0},{1},{2})` |
| `string-index-of` | `_agentscript.str_index_of({0},{1})` |
| `string-contains?` | `({1} in {0})` |
| `string-starts-with?` | `{0}.startswith({1})` |
| `string-split` | `{0}.split({1})` |
| `string-join` | `{1}.join({0})` |
| `string-chars` | `list({0})` |
| `string-to-int64` | `_agentscript.to_int({0})` |
| `string-from-int64` | `str({0})` |
| `str` | `"".join([{*}])` |
| `list-cons` / `list-append` | `([{0}] + {1})` / `({0} + {1})` |
| `list-head` / `list-tail` | `_agentscript.at({0},0)` / `_agentscript.tail({0})` |
| `list-empty?` | `(len({0}) == 0)` |
| `list-reverse` | `{0}[::-1]` |
| `map` | `[{0}(_x) for _x in {1}]` |
| `pair` | `_agentscript.pair({0},{1})` (pattern `pair` handled by `backend/to_python.py:pattern`) |

Special forms needed and already lowered by `backend/to_python.py`: module/defschema/defenum/defun/
fn/let/if/cond/match/try/call/ctor/field-access (`.-field`, `to_python.py:345-352`), enum patterns
(`to_python.py:pattern`), recursion, imports (`Transpiler.transpile(..., path=..., roots=...)` links
transitive deps, `to_python.py:127-148`).

**Not in the vocabulary** (do not plan around them): `string-to-int`, `string-append`, `int-to-string`.
Int literals must go through `string-to-int64`.

## Work items

### 1. Execution harness — transpile + `runpy`, in-process

**What:** new `packages/asl-parser/tests/harness.py` + new driver fixture
`packages/asl-parser/tests/fixtures/exec_smoke.asl`. `harness.run_asl(driver_path) -> dict`:
transpile with `backend.to_python.Transpiler().transpile(src, path=driver, roots=[<src dir>, <driver dir>])`,
`py_compile` the output, copy `backend/runtime.py` next to it (the emit opens with
`import runtime as _agentscript`), then `runpy.run_path` and return the namespace. The harness
**docstring must state why both roots are passed**: `asl-parser/lexer` ↔ `asl-parser/reader`
cross-imports only link when both the `src/` directory and the test/fixture directory are roots
(`Transpiler.link` resolves transitive deps against `roots` and raises on collisions otherwise) —
a later implementer trimming it to `roots=[<src dir>]` breaks item 4 silently. The smoke driver
imports `asl-parser/lexer`, exercises **every builtin in the table above** plus `match`/`let`/
recursion/`pair`, and returns one typed value computed from their results — the test asserts that
value against a hand-written expectation (e.g. `run-smoke` evaluates
`(token-type-name (token-kind "("))` and the test asserts `"LPAREN"`; never a literal `true` —
the stub pattern this phase exists to kill). The driver **must contain at least one
`(match <enum-value> ((<case>) ...))`** so the enum tag-compare lowering executes under the harness
before item 4's first `match` test leans on it. The driver must **not** be named `main`:
`Transpiler.host_entry` only emits a host entry for a `main`, but anything named `main` risks the
`runpy` run executing it as a script instead of yielding the namespace value — the returned binding
is `run-smoke`. Test `test_harness_executes_asl` in `test_lexer.py` asserts `ns["run-smoke"]`
equals the hand-written value and asserts a computed string.

**Why:** decisions 1 — the whole phase is graded by execution of transpiled ASL; this is the
vehicle, and it proves the lexer's existing helpers already run end-to-end before anything is added.

**Gate:**
```bash
.venv/bin/python -m pytest packages/asl-parser/tests/test_lexer.py::test_harness_executes_asl -q
```
Current output: `ERROR ... no tests ran` (test does not exist).

**Breaks if run before item above:** nothing — this is the root.

### 2. `lexer.asl`: real `tokenize (String -> (List Token))` with line/col

**What:** extend `packages/asl-parser/src/lexer.asl` with `tokenize` (exported): recursive scanner
over `string-slice`/`string-length`/`string-chars` — skip whitespace, delimiters become the four
nullary cases, `"` starts a string literal (scan to closing quote, keep raw text), digits start an
int (`string-to-int64`), `:` a keyword, else symbol; accumulate with `list-cons` +
`list-reverse`; every token carries 1-based `line`/`col` in the existing `Token` schema
(`lexer.asl:16-22`); terminate with `(tok-eof)`. Extend `token-kind`-style classification only where
the scanner needs it — do not reshape existing exported helpers.

**`string-slice` semantics (verified, `backend/runtime.py:196-200`):** half-open and end-exclusive
— `s[a:b]` under the guard `0 <= a <= b <= len(s)`, and it returns an **Option** (`some`/`NONE`),
so the scanner unwraps the result explicitly rather than treating the slice as a bare `String`.
The scanner's index arithmetic is correct only against this convention.

**Input-length bound (promised by the harness and fixtures):** every test input stays **≤ 2 KiB**.
Deeper input needs an accumulator-style rewrite of the scanner (CPython has no TCO and
`string-slice` copies per call); that is item-2 scope expansion and must be **flagged**, not hidden
— `sys.setrecursionlimit` in the harness is not a fix (C-stack exhaustion segfaults well before it
helps at scale). Tests in `test_lexer.py`: `test_tokenize_runs` drives `tokenize` through the
harness on a multi-line sample and asserts kinds, raw-text, line and col of specific tokens (values
written by hand from AGENT_SPEC_CORE §scanner expectations, not from observed output).

**Why:** `tokenize` is absent today — `lexer.asl` exports only per-atom classifiers (`lexer.asl:2-4`).

**Gate:**
```bash
.venv/bin/python -m pytest packages/asl-parser/tests/test_lexer.py -q
```
Current output: `4 passed` — but `test_tokenize_runs` absent ⇒ `ERROR ... no tests ran` for the
item's own node id; after the item, whole file passes with the new test included.

**Breaks if run before item 1:** the test has no way to execute ASL (no harness), so it would be a
mirror — exactly what the phase forbids.

### 3. `ast.asl`: the four typed nodes, full field shapes

**What:** new `packages/asl-parser/src/ast.asl` defining, per AGENT_SPEC_CORE.md :199-207 / :269-273 /
:317 / :333-339 / :384-386:

- `ModuleNode` — `:doc` (String), exported names `(List String)` (the `:export [ ... ]` vector),
  `imports (List (Pair String String))` (module path, alias — the `:import [(core/strings :as s) ...]`
  surface), `defs (List TopForm)`.
- `SchemaNode` — name, `type-vars (List String)`, fields (`:default`/`:json` per-field options),
  `json-case (Option String)` — the schema-level `:json-case` (`kebab`/`camel`/`snake`/`pascal`;
  `None` means the `kebab` default). Without it the wire-format rule cannot be checked from the
  AST without re-reading source.
- `EnumNode` — name, `type-vars (List String)`, cases.
- `DefunNode` — name, `type-vars (List String)` (rule 10: every used type variable is bound here),
  `is-exported (Bool)` (resolved at module scope by item 4 against the module's `:export` vector —
  rule 8 makes `:doc` **mandatory for exported functions and optional otherwise**, and that
  conditionality needs this field), `!` effect flag as `Bool` **read verbatim from the source token
  between `defun` and the optional `{<type-vars>}` — never inferred from the body** (rule 12 must be
  enforceable from the AST alone), `params` — a `(List Param)` where each `Param` came out of the
  `[ ... ]` **vector** form (`AGENT_SPEC_CORE.md:317-322`; a reader treating it as a `( ... )` list
  has mis-implemented the form), return type, `:doc`, body.
- `EnumCase` — name, `fields` from the `[ ... ]` vector form (`AGENT_SPEC_CORE.md:385`:
  `[(width Float64) (height Float64)]`), `:doc`.
- `AstField` helper schema and a `TopForm` enum wrapping the four nodes.

Heads may arrive Ultra-Nano or verbose; the nodes store the **verbose** head string only
(normalisation belongs to the reader, item 4).

**Typed-AST scope (deliberate split):** the parser produces typed nodes for exactly the four §4
heads — `ModuleNode`, `SchemaNode`, `EnumNode`, `DefunNode`. Every other top form is retained as
generic `SExpr` inside the node's body field. This is by design: semantic rules live in the checker
(`AGENT_SPEC_CORE.md:744-747`), and retaining untyped forms is what lets the checker keep doing
rule-level rejection. The "parser produces a typed AST" claim is scoped to the four heads; item 4
must not widen the SExpr fallback to swallow classified forms.

Tests in `test_reader.py`: `test_ast_nodes_run` constructs each node through the harness and asserts
a `.-field` projection of each.

**Why:** typed nodes are absent (`packages/asl-parser/src/` contains only `lexer.asl`,
`reader.asl`; `reader.asl:2-4` exports generic `SExpr` helpers only).

**Gate:**
```bash
.venv/bin/python -m pytest packages/asl-parser/tests/test_reader.py::test_ast_nodes_run -q
```
Current output: `ERROR ... no tests ran`.

**Breaks if run before item 1:** same as item 2 — no execution vehicle.

### 4. `reader.asl`: token-consuming parse into the typed AST, both dialects

**What:** extend `packages/asl-parser/src/reader.asl` (or place `parse` in `ast.asl` — implementer's
choice, but the export must be reachable from one module) with `parse (String -> (List TopForm))`:
`tokenize` → recursive-descent reader over `List Token` returning `(pair forms (List Token))`
remainder pattern, dispatching on the head atom against **both** dialect heads using the existing
`is-dual-head?` helper (`reader.asl:41-43`) and the `tools/transcoder.py:15-25` mapping
(`defun`/`df`, `defschema`/`dfs`, `defenum`/`dfe`, **`match`/`mt`**, `:field`/`:f`, `:case`/`:c`,
`:doc`/`:d`, `:export`/`:x`, `:import`/`:i`, `:as`/`:a`), normalising to verbose before node
construction. The same head-normalisation mapping applies to **embedded SExpr heads in bodies** —
a `(match ...)` inside a `defun` body and its Ultra-Nano `(mt ...)` twin must normalise and render
identically even though `match` has no typed node (`match`/`mt` joins the mapping, not the typed
dispatch).

**Option keywords are named slots, not syntax.** `:doc`/`:d`, `:export`/`:x`, `:import`/`:i`,
`:field`/`:f`, `:case`/`:c`, `:as`/`:a` are routed by their slot within the owning form, not by a
syntactic keyword class: a token spelled `:d` outside a documentation slot is ordinary data (the
lexical rule permits any `:ident`), not a parse error and not a doc option.

`is-exported` on each `DefunNode` is resolved against the owning module's `:export` vector at module
scope. Unclassified forms stay as generic `SExpr` inside the node's body field rather than being
dropped — per item 3's scope statement, this is what keeps semantic-rule rejection in the checker.

**Corpus/semantic regression responsibility:** item 4 must not disturb the checker's rule-level
rejection — the reader retains unclassified forms as `SExpr` precisely so `grammar/corpus/semantic`
fixtures keep failing under the rule their `; expect:` header names. Item 4's gate therefore also
re-runs the checker gate.

Tests in `test_reader.py`: `test_parse_verbose` and `test_parse_nano` drive `parse` through the
harness on a verbose and an Ultra-Nano module fixture and assert the same field values on the
produced `DefunNode`/`SchemaNode` (names, arity, effect flag, param count) — hand-written expectations.

**Why:** there is no token-consuming parse today; `reader.asl` only manipulates already-built
`SExpr` values, and nothing produces a typed AST.

**Gate:**
```bash
.venv/bin/python -m pytest packages/asl-parser/tests/test_reader.py -q
.venv/bin/python checker/gate.py
```
Current output: first command `2 passed` — item's own node ids absent ⇒ `ERROR ... no tests ran`;
checker gate green today and must stay green.

**Breaks if run before items 2–3:** `parse` consumes `tokenize` output and constructs `ast.asl`
nodes; without them the driver does not transpile (checker/linker rejects the import surface).

### 5. Canonical verbose renderer + Ultra-Nano/verbose round-trip

**What:** add `render-node (TopForm -> String)` producing the **canonical verbose** text (one
whitespace convention, `:doc` first, options in spec order). Add test `test_nano_verbose_roundtrip`
in `test_reader.py`: take one module source and run `parse` on it against **two** Ultra-Nano twins —
one produced **with `tools/transcoder.py:to_ultra_nano`** (the reference mapping, not a hand copy)
and one **hand-written** (so a parser that cheats by calling `to_ultra_nano` internally cannot pass
by matching its own output) — then assert two things for every top form:

1. `render-node` output is byte-identical across the verbose source and both Ultra-Nano twins;
2. **per-form head-equality**: `parse(verbose)` and `parse(Ultra-Nano)` yield ASTs whose
   corresponding fields are equal for every field whose source surface varies — the ten mapped
   heads `defun`/`df`, `defschema`/`dfs`, `defenum`/`dfe`, `match`/`mt`, `:field`/`:f`,
   `:case`/`:c`, `:doc`/`:d`, `:export`/`:x`, `:import`/`:i`, `:as`/`:a`. Rendering equivalence
   alone does not prove the parser distinguishes the dialects; the head assertions do.

**Why:** orchestrator decision 2 — dual projection is proven by `parse(Ultra-Nano)` and
`parse(verbose)` producing the same AST and rendering to one canonical string; nothing today renders
a typed AST at all.

**Gate:**
```bash
.venv/bin/python -m pytest packages/asl-parser/tests/test_reader.py::test_nano_verbose_roundtrip -q
```
Current output: `ERROR ... no tests ran`.

**Breaks if run before item 4:** there is no `parse` to feed.

### 6. Retire the mirrors; fixtures become drivers; phase gate

**What:** rewrite `packages/asl-parser/tests/test_lexer.py` and `test_reader.py`: delete the Python
mirrors (`classify_atom`, `parse_sexpr`) and the `test_*_simulation`/`test_*_token_rules` bodies that
assert them; keep a `check_file`-clean assertion for every `.asl` file under `packages/asl-parser/`
as a **secondary** check (source files must still check clean). Repoint `tests/lexer_test.asl` and
`tests/reader_test.asl` from stubs into real driver modules whose exported functions are what the
pytest tests invoke (they currently `:import (core/strings :as s)` and return literal `true` —
`lexer_test.asl:6-7`, `reader_test.asl:6-7`; the import is also dead in a stub). Re-run the full
phase gate and the repo corpus gates to confirm nothing else regressed.

**Why:** the phase gate is green today purely on mirrors; leaving them means "passing" forever
means nothing.

**Gate (phase-level, plus the no-mirror guard):**
```bash
.venv/bin/python -m pytest packages/asl-parser/tests/test_reader.py packages/asl-parser/tests/test_lexer.py -q
! grep -n "classify_atom\|parse_sexpr" packages/asl-parser/tests/test_lexer.py packages/asl-parser/tests/test_reader.py
```
Current output: first command `4 passed` (green on mirrors); grep finds 2 hits ⇒ guard fails today.

**Breaks if run before items 1–5:** the rewritten tests would have nothing genuine to assert.

## Risks / unverified

- **Recursion depth.** `tokenize` is per-character recursive; CPython's default limit (~1000) caps
  input length, and per-call `string-slice` copies make the real budget smaller than the frame count
  suggests. Item 2 fixes the promise: **harness and fixture inputs stay ≤ 2 KiB**; deeper input is
  an accumulator-style rewrite, flagged as scope expansion, never hidden behind
  `sys.setrecursionlimit`.
- **`string-slice` semantics — resolved.** Half-open, end-exclusive, guard `0 <= a <= b <= len(s)`,
  returns an Option: `backend/runtime.py:196-200`, read and recorded in item 2. The implementer must
  still not skip the read before writing the scanner loop.
- **Enum-value equality for `Token.kind` assertions.** Tests will assert kinds via
  `token-type-name` (String) rather than comparing enum values in Python, since the transpiled enum
  is a tagged tuple (`to_python.py` emits `("<case>" [, payload...])`; `pattern` compares the tag
  string) — asserting on the tuple's shape would be asserting the lowering, not the AST. Item 1's
  driver exercises the tag-compare `match` path so this is proven before item 4 relies on it.
- **`core/strings` resolution — resolved.** `grammar/corpus/modules/core/strings.agentscript`
  exists (confirmed this session). Item 6 repoints the fixtures' imports to `asl-parser/lexer` /
  `asl-parser/reader` anyway; if `check_file` on the old fixtures was passing by luck, that luck
  dies here (which is fine — it is in scope).
- **Matcher on schema records.** `backend/to_python.py:pattern` handles enum patterns but there is
  no record-destructuring pattern for `defschema` values; the reader must use `(.-field tok)` access
  (`to_python.py:345-352`, AGENT_SPEC_CORE.md "Field access uses the `.-` prefix") rather than
  pattern-matching a `Token`. If a record pattern *is* wanted, it is a transpiler change and
  **out of scope** — flag to orchestrator instead.
- **Verified-builtin table** was compiled by reading `prelude/prelude.json` fields, not by executing
  every lowering; item 1's smoke driver closes that gap by evaluating each one.

## Out of scope

- **Rust/TypeScript/Go backends for the parser** — decision 1 fixes the execution vehicle to
  `to_python.py`; `differential.py` over the parser is a later phase.
- **Transpiler changes** (record patterns, tail calls, `main` semantics) — any gap that cannot be
  worked around inside the verified surface is reported as a finding, not fixed here.
- **`grammar/` changes** — both grammars already accept both dialects (`tools/transcoder.py` mapping
  round-trips today); no grammar work belongs to this phase.
- **Wasm/JIT performance of the parser** — nothing in the phase measures speed.
- **Typed nodes beyond the four §4 heads** — `match`/`fn`/`let` etc. round-trip as normalised
  `SExpr` (item 4); giving them typed nodes is a later phase.
