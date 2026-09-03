# Phase 4 — Parser Scalability: iterative scanner (asl-selfhosted-runtime-v1)

## Acceptance criterion

```
.venv/bin/python -m pytest tools/tests/test_native_parse_all.py -q
```

Current verbatim output:

```
no tests ran in 0.00s
ERROR: file or directory not found: tools/tests/test_native_parse_all.py
```

With the test file present, the failure it exposes is (measured by probe just now,
running `native_render` on the file contents):

```
packages/asl-parser/src/lexer.asl FAIL: maximum recursion depth exceeded
packages/asl-parser/src/ast.asl FAIL: maximum recursion depth exceeded
packages/asl-sh/src/sh.asl FAIL: maximum recursion depth exceeded
```

The parser's own suites are green today and must stay green (measured just now):
`packages/asl-parser/tests` + `tools/tests/test_native_parser.py` → `14 passed in 17.08s`.

## Root cause (verified, with citations)

`packages/asl-parser/src/lexer.asl` scans by pure recursion, one Python frame per
character: `tokenize` (lexer.asl:88) → `scan` (lexer.asl:141) → `scan-run`
(lexer.asl:128) → `run-emit` (lexer.asl:114) → back into `scan`. Whitespace
consumes one `scan` frame per char (lexer.asl:146-149), so depth scales with file
size: lexer.asl itself is 6296 B and ast.asl is 17628 B. The language has no
`while`/`recur` and no TCO, so emitted Python recursion is real recursion.

The reader and AST layers also recurse, but per *structural* unit, not per char:
`read-forms` per top-level form (ast.asl:70-78; ast.asl has **52** top-level
forms, counted with `grep -cE '^\((df|dfs|dfe|module) '`), `read-one`/`read-seq-items`
per list item and nesting level (ast.asl:81-104), `decl-forms` per declaration
(ast.asl:192), `collect-vars` per type var (ast.asl:224), `find-opt` per field
(ast.asl:139). Depth is bounded by form count and nesting, not file bytes — but
the end-to-end behaviour on a 17 KB file is not yet measured, so Item 3 verifies
it and fixes only on a red gate.

## Verified iteration surface (what the rewrite may use)

- `fold` : `(fn [B A] -> B) B (List A) -> B`, lowered to a Python `for` loop
  (`_agentscript.fold`, prelude.json:754-761; `backend/runtime.py:189-193`).
- `string-chars` : `String -> (List String)`, lowered to `list({0})`
  (prelude.json:479-485).
- Two-parameter `fn` literals inside `fold` are legal and tested:
  `grammar/corpus/valid/14-sequenced-bodies.agentscript:15`,
  `grammar/corpus/valid/07-lambda-elision.agentscript:18`.
- Passing a named `df` as a function value is legal and in use:
  `(fold tally (map-empty) words)` — `bench/algo/histogram.agentscript:15`,
  `grammar/corpus/valid/26-map-lifecycle.agentscript:21`.
- Generic `Option` over any type is legal: `(Option rd/SExpr)` (ast.asl:139),
  `(Option (Pair String Int64))` (grammar/corpus/valid/04-longest-run.agentscript:16).
- `string-slice` returns an Option, half-open (prelude.json:347-354;
  `backend/runtime.py:195-199`); `string-to-int64` → Option (prelude.json:512);
  `list-cons` (prelude.json:644), `list-reverse` (prelude.json:666).
- There is **no record field-update syntax** — fold state must be rebuilt via
  constructors each step, or carried as a `Pair`.

---

## Work items

### Item 1 — Add the phase-gate test `tools/tests/test_native_parse_all.py`

**What.** New file `tools/tests/test_native_parse_all.py`. Conventions copied
from `tools/tests/test_native_parser.py` (`ROOT = Path(__file__).resolve().parent.parent.parent`,
import `from tools.native_parser import native_render`). It must:

- walk `ROOT / "packages"` with `rglob("*.asl")` — 37 files today (counted with
  `find packages -name '*.asl' | wc -l`; record the measured count in a comment);
- parametrize per file with the repo-relative path as the pytest id, so a
  failure names the file;
- per file: `out = native_render(text)`; assert `isinstance(out, str)` and
  `out.strip()` is non-empty (every package file carries a `(module ...)` header,
  so `render-all` always yields at least one line);
- hard-fail the whole module if the walk finds **zero** files (guards against a
  silently broken glob reporting a green run).

**Why.** This file *is* the phase gate; nothing else in the repo drives the
native parser over every real package source. Until it exists the acceptance
criterion cannot even be evaluated.

**Gate (fails now, passes only when the whole phase is done).**

```
.venv/bin/python -m pytest tools/tests/test_native_parse_all.py -q
```

Current verbatim output: `ERROR: file or directory not found: tools/tests/test_native_parse_all.py`.
After this item alone it must fail on the five verified-overflow files
(`lexer.asl`, `reader.asl`, `ast.asl`, `asl-sh/src/sh.asl`, `asl-lint/src/core/lint.asl`)
with `maximum recursion depth exceeded` — that failure is the phase's measuring
instrument, so this item ships before any parser change.

**What breaks if run late.** If the lexer rewrite (Item 2) lands first, the test
is written against an already-moving target and nobody sees which files it
rescued; ordering test-first keeps the root-cause claim falsifiable.

---

### Item 2 — Rewrite the lexer scanner core as a `fold` over the char stream

**What.** In `packages/asl-parser/src/lexer.asl`, replace the recursive core
(`scan`, `scan-run`, `run-emit`, lexer.asl:114-160) with an explicit-state fold:

- Two private `dfs` records, e.g. `RunState` (`:mode RunMode`, `:raw String`,
  `:start-line Int64`, `:start-col Int64`) and `ScanState` (`:toks (List Token)`
  reversed accumulator, `:line Int64`, `:col Int64`, `:run (Option RunState)`).
- One private step function `(df step [(st ScanState) (ch String)] -> ScanState ...)`
  passed **by name** to `(fold step (initial-state) (string-chars s))` — bare
  named-function arguments to `fold` are verified working
  (bench/algo/histogram.agentscript:15). Rebuild the `ScanState` record each
  step (no field-update syntax exists).
- `tokenize` (lexer.asl:88) keeps its exact signature; after the fold it flushes
  an open run (if any) and appends the EOF token, then `list-reverse`s the
  accumulator.

**Exported surface must not change** — lexer.asl:3-5 exports exactly `TokenType
Token make-token token-kind is-whitespace is-delimiter token-type-name tokenize`.
`scan`/`scan-run`/`run-emit`/`RunMode`/`run-continues?`/`run-token` are private
and may be deleted or reshaped; `token-kind`, `delim-kind`, `is-symbol-char`,
`is-brace`, `char-at`, `is-digit` stay as-is (they are pure per-atom/per-char
helpers, not part of the recursion). Cross-module consumers verified: `ast.asl:5`
imports lexer and uses only `lx/Token` and `lx/tokenize`; the three test drivers
(`tests/lexer_test.asl:4`, `tests/fixtures/exec_smoke.asl:4`,
`tests/fixtures/tokenize_driver.asl:4`) use only exported names.

**Semantics that must be preserved bit-for-bit** (each one is an observable the
gates check):

1. 1-based line/col; `\n` resets col to 1, otherwise col + 1 — including *inside*
   string runs (scan-run updates line/col for every consumed char, lexer.asl:133-136).
2. Whitespace: one char skipped, position advanced (lexer.asl:146-149).
3. Delimiters `()[]` and braces `{}` emit their own tokens at the *current*
   position (lexer.asl:149-153), and terminate an open symbol/keyword run first
   (`is-symbol-char` excludes them, lexer.asl:72-77).
4. `"` opens a string run whose raw includes the opening quote (lexer.asl:154-155);
   on the closing quote the raw includes it and the position advances past it
   (lexer.asl:118-124); at EOF an open string emits its raw *without* a closing
   quote (lexer.asl:117-118).
5. A digit opens an int run (lexer.asl:156-157); on emit, `string-to-int64`
   failure yields `0` (lexer.asl:109-111).
6. `:` opens a keyword run with raw `:` (lexer.asl:158) — a lone `:` before a
   delimiter or whitespace is still a `tok-keyword ":"` because `:` is not a
   symbol char (lexer.asl:72-77).
7. EOF terminator: raw `""` at the final line/col (lexer.asl:142-144). This raw
   `""` is a load-bearing sentinel — `read-forms` detects stream end by it
   (ast.asl:75-76). Do not "fix" it.
8. Run start positions are captured when the run opens (`start-line`/`start-col`,
   lexer.asl:154-159), not when it emits.

**Hardening (recommended, small).** `test_lexer.py::test_tokenize_runs` asserts a
hand-written 7-token expectation (test_lexer.py:26-40) that covers items 1-7 only
partially (no string-at-EOF case). If the implementer extends
`fixtures/tokenize_driver.asl` with one more sample, the expected strings must be
written by hand from the semantics above, never from observing the new output
(project convention; AGENTS.md "Benchmark task translations are written by hand").

**Why.** This is the dominant fix: it replaces per-character recursion depth with
a Python `for` loop (`_agentscript.fold`, runtime.py:189-193), dropping lexer
depth from O(bytes) to O(1).

**Gate.**

```
.venv/bin/python -m pytest tools/tests/test_native_parse_all.py -q
```

Fails now (Item 1's red run). Declared expected result after this item: every
file whose overflow was lexer-bound goes green — minimally `lexer.asl`,
`reader.asl`, `asl-sh/src/sh.asl`, `asl-lint/src/core/lint.asl` (all measured
overflowing; all have token streams whose reader/AST depth is small). `ast.asl`
(17 KB) may still be red at this point — that is exactly what Item 3 decides.

**What breaks if it runs before Item 1.** Without the test there is no command
that fails on the current lexer, so the rewrite would be graded by the *old*
green suites, which pass against the recursive lexer too — the change would be
unverifiable.

**Regression guard for this item** (green today, must stay green):
`.venv/bin/python -m pytest packages/asl-parser/tests -q` → `8 passed in 8.90s`.

---

### Item 3 — Verify the reader/AST layers on the 17 KB file; fix only on a red gate

**What.** Run the ast-focused slice of the phase gate:

```
.venv/bin/python -m pytest tools/tests/test_native_parse_all.py -q -k ast
```

- **If green** (expected: reader depth for ast.asl is ~52 frames of
  `read-forms` plus nesting-bounded `read-seq-items`/`find-opt`/`collect-vars` —
  small against CPython's 1000-frame default): the item's deliverable is the
  recorded measured result; no code changes. Do not pre-emptively rewrite
  working code.
- **If red** with `maximum recursion depth exceeded`: apply the same treatment
  to the implicated chain in `packages/asl-parser/src/ast.asl` — `read-forms`
  (ast.asl:70-78) and `read-seq-items` (ast.asl:92-104) become folds over the
  token list with an explicit `(Pair SExpr remaining-toks)`-shaped state, exactly
  the pattern Item 2 establishes (`list-head`/`list-tail` provide the stream,
  both verified in prelude.json). `decl-forms` (ast.asl:192) and `collect-vars`
  (ast.asl:224) get the same only if the gate names them.

**Why.** The task's root-cause analysis flags the reader/AST recursion as
probably-bounded but unverified on a real 17 KB input; the acceptance criterion
requires ast.asl to parse, and a silent assumption here would leave the gate red
with no plan for it.

**Gate.** The `-k ast` command above. Fails now and after Item 1; expected green
after Item 2 — if it is not, this item's rewrite is the only thing that can turn
it green.

**What breaks if it runs before Item 2.** Before the lexer fix, the ast.asl
failure is caused by the lexer, so any reader change made now would be graded
against a defect that lives elsewhere and could "pass" while hiding a real reader
limit (or fail and invite an unnecessary rewrite).

---

### Item 4 — Full gate run: phase gate + both regression suites + repo gates

**What.** Run, in order, and record outputs:

```
.venv/bin/python -m pytest tools/tests/test_native_parse_all.py -q
.venv/bin/python -m pytest packages/asl-parser/tests tools/tests/test_native_parser.py -q
.venv/bin/python grammar/validate.py
.venv/bin/python grammar/closure_audit.py
.venv/bin/python checker/gate.py
```

The first two are the phase gate and the regression floor (`14 passed` today);
the last three are cheap insurance the project's AGENTS.md requires before any
commit — `lexer.asl` changed, so the closure audit's call-head extraction must
still resolve every head it sees (the rewrite introduces only vocabulary
builtins plus locally-bound `df`s, and passes a `df` by name as a value, which
the audit must tolerate — corpus precedent exists, see
grammar/corpus/valid/26-map-lifecycle.agentscript:21, but the audit's treatment
of a bare-value argument in `packages/` is unverified; see Risks).

**Why.** Separation of duties: the phase closes only on an independently re-run
gate, and a lexer rewrite that regressed token semantics would show up in
`test_lexer.py`'s hand-written expectations (test_lexer.py:26-40) here.

**Gate.** The first command above; fails now (`ERROR: file or directory not
found: tools/tests/test_native_parse_all.py`), green only when the phase is done.

---

## Risks / unverified

1. **`fold` emission of a large step function (medium).** No file under
   `packages/` uses `fold` today (`grep -rn '(fold ' packages/` → no matches);
   the lowering itself is verified (prelude.json:754-761, runtime.py:189-193) and
   two-param `fn` literals in `fold` are corpus-tested, but a step body with
   nested `mt`/`cond`/`let` of this size has never been transpiled. Mitigation:
   pass a private `df` by name (verified pattern, histogram.agentscript:15) so
   the `fn` literal stays trivial. If the transpiler still chokes, that is a
   backend defect to report, not a reason to reintroduce recursion.
2. **Closure audit vs. bare function values in `packages/` (low-medium).** The
   audit extracts call heads from repo sources; whether it scans `packages/*.asl`
   and how it classifies `(fold step ...)` where `step` is a value, not a call,
   is unverified. `step` is locally bound, so the "vocabulary or locally bound"
   rule should accept it — Item 4's `closure_audit.py` run is the check.
3. **Executed-coverage ratchet (low).** `fold`/`string-chars` become executed
   vocabulary if any gate-run program evaluates their emitted expressions
   (backend/exec_coverage.py). If a coverage gate moves, record the new figure
   with `backend/exec_coverage.py --write` deliberately, in the commit that
   earns it — never by editing the lock by hand.
4. **Per-char record allocation (low).** Rebuilding `ScanState` per char is O(1)
   per char and O(bytes) overall — 17628 steps for ast.asl, far below any
   recursion concern; `str` accumulation per run is O(run²) but runs are short.
   No action planned; noted so nobody "optimizes" into a shared-mutable-state bug.
5. **Unverified end-to-end**: whether the reader chain's real depth on ast.asl
   stays under the limit after Item 2 (Item 3 exists to measure it), and whether
   any of the 32 non-parser package files have reader-depth exposure beyond the
   five measured overflow files (the gate measures all 37; only the five are
   pre-verified to fail).

## Out of scope

- **A `while`/`recur` special form or TCO** — a language change with its own
  spec/gate burden; this phase uses only the verified builtin surface.
- **The JS/Rust/Go backends' treatment of the parser** — the harness
  (`packages/asl-parser/tests/harness.py`) transpiles to Python only;
  `native_render` is Python-only (`tools/native_parser.py:34-40`).
- **Runtime recursion inside other packages' own logic** (e.g. `bus.asl`,
  `vdom.asl`) — the phase gate parses those files but does not execute them;
  only the parser's recursion is exercised.
- **Parser performance/benchmarking** — O(bytes) fold with per-char record
  rebuild is fast enough for the gate; timing work belongs to the existing
  `--bench` surface, not this phase.
- **The Lark grammar and constrained decoding** — `agentscript.lark` and
  `grammar.js` are untouched; the language does not change, only one
  implementation of its scanner does.
