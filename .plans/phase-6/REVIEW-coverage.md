# Phase 6 — REVIEW-coverage

## Lens
Coverage. Did the plan's acceptance axes (ambiguity, edit/AST/search, formatter idempotence,
plus the three PHASES.md re-integrations and the observability/budget ratchets) end in numbers
that can regress? For each work item, what would a conformant-but-wrong implementation still
pass?

## Verdict
**reject** — three blockers, three majors.

---

## Blockers

### B1 — W4 (formatter idempotence) is a trivially-satisfiable gate

The plan defines the formatter gate as:

> D6 — `tools/fmt/fmt.py --check <corpus-dir>`. For each fixture: format once, format the
> output again, fail unless pass-2 output equals pass-1. (PLAN.md:166)

A no-op formatter `def format_source(s, p): return s` satisfies this trivially: pass-1 returns
the input, pass-2 returns the input, equality holds. So does a formatter that drops every
comment (the same drop happens on both passes), a formatter that reorders all forms
(deterministic reordering is idempotent), or a formatter that injects a single newline
between top-level forms (added on pass 1, already there on pass 2 — equality holds).

The plan defers the *real* formatter coverage to `tools/fmt/t/test_fmt.py`, which the stash
provides and which has three claims (idempotence, tree preservation, comment survival). The
gate listed in §4 is `tools/fmt/fmt.py --check grammar/corpus` — that gate alone, executed in
isolation, accepts any of the conformant-but-wrong formatters above. The plan's acceptance
battery mentions `pytest tools/fmt/t tools/t tools/bindgen/t` (PLAN.md:244), but the W4 item
itself is defined only by the `--check` command, and there is no in-W4 assertion that pytest
must run as part of W4's completion. A reviewer or implementer could ship W4 as the CLI gate
alone and consider axis 3 satisfied.

Evidence:
- PLAN.md:160-167 — W4 definition: "format once, format the output again, fail unless
  outputs are equal".
- PLAN.md:242-248 — acceptance battery lists `fmt.py --check` and the pytest of
  `tools/fmt/t` as **separate** items; the gate for W4 is the former.

What would make it right: W4 must additionally require the pytest pass over `tools/fmt/t` as
part of its gate, not as a separate end-of-phase check. Or: change the `--check` semantics
to include the three stash claims (tree preservation, comment survival) inline. The plan's
own PHASES.md acceptance for Phase 6 says "the formatter is idempotent on the corpus", which
idempotence alone trivially satisfies — but the agent-facing product goal (goal 4 in
ROADMAP.md, PHASES.md:54-58) is that the formatter produce canonical AgentScript source;
the gate does not enforce that.

### B2 — W1's ambiguity count can be silently meaningless

The plan pins the mechanism (Lark `_ambig` under `ambiguity="explicit"`; PLAN.md:30-35,
PLAN.md:104-111) and reproduces the 219 baseline against the corpus. That part is solid.
But the gate described is:

> parse `valid` + `semantic` + `modules`, count `_ambig` nodes, compare against
> `grammar/ambiguity.lock`; `--write` records. (PLAN.md:34)

The lock is a single number. A gate that "fails if greater" makes regressions visible;
W2 (PLAN.md:120-130) names the l-b1b8 dead alternatives and is expected to reduce the
number. The conformant-but-wrong: an implementer who *raises* the number with `--write`
("we made it worse but it locks the new baseline") passes `--check` forever after, even
though W2's intent was a strictly smaller number. W2 says "fail with a count below the
lock until --write records the new figure" (PLAN.md:127), which is the right invariant —
but that invariant is not stated in W1's gate. W1's gate alone accepts a `--write` of any
number, including one larger than the baseline.

This is a weaker form of B1: the lock-ratchet only catches *regressions*. Phase 6's
acceptance criterion says "ambiguity is surfaced and **driven to zero or recorded**"
(PHASES.md:55). "Driven" implies a downward trajectory, which `--check` does not enforce.

Evidence: PLAN.md:104-117 (W1 gate description, no mention of direction); PLAN.md:120-130
(W2 introduces the direction in passing); PHASES.md:54-56 ("driven to zero or recorded").
The reproducer I ran (.venv/bin/python ... ambiguity='explicit' ...) shows 219; the gate
command would accept any number ≤ current lock as pass, and `--write` is a free pass to
raise it.

What would make it right: the auditor must distinguish "improvement" from "regression" by
direction, OR the gate must read the lock as `>=` baseline and accept new locks only with
an explicit `--accept-regression` flag (or comment in the lock file). The plan's "W2
fails below the lock until --write records" pattern is right for W2; W1 must encode that
intent at the gate level, not the work-item level.

### B3 — W5 (edit/AST/search) tests are not specified, only enumerated

The plan says W5's tests are "D5's replace/delete/insert, byte round-trip, re-parse +
idempotent format" (PLAN.md:177). That is a list, not a test plan. The central coverage
question for edit ops is: are the tests asserting *real* semantics, or just that the CLI
exits 0?

Reading D5 (PLAN.md:65-76) carefully: "Tests: node-addressed replace, delete, insert;
delete+re-insert round-trip reproduces the original bytes; replace output re-parses and
formats idempotently (D5 rides on W3's formatter)." This is closer to a real test plan
than B1's gate, but it has a gap:

- **Per-node-kind coverage is not asserted.** The plan enumerates the three ops but not
  the constructs they exercise. The test that catches "replace on an `expr` always
  succeeds" is a test that exercises replace on every form class (defun, defschema,
  match arm, cond clause, ctor, record, qualified, field access). Without per-kind
  assertions, an implementation that handles only `expr` (the most general class) and
  crashes on, say, a `qualified` body in a `defschema` passes the happy-path test.

- **The byte round-trip test catches a no-op delete** (delete does nothing → re-insert
  puts nothing back → equality trivially holds only if delete also does nothing on
  re-insert which contradicts "byte round-trip"). Actually that does work, but it does
  not catch a delete that is silent (delete range X but emit empty file).

- **The "replaces output re-parses and formats idempotently" assertion** rides on W3's
  formatter and on the Lark parser. Both are tested in isolation elsewhere; the
  end-to-end test depends on both gates staying green, which the plan acknowledges but
  does not pin. If W3 ships a formatter that emits syntactically invalid output
  (specifically, output that re-parses to a different tree), the edit test would fail
  with a message pointing at the formatter, not the edit — and a fix that disables
  one of them could "pass" the edit test by making the assertion vacuous.

Evidence: PLAN.md:65-76 (D5 specification — three ops enumerated, no per-kind coverage);
PLAN.md:177 ("D5's replace/delete/insert, byte round-trip, re-parse + idempotent format" —
restated in W5); no `tools/t/test_edit.py` exists yet (the gate at PLAN.md:181-183 fails
on missing file, by design).

What would make it right: D5/W5 must enumerate the form classes the tests cover. A concrete
list: `(defun f [] -> T body)`, `(defschema S field+)`, `(defenum S variant+)`, `(let bs
body+)`, `(if a b c)`, `(cond cls+)`, `(match e arms+)`, `(try e)`, qualified, field
access, ctor. The three ops × N form classes should be a parametrised test, not a single
happy path. The plan also does not state whether edit operates on the *source bytes* (in
which case the tree-sitter byte ranges are authoritative) or on the *tree* (in which case
it must round-trip through printing) — both are listed but the test for "byte round-trip
preserves the tree-sitter CST" is not stated.

---

## Major findings

### M1 — Token budget ratchet (W7) accepts growth with `--write`

Same shape as B2. D3 says "fails when the count exceeds the lock; `--write` records"
(PLAN.md:42-44). A change that *grows* HANDBOOK.md by adding a builtin is the whole point
of vocabulary work; the lock must move with it. But "accepts growth" is fine; the failure
mode is that the gate's pass criterion is `len(file) <= lock`, which makes a regression
visible only when someone forgets to run `--write`. A real ratchet needs CI to run
`--check` and the implementer to run `--write` in the same commit; the plan does not say
that. Without it, the lock is a one-shot number, not a ratchet. Same mitigation as B2:
state the commit-coupled invariant explicitly.

### M2 — Span coverage fraction (W8) is a metric that can lie

W8 measures "variants-with-`span`-field / total `Expr` variants" (PLAN.md:62-67).
Baseline 1/17. The conformant-but-wrong: add `pub span: Span` to every variant *without
populating it* (e.g. `Span::default()` everywhere). The fraction rises to 17/17, the
lock moves with `--write`, and `tools/t/test_interp_diag.py` (the functional test) still
passes *if* the runtime error paths it exercises happen to hit a populated span. There is
no test that asserts every `eval.rs:Err(` site is reachable from a *populated* span.

What would make it right: the functional test must enumerate the 29 `Err(` sites (or
the runtime error paths the plan names: `Ident`, `Qualified`, `Call`, `FieldAccess`,
`If`, `Cond`, `Match`, `Try`, `Ctor`, `Record`, `Let`) and assert each one reports a
*non-default* span. The current plan asserts only "stderr matches `path:line:col:`"
(PLAN.md:225-227), which a default `Span{line:0, col:0}` produces as `path:0:0:` — a
prefix that matches the regex.

Evidence: PLAN.md:62-67 (D4 definition); PLAN.md:218-228 (W8 specification).
crates/agentscript-interp/src/eval.rs (29 `Err(` sites referenced but not enumerated as
test targets); `ast.rs:64` `pub enum Expr` with 17 variants — verified, awk count
returns 17.

### M3 — The plan's `43 parseable fixtures` claim is wrong, but the gate is fine

The plan claims 43 parseable fixtures (PLAN.md:24, PLAN.md:108-110). I count 77:
29 valid + 42 semantic + 6 modules = 77. (Probe: `total files matched: 77, parseable:
77, total_ambig: 219`. The 219 figure is correct, but the corpus count is not 43.) The
gate works because it globs the same patterns I gloved; the baseline figure is wrong but
the lock-ratchet would self-correct on first `--write`. Not a blocker, but the
baseline-claim should be corrected in PLAN.md.

Evidence: `ls grammar/corpus/valid/*.agentscript | wc -l` = 29; same for semantic = 42;
modules = 6. PLAN.md:24 says "43 parseable fixtures".

---

## Non-blocking

- **W6 (bindgen re-integration)** is well-specified. The expected fixture may need edits
  per the plan (PLAN.md:188-191); that is acknowledged. The test contract
  (`output_matches_the_checked_in_expectation`) is a snapshot test that catches
  regressions but not silent corruption — acceptable for a one-shot generator.

- **W3 formatter re-integration** correctly identifies the form-keyword drift between
  the stash and the current grammar (PLAN.md:138-145). The accepted gate
  (`pytest tools/fmt/t -q`) covers the three stash claims and is sufficient provided
  W4 fixes B1.

- **Acceptance battery** (PLAN.md:240-248) covers the right things modulo B1, B2, M1.

- **Risks section** (PLAN.md:251-279) is honest: D5's mechanism is unverified (the
  `tree-sitter` Python package is not installed — `.venv/bin/pip show tree-sitter`
  returns "Package(s) not found", confirming the risk); 14-sequenced-bodies residual
  attribution work may grow; formatter fit is unverified.

- **D5 fallback** (PLAN.md:170) — the Rust edit CLI fallback is the right escape hatch,
  with the explicit note that the ops, CLI surface, and tests are unchanged. The risk
  is that the tests are written against the CLI surface, not the mechanism, so the
  swap is contained.

- **Plan-derived number for `13-module-program.agentscript`** (PLAN.md:25 lists
  `14-sequenced-bodies` at 25 as the largest per-file count) — verified by my probe
  (it returns 25 from the same fixture).

---

## Conformant-but-wrong implementations the plan would accept

| # | Description | What passes | What gate is meant to catch it | Verdict |
|---|---|---|---|---|
| 1 | A no-op formatter: `def format_source(s, p): return s` | W4 (format twice == format once) | The three stash tests in `tools/fmt/t/test_fmt.py` (tree preservation, comment survival) catch it — IF they are run as part of W4 | Plan runs them only at end-of-phase acceptance battery, not in W4 |
| 2 | A formatter that drops every comment | W4 idempotence (drop happens once, then format(dropless) == format(dropless)) | `test_every_comment_survives` in stash | Not in W4's gate |
| 3 | An ambiguity auditor whose count is wired to `--write`'s argument | W1 --check | Nothing — the lock is whatever the auditor reports | W1 must be verified to read the lock from disk, not from internal state |
| 4 | An ambiguity auditor that parses with `ambiguity="resolve"` (current `parse.py` mode) and counts 0 — because `resolve` collapses `_ambig` | W1 --check returns 0 | W2 must remove the dead `pattern` alternatives first and confirm the number goes up first, then down | Plan does not require the before/after relationship |
| 5 | A token budget ratchet whose `--write` is run without `--check`, lock grows by 30%, plan reports "vocabulary grew" | W7 --check (lock is now higher than file) | A commit-coupled invariant | Not stated in plan |
| 6 | Span coverage rises from 1/17 to 17/17 with all spans defaulted | W8 --check | Functional test asserts non-default span on every error site | Plan asserts only that stderr matches `path:line:col:`, which `path:0:0:` satisfies |
| 7 | Edit `replace` operates only on the `expr` rule — crashes on `defschema` body | Per-fixture happy path | Per-form-class parametrised test | Plan enumerates three ops, not per-form coverage |
| 8 | Edit `delete` does nothing on `--range` (a no-op); the round-trip test passes because re-insert puts nothing back and "delete+re-insert reproduces original bytes" trivially holds if both ops no-op | Round-trip test | Assert that the deleted range's bytes are *gone* from the post-delete file, not just that round-trip == original | Plan does not state this |
| 9 | Formatter that deterministically reorders top-level forms (legal in S-expressions) | Idempotence (reorder twice = reorder once) | Tree preservation test (reorder changes tree) | Not in W4's gate |

---

## Verified

- PLAN.md:24 baseline 219 ambiguity count is reproducible. Probe:
  `.venv/bin/python ... ambiguity='explicit' ...` returns 219 over valid + semantic +
  modules. Per-file counts include `14-sequenced-bodies.agentscript` at 25 and
  `02-match.agentscript` at 10, matching the plan's claim.

- PLAN.md:27 token-budget baseline 12,779 chars is exact. `wc -c
  prelude/HANDBOOK.md` returns 12779.

- PLAN.md:28 — `crates/agentscript-interp/src/ast.rs` carries `IntLit` with a `Span`
  field (ast.rs:53-63, line 64 `Int(IntLit)` variant in `Expr`). The plan's
  "1 of 17 Expr variants carries a Span" is correct (verified: `awk ... | grep -cE
  '^\s+(Int|Float|Str|Bool|Unit|Ident|Qualified|Let|If|Cond|Match|Try|Fn|Ctor|Record|FieldAccess|Call)\b'`
  = 17; only `Int` has the inner `Span`).

- PLAN.md:33-35 D2 mechanism: `Lark(GRAMMAR.read_text(), start='start',
  parser='earley', ambiguity='explicit')` — verified by my probe. The plan's local
  copy of the parser is the right call (`parse.py:26` uses `ambiguity="resolve"`,
  changing it would push `_ambig` trees to every consumer).

- PLAN.md:42-44 D3 token-budget mechanism: `len(prelude/HANDBOOK.md)` is the right
  metric; the 12,779 baseline matches.

- PLAN.md:84-87 W3 token-set drift (`DEFENTRY`/`DEFEXTERN`/`DEFOPAQUE` in the stash,
  absent from current `parse.py:24-28` `FORM_KW`) is real. Confirmed by reading
  `parse.py:24-28` and `git show stash@{0}^3:tools/fmt/fmt.py | head`.

- PLAN.md:170-180 W5 distributor stash reference: `git ls-tree stash@{0}^3` shows
  exactly the files claimed (`as-lang`, `tools/fmt/fmt.py`, `tools/fmt/t/test_fmt.py`).
  The b614ec8 commit's bindgen files exist as the plan claims.

- PLAN.md:227 `tools/span_coverage.py` parses `ast.rs` and counts
  variants-with-span. Mechanism is sound; the missing piece is per-`Err(`-site test
  coverage (M2).

- PLAN.md:166 D6 idempotence gate command `.venv/bin/python tools/fmt/fmt.py --check
  grammar/corpus` is correctly named — file does not exist yet, the gate fails as
  advertised.

- PLAN.md:181-183, 191-193, 199-201, 219-221 — all gates fail as advertised because
  the files do not yet exist. This is correct.

## Unverified

- The `tree-sitter` Python binding's compatibility with this grammar (`D5` mechanism,
  PLAN.md:65-76). Confirmed not installed (`.venv/bin/pip show tree-sitter` →
  "Package(s) not found"); whether `tree-sitter build -o` produces a loadable shared
  library for this grammar was not tested in this review session (the plan correctly
  flags this as a risk at PLAN.md:253-256).

- Whether the `14-sequenced-bodies.agentscript` 25-ambiguity source can be cheaply
  reduced (PLAN.md:255-258 names this risk). The 25 figure is real; the cost of
  reduction is unestimated.

- Whether the stash's `test_fmt.py` test corpus (`backend/t`, `bench`, `examples`)
  still exists in the renamed tree. PLAN.md:138-145 implies it does not (the plan
  rewrites the `CORPUS` to `valid + semantic + modules`); whether the stash's probe
  subject (PROBE_SUBJECT, with `defopaque`, `defentry`, `defextern` keywords) needs
  rewriting against the current grammar — the plan acknowledges this implicitly
  through the "token set adaptation" requirement (PLAN.md:144).

- Whether `differential.py`'s program mode compares stderr text or only status/prefix
  (PLAN.md:262-265). The risk is correctly named; I did not re-read
  `backend/differential.py` in this review.

- M3 (corpus count 43 vs actual 77). I counted 77 parseable fixtures via the same
  glob patterns the plan implies. The 219 figure is correct; the 43 figure is wrong.
  Self-correcting on first `--write`, but the plan's stated baseline is incorrect.
