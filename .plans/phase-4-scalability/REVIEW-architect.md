# REVIEW-architect — Phase 4 (Parser Scalability: iterative scanner)

Lens: algorithmic/cross-cutting. Plan reviewed:
`.plans/phase-4-scalability/PLAN.md` (4 items). Verdict at bottom.

## Method

Every probe below was re-measured this session, not copied from the plan:

- `find packages -name '*.asl' | wc -l` → **37** (plan's count confirmed).
- `grep -cE '^\((df|dfs|dfe|module) ' packages/asl-parser/src/ast.asl` → **52**.
- Phase-gate probe: a script walking `rglob("*.asl")` under `packages/`,
  calling `tools.native_parser.native_render(text)` per file. **20 of 37
  files fail** with `maximum recursion depth exceeded` (full list below),
  17 pass.
- `python -m pytest tools/tests/test_native_parse_all.py -q` → verbatim
  `no tests ran in 0.00s` / `ERROR: file or directory not found: ...`
  (plan's acceptance-criterion output confirmed).
- `python -m pytest packages/asl-parser/tests tools/tests/test_native_parser.py -q`
  → `14 passed in 23.37s` (plan's regression floor confirmed).
- Bare-`df`-as-value probe: transpiled `bench/algo/histogram.agentscript`
  through `backend.to_python.Transpiler` — emitted line
  `counts = _agentscript.fold(tally, {}, words)`, i.e. a `df` name passes as
  a bare Python callable. `backend/runtime.py:189-193` (`def fold(f, init,
  xs)`) invokes it as an ordinary Python function.
- `python -c "import json; ..."` on `prelude/coverage.lock` → `fold` and
  `string-chars` are **already** in `instantiations`, lock records
  `executed: 107`.

## Findings, ranked

### F1 (blocking) — Item 1 and Item 2 state five overflowing files; the probe measures twenty

Plan: "it must fail on the five verified-overflow files (`lexer.asl`,
`reader.asl`, `ast.asl`, `asl-sh/src/sh.asl`, `asl-lint/src/core/lint.asl`)"
(Item 1, Gate); "minimally `lexer.asl`, `reader.asl`, `asl-sh/src/sh.asl`,
`asl-lint/src/core/lint.asl` … (all measured overflowing)" (Item 2, Gate).

Re-measured failure set, 20 files:

```
packages/asl-codec/src/core/codec.asl          (11 top forms)
packages/asl-eddie/src/eddie.asl               (11)
packages/asl-fsm/src/fsm.asl                   (5)
packages/asl-lint/src/core/clone.asl           (7)
packages/asl-lint/src/core/heal.asl            (7)
packages/asl-lint/src/core/lint.asl            (11)
packages/asl-parser/src/ast.asl                (52)
packages/asl-parser/src/lexer.asl              (20)
packages/asl-parser/src/reader.asl             (12)
packages/asl-parser/tests/fixtures/ast_driver.asl   (7)
packages/asl-parser/tests/fixtures/exec_smoke.asl   (5)
packages/asl-parser/tests/reader_test.asl      (13)
packages/asl-sh/src/core/log.asl               (7)
packages/asl-sh/src/core/process.asl           (10)
packages/asl-sh/src/sh.asl                     (6)
packages/asl-sh/tests/sh_test.asl              (4)
packages/asl-skyloom/src/core/skyloom.asl      (9)
packages/asl-sql/src/core/ddl.asl              (23)
packages/asl-sql/src/core/sql.asl              (32)
packages/asl-voice/src/voice.asl               (7)
```

Consequences if left as written:

1. Item 1's gate gets a declared expected result that is false on 15 of 20
   files. An implementer who compares against the plan's five-name list sees
   either a "gate that fails differently than declared" or silently loosens
   the assertion to match whatever fails.
2. Item 2's declared expected result ("every file whose overflow was
   lexer-bound goes green — minimally [4 names]") is checkable only against
   the full 20. All 20 are lexer-bound — the 16 non-parser files and both
   test drivers cannot be read at all until `lx/tokenize` is iterative; their
   reader/AST depth is small by top-form count (4–32, vs. CPython's 1000-frame
   default), so green after Item 2 is the correct expectation *for all 20
   except possibly `ast.asl`*. The plan must say so with the full list, or
   the item cannot fail for the right reason.
3. Risks §5 ("whether any of the 32 non-parser package files have
   reader-depth exposure beyond the five measured overflow files") is the
   question the probe already answers. It is not an open risk; it is an
   unrecorded measurement.

Required amendment: Item 1 records the measured 20-file red list verbatim
(the test's parametrize ids already name them); Item 2 declares all 20 green
after the rewrite, with `ast.asl` explicitly deferred to Item 3.

### F2 (blocking) — Item 3's selector `-k ast` names two files, not one

Plan Item 3 gate: `pytest tools/tests/test_native_parse_all.py -q -k ast`.
`-k` is a substring match: it selects both `packages/asl-parser/src/ast.asl`
and `packages/asl-parser/tests/fixtures/ast_driver.asl` (both contain `ast`,
both are in the 20-file failure set). `ast_driver.asl` is lexer-bound with 7
top forms, so it goes green after Item 2 regardless of reader depth. If the
selector is green for the wrong file while `ast.asl` stays red, the item's
decision ("no code changes") is taken on evidence about a different file.

Required amendment: use an exact node-id selector against the parametrized id
(e.g. `-k 'ast.asl and not ast_driver'`, or the full node id with brackets),
and record the chosen selector's actual output in the plan before relying on
it.

### F3 (blocking) — Item 4 runs three of the repo's seven mandatory commit gates

AGENTS.md "Gates — both must pass before any commit" lists
`grammar/validate.py`, `grammar/closure_audit.py`, `prelude/generate.py
--check`, `checker/gate.py`, `backend/check_corpus.py`,
`backend/monomorphism.py`, `backend/differential.py`, plus the four pytest
suites. Item 4 runs only `validate.py`, `closure_audit.py`, `checker/gate.py`
(+ the two pytest suites; `backend/tests` etc. are named in the prose as
"both regression suites" but not in the command list). The plan's own Risks
§3 says the rewrite makes `fold`/`string-chars` executed vocabulary and may
move the lock — precisely the thing `closure_audit.py` +
`exec_coverage.check()` enforce — while omitting `differential.py`,
`monomorphism.py`, `check_corpus.py` and `prelude/generate.py --check` from
the run list. Two of the omissions are provably irrelevant to this change
(`prelude/generate.py --check` — prelude.json untouched; `check_corpus.py` /
`differential.py` / `monomorphism.py` — they consume `grammar/corpus` and
`prelude.json`, never `packages/`; harness.py transpiles to Python only).
But "provably irrelevant" belongs in the plan as an explicit per-gate
justification, not as a silent subset — a subset is a gate made smaller.

Required amendment: Item 4's command list is either the full AGENTS.md set,
or each omitted gate carries a one-line "unaffected because <input set
excludes packages/>" justification. My measured grounds: `prelude/coverage.lock`
already lists `fold` and `string-chars` in `instantiations` with
`executed: 107`, so Risk 3 as written cannot fire from this change; restate
it that way.

### F4 (blocking) — The plan's closure-audit claims describe a gate that does not scan `packages/`

Plan Item 4: "`lexer.asl` changed, so the closure audit's call-head
extraction must still resolve every head it sees" and Risk 2: "whether it
scans `packages/*.asl` … is unverified". Both are resolved by reading the
gate: `grammar/closure_audit.py:76` —
`sources = sorted((ROOT / "corpus" / "valid").glob("*.agentscript"))`,
augmented only by spec-extraction blocks (closure_audit.py:79-86). `packages/`
is outside the gate's input set entirely, so the lexer rewrite changes
nothing the audit sees; the risk is nil, and Item 4's stated reason for
running it ("the rewrite introduces … a `df` by name as a value, which the
audit must tolerate") is false as written. A plan whose risk section asks an
open question the cited file answers is a plan whose author did not open it;
correct it so the implementer does not go chasing a phantom or, worse,
"fix" the audit to scan `packages/` (which would be scope creep into a
gate's enforcement surface).

Required amendment: replace Risk 2 and the Item 4 rationale with the
closure_audit.py:76 citation and the conclusion "audit input set is
`grammar/corpus/valid` + spec examples; the rewrite is invisible to it".

### F5 (non-blocking) — Cited line numbers drift 1–4 lines in the semantic-preservation list

Every def-header citation in the plan is correct (verified:
lexer.asl:88 `tokenize`, :114 `run-emit`, :128 `scan-run`, :141 `scan`;
ast.asl:5 `:i [(lexer ...)]`, :70-78 `read-forms`, :75-76 EOF-raw check,
:81-104 `read-one`, :92-104 `read-seq-items`, :139 `find-opt`, :192
`decl-forms`, :214 `read-type-vars`, :224 `collect-vars`; test_native_parser.py:15
ROOT; ast.asl's 52 top forms). The semantic list's *body* lines are off:

- Item 2 §1 "lexer.asl:146-149" for whitespace → the clause is at
  lexer.asl:147-150 (whitespace branch starts :147, `\n` line/col update at
  :149-150). Plan says "lexer.asl:146-149".
- Item 2 §2 "lexer.asl:149-153" for delimiter/brace emission → delimiter at
  :151-153, brace at :154-156.
- Item 2 §4 "lexer.asl:118-124" for the closing-quote append → the `(let
  [(closed (str raw (char-at s i)))]` append is at lexer.asl:122-124; the
  EOF-without-quote path is :117-120. Range is roughly right; the named
  sub-behaviour lines are not.
- Item 2 §5 "lexer.asl:109-111" for `string-to-int64` → the `tok-int (mt
  (string-to-int64 raw) ...)` expression is at lexer.asl:112.
- Item 2 §6 "lexer.asl:158" for the keyword open → `:` clause at
  lexer.asl:161-162 (`:158` is the string-open `scan-run`).
- Item 2 §7 "lexer.asl:142-144" for EOF → lexer.asl:144
  (`(list (make-token (tok-eof) "" line col))`); :142 is the `(if (>= i
  ...)` guard.
- Item 2 §8 "lexer.asl:154-159" for run-start capture → the three run-open
  sites are at lexer.asl:158 (string), :160 (int), :162 (keyword); symbol at
  :164.
- Item 2 export claim "lexer.asl:3-5" → the `:x` vector spans
  lexer.asl:4-5 under `(module` at :1.

None changes the substance of the preservation list, but the review standard
is that a wrong cited line is the highest-value finding class, and a plan
whose implementer chases `:158` looking for the keyword clause will land on
the string clause instead. All seven semantic points themselves are
**correct** against the code I read (see lens 1 below) — fix the numbers.

### F6 (non-blocking) — Item 1's "hard-fail on zero files" is good; one guard missing

Item 1 requires failing the module when the walk finds zero files — correct,
this is the silent-green defense. But the walk's root is computed from
`ROOT = Path(__file__).resolve().parent.parent.parent`
(test_native_parser.py:15 convention); if that resolves wrong, `rglob` finds
zero files and the hard-fail fires with an unhelpful message. Add: assert
the resolved `ROOT / "packages"` exists before the zero-count check, so the
failure names the cause. Also: the plan asserts "every package file carries
a `(module ...)` header, so `render-all` always yields at least one line" —
verified true (`head -1` of all 37 files starts with `(module`), so the
`out.strip()` non-empty assertion is safe. No change required.

## Lens answers

### 1. Correctness of the fold-based scanner design — sound, with two sharp edges

The seven semantics the plan lists all match the code:

- (a) Newline accounting: `scan` whitespace branch and `scan-run` both do
  `(if (= ch "\n") (+ line 1) line)` / `(if (= ch "\n") 1 (+ col 1))`
  (lexer.asl:147-150, :133-136 by offset; the step function must apply this
  rule uniformly to every consumed char **including inside runs** — the plan
  says so in §1 and this is the single most likely regression.
- (b) Closing quote: `run-emit` appends `char-at s i` to the raw before
  advancing `i` (lexer.asl:122-124). In a fold the closing `"` is an
  ordinary char of the stream, so the step function consumes it into `raw`
  and clears the run — the fold version is structurally less error-prone
  than the recursive one, provided the step recognizes the in-string state
  before testing delimiter/digit rules. The mode lives in
  `ScanState.run (Option RunState)`, which the plan specifies; correct.
- (c) EOF sentinel: lexer.asl:144 emits raw `""`; ast.asl:75-76 keys stream
  end on exactly that raw. The plan names this as load-bearing (Item 2 §7)
  and the post-fold flush must reproduce it: append the EOF token with the
  final `line`/`col` from `ScanState`, then `list-reverse`. Correct as
  specified.
- (d) `string-to-int64` unwrap: lexer.asl:112 — `((some v) v) ((none) 0)`.
  The plan's §5 preserves the `0` fallback. The fold's flush path must call
  the same helper (`run-token` stays, per plan); correct.
- (e) Keyword runs: `:` opens a run with raw `":"` (lexer.asl:161-162); a
  lone `:` before a delimiter emits `tok-keyword ":"` because `:` is not a
  symbol char (lexer.asl:72-77). The plan's §6 states this. Correct.

Termination: `fold` over `string-chars` is bounded by input length;
`runtime.py:189-193` is a `for` loop, no recursion. The step function is
total over `(ScanState × String) → ScanState` as specified. Depth drops from
O(bytes) to O(1) plus the flush, as claimed.

Sharp edge 1 (the plan names it, keep it sharp): the post-fold flush must
handle an open run. Current code handles open string at EOF by emitting raw
without a closing quote (lexer.asl:117-120); the flush must do the same, and
must also run `run-token` for open symbol/keyword/int runs. Plan Item 2
"flushes an open run (if any)" — correct, but the string-at-EOF sub-case
belongs in the item's declared expected result for `test_tokenize_runs`
extension (the plan's Hardening note says no string-at-EOF case exists in
test_lexer.py:26-40 — confirmed, the hand-written expectation covers the
closed-string case only).

Sharp edge 2 (not in the plan): position accounting for the char that opens
a run. Current code advances col past the opening `"` *before* entering
`scan-run` (lexer.asl:158: `(scan-run (run-string) s (+ i 1) line (+ col 1)
line col "\"")` — start position is the quote's position, the state's
line/col is already past it). For `:`, same shape (:162). For int runs the
opening digit is *not* pre-consumed (:160: `(scan-run (run-int) s i ...
line col line col "")` — the digit is the first run char). A fold step that
treats all three openers uniformly will get one of these wrong. The plan's
§8 ("run start positions are captured when the run opens, lexer.asl:154-159")
covers the start position but not the asymmetric pre-consumption; add it.

### 2. Builtin surface — all verified present with Python lowerings

Measured in `prelude/prelude.json` this session (name → line → `py` field):
`fold` :754 → `_agentscript.fold({0}, {1}, {2})` (:758); `string-chars`
:479 → `list({0})` (:485); `string-length` :314 → `len({0})`; `str` :336 →
`"".join([{*}])`; `string-slice` :347 → `_agentscript.str_slice(...)`;
`string-to-int64` :512 → `_agentscript.to_int({0})`; `list-head` :622 →
`_agentscript.at({0}, 0)`; `list-tail` :633 → `_agentscript.tail({0})`;
`list-cons` :644 → `([{0}] + {1})`; `list-reverse` :666 → `{0}[::-1]`.
Runtime: `runtime.py:189-193` (`fold`), :141 (`at`), :145 (`tail`).

Bare `df` as a value argument to `fold`: **transpiles**. Empirical:
transpiling `bench/algo/histogram.agentscript` emits
`counts = _agentscript.fold(tally, {}, words)`. Static: `df` names land in
`Transpiler.local` via `unit_names` (to_python.py:129-147), are emitted as
bare names by `atom`/`resolve` (to_python.py:476-487, :94-95), and
`Transpiler.call` formats the builtin template with the bare name as `{0}`
(to_python.py:374-378). `runtime.py:189-193` accepts any Python callable.
Corpus precedent: `grammar/corpus/valid/26-map-lifecycle.agentscript:21`
(`(fold tally ...)`), exercised under a `; run:` header (:7) so it counts in
the lock — which is why `fold`'s instantiations already include
`(fn [(Map String Int64) String] -> (Map String Int64))`.

Residual (low): no checked-in source passes a **record** as a fold
accumulator; `histogram` uses a Map, corpus uses Int64. Records lower to
dicts (to_python.py `defschema` :188-195) and `fold` treats the accumulator
opaquely, so there is no mechanism by which this fails, but it is a first
for the repo — Item 2's regression suite is the check. Plan Risk 1 already
covers the transpiler-choke variant; extend it to name the record-accumulator
first.

### 3. No record-update constraint — correctly acknowledged

Plan Item 2 states "no field-update syntax exists … rebuild the `ScanState`
record each step" and backs it with per-char reconstruction. Verified there
is no update form in the grammar's lowering surface (`to_python.py` `expr`
:245-366 handles let/if/cond/match/try/fn/field_access/ctor/call and nothing
that mutates). Per-char rebuild is O(bytes) allocations of small dicts —
`ast.asl` at 17628 chars is ~17.6k dict constructions, negligible against
CPython's normal allocation rate, and it does not reintroduce recursion
anywhere (the step function is a `df` with one expression body per branch;
the only recursion in the new shape would be if the implementer re-nested a
helper per char, which the plan's "no action planned" note guards against).
Risk §4's O(run²) `str` accumulation observation is accurate (each `(str acc
ch)` copies); runs in this codebase are bounded by line length. No action
needed; the acknowledgment is sufficient.

### 4. Reader/AST residual recursion — Item 3's logic is sound; F2 fixes its selector

Depth estimate for `ast.asl` after Item 2: `read-forms` recurses once per
top-level form (ast.asl:70-78) — 52 forms measured; `read-one`/
`read-seq-items` per list item and nesting level (ast.asl:81-104) — the
deepest single form in ast.asl is a `df` with ~10 items and at most 3
nesting levels; `decl-forms` per declaration (:192), `collect-vars` per
type var (:224), `find-opt` per field (:139). Sum is well under 300 frames
against CPython's 1000 default, including harness frames (harness.py runs
the transpiled module via `runpy.run_path`). The plan's "verify, fix only
on red" stance is the correct one; a pre-emptive rewrite of working code is
what the repo's conventions argue against. Item 3's contingency (fold-ify
`read-forms`/`read-seq-items` with `(Pair SExpr remaining-toks)` state,
`list-head`/`list-tail` verified at prelude.json:622/:633) is implementable
with the same verified surface. The one defect is the selector (F2).

On the wider file set: every one of the 20 failing files is lexer-bound
first (the probe fails inside `tokenize` before the reader runs), and all
16 non-ast.asl files have 4–32 top forms, so the same depth argument
applies. After Item 2, expect all 20 green unless `ast.asl` specifically
exceeds the budget — exactly what Item 3 measures. This strengthens F1: the
plan's risk framing ("32 non-parser package files … unverified") understates
how much the probe already shows.

### 5. Gate integrity

- Item 1 gate fails today verbatim as stated (re-measured:
  `ERROR: file or directory not found`); passes only when all 37 files
  render. With F1 fixed, the declared intermediate red state is honest.
- Item 2 gate: the same command, declared expected result must be the full
  20-file green (F1). The plan's sequencing rationale (test first so the
  red run is on record) is correct and matches the steps protocol's
  "fails now, passes when done".
- Item 3 gate: right idea, broken selector (F2).
- Item 4 gate: runs the phase gate + both regression suites + repo gates —
  the task's required triple is present, but the repo-gate subset is
  incomplete (F3) and its closure-audit rationale is wrong (F4).

## Risks logged (uncertainty, not fact)

- R1: record-as-fold-accumulator has no repo precedent; believed safe by
  construction (dicts, opaque accumulator) but untested until Item 2.
- R2: the exact frame count of the harness + `runpy` + transpiled-module
  chain is not measured; the depth estimates above assume it stays
  three-digit-low. If `ast.asl` fails after Item 2, Item 3's red path fires
  and the estimate was wrong — the plan handles this.
- R3: `exec_smoke.asl` and `ast_driver.asl` are lexer-bound but are also
  *executed* by the existing 8-test suite (harness.py), which passes today
  only because those drivers are small. After Item 2 they stay in the
  suite's input set; no change expected, noted for completeness.

## Verdict

`approve-with-amendments`

Required amendments (blocking):

1. **F1**: Item 1 and Item 2 replace the five-file failure/expectation set
   with the measured 20-file list (verbatim above); Item 2 declares all 20
   green post-rewrite with `ast.asl` deferred to Item 3; Risks §5 restated
   as a recorded measurement.
2. **F2**: Item 3's `-k ast` selector replaced with an exact node-id or
   `ast.asl and not ast_driver` form, and the chosen selector's output
   recorded.
3. **F3**: Item 4 runs the full AGENTS.md gate list or carries a per-gate
   "unaffected because input set excludes packages/" justification for each
   omission; Risks §3 restated using the measured lock state (`fold` and
   `string-chars` already in `instantiations`, `executed: 107`).
4. **F4**: Risk 2 and Item 4's closure-audit rationale corrected against
   closure_audit.py:76 — the audit scans `grammar/corpus/valid` + spec
   examples only; `packages/` is outside its input set.

Recommended (non-blocking):

5. **F5**: correct the seven drifted body-line citations in Item 2's
   semantic list (exact replacements listed in F5).
6. Lens-1 sharp edge 2: add the asymmetric run-opener pre-consumption
   (`"` and `:` pre-consume, digit does not) to Item 2's semantic list.
