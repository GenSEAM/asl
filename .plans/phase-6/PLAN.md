# Phase 6 — The agent-facing surface, measured

## §1 Scope and acceptance

Phase 6 gives goal 4 (`.plans/PHASES.md` Phase 6) its first regressible numbers. Three
acceptance axes, each ending in a number a command checks:

1. **Ambiguity is surfaced and driven to zero or recorded** — an Earley ambiguity count over
   every parseable corpus fixture, ratcheted in a lock file.
2. **Edit/AST/search are covered by tests** — structured edit operations (point/range), JSON
   AST access, and structural search, wired into the distributor and exercised by pytest.
3. **The formatter is idempotent on the corpus** — formatter output equals its own output on
   the second pass for every corpus fixture, checked by a command, with the formatter's test
   suite (tree preservation, comment survival) part of the same gate.

Plus the two re-integrations PHASES.md names for this phase (formatter, bindgen), the
distributor that hosts the new subcommands, the token budget ratchet, and source spans on
interpreter runtime errors.

**Measured baselines (this session, commands shown; the lock, not this prose, is the
authoritative figure once W1/W7/W8 record them):**

- Earley ambiguity, Lark 1.3.1, `parser="earley", ambiguity="explicit"`, counting `_ambig`
  nodes over `grammar/corpus/valid/*.agentscript` (29) + `grammar/corpus/semantic/*.agentscript`
  (42) + `grammar/corpus/modules/**/*.agentscript` (6; note the subdirectories — the glob must
  be recursive): **219 over 79 parseable fixtures**, deterministic across repeat runs. Largest
  per-file contributors: `14-sequenced-bodies` at 25, `02-match` at 10. Re-measure: build the
  grammar as `Lark(GRAMMAR, start="start", parser="earley", ambiguity="explicit")` and count
  trees with `data == "_ambig"`. **The lock (`grammar/ambiguity.lock`) is authoritative** —
  the auditor's recursive glob measures 79 fixtures (not the 77 this prose once estimated), and
  post-W2 it locks 140 over 79.
- `prelude/HANDBOOK.md`: **12,749 characters** (`len(read_text())`; the file is 12,779
  *bytes* by `wc -c` — the budget unit is characters, per D3's mechanism).
- `crates/agentscript-interp/src/ast.rs`: `Expr` has 17 variants; **4 of them (`Float`, `Str`,
  `Bool`, `Unit`) cannot reach any of `eval.rs`'s 29 `Err(` sites** (no `Expr::Float|Str|Bool|Unit`
  site exists in eval.rs), so the failable subset is **13**. Only `IntLit` carries a `Span`
  today (ast.rs:52–62) → baseline **1 of 13** failable variants. `eval.rs` has 29 `Err(` sites,
  none located.

### Decisions (recorded, each the laziest correct option)

**D1 — Distributor: re-integrate the stashed `as-lang` shim, renamed `agentscript`, and extend
it.** The stash (`git show 'stash@{0}^3:as-lang'`, 202 lines) defines the two contracts callers
write against — `--json` emits `{file, line, col, rule, message}` and exit = problem count —
and delegates to the existing scripts. Building a distributor from scratch would re-derive
those conventions for no gain. It lands at the repo root as `agentscript` (Python script, run
as `.venv/bin/python agentscript ...`). The shim as stashed **cannot start** against today's
tree — it reads `prelude.json["targets"]` (no such key; actual keys: `$comment, version,
runtime, special_forms, types, builtins`) and calls `check.parser()`, `check.check_file(parser,
f)`, `check.import_cycles(models)`, `check.target_capabilities(models, target)` (stash lines
33, 82–90), none of which exist; the current checker surface is the 32-line CLI
`checker/check.py` over `checker/resolve.py:641` `check_file(path, roots) -> list[Diagnostic]`.
W5 therefore includes rewriting those call sites (see D1a). With that scoped, the rename work
is: `BACKENDS` pruned to what exists (`py`, `rs` — the stash's `sw` has no `to_swift.py` here;
`differential.py` drives exactly py/rs/interp), paths `tree-sitter-as-lang` →
`tree-sitter-agentscript`, `*.as` → `*.agentscript`, new subcommands `ambiguity`, `tokens`,
`search`, `edit` delegating to the phase's new tools. The name `agentscript` collides with
nothing (no `.venv/bin` or `node_modules/.bin` entry; the only Cargo binary is
`agentscript-interp`; `package.json` has no `bin` field).

**D1a — `check` re-pointing.** `cmd_check` delegates to the current checker: run
`checker/check.py <files> --root ...` as a subprocess (its exit code is already the diagnostic
count, matching the shim's contract) or import `resolve.check_file` directly — implementer's
choice, decided by which keeps `--json` diagnosis trivial. `TARGETS` for `build` comes from
`BACKENDS` keys, not `prelude.json`. The stash's `--target` (check-side capability filtering)
and `--rules` flags have **no counterpart in the current checker**; they are dropped unless
the orchestrator explicitly re-scopes them — `build --target {py,rs}` stays.

**D2 — Ambiguity metric: count Lark Earley `_ambig` nodes under `ambiguity="explicit"`.**
Mechanism verified this session (see baseline above). The audit is
`grammar/ambiguity_audit.py --check`: parse `valid` + `semantic` + `modules` (rglob for
modules), count `_ambig` nodes, compare against `grammar/ambiguity.lock` under D7's
exact-match rule; `--write` records. Invalid fixtures are excluded (they must not parse at
all). "Driven to zero or recorded": the dead `pattern` alternatives (`l-b1b8`,
`grammar/agentscript.lark:91–97` — the seven per-prelude-case alternatives `OK`, `ERR`,
`SOME`, `NONE`, `LIST`, `CONS`, `PAIR`) go first; the live alternatives `literal | IDENT |
WILDCARD` (lines 98–100) stay. In-memory simulation this session: removing exactly 91–97
keeps all 77 fixtures parsing and drops the total 219 → **140** (the lock records the real
post-removal figure). Residual sources are then examined and the cheap ones removed;
whatever remains is the recorded number. No number is faked at zero.

**D3 — Token budget: deterministic character count, no tokenizer.** A real tokenizer adds a
dependency and a determinism question for a number whose only job is to regress when the
handbook grows. `prelude/budget.py --check` records `len(prelude/HANDBOOK.md)` characters in
`prelude/budget.lock` and fails on any difference from the lock (D7); `--write` records a new
figure in the commit that earns it. Baseline 12,749 chars.

**D4 — Observability: thread `Span` into every `Expr` variant that can fail at runtime.** The
tree-sitter CST carries line/col for every node (`propagate_positions=True` on the Lark side;
`cst.rs` already lowers positions into `Span`, cst.rs:70–73), so plumbing spans is data
movement, not new parsing. `ast.rs` `Span{line, col}` (ast.rs:58–62) is extended where
needed; runtime errors print `path:line:col: message`; exit codes stay 0/1/2 (`main.rs:15-18`).
The regressible number: variants-with-span / **failable** variants, computed by
`tools/span_coverage.py` from `ast.rs` and locked in `crates/agentscript-interp/span.lock`.
The denominator is **13** (the failable subset); `span.lock` records the four excluded
variants (`Float`, `Str`, `Bool`, `Unit`) with the reason — they can never reach an `Err(`
site, so span-plumbing them would reward work no diagnostic needs. Coverage of the *value*
(not just the field) is enforced by W8's functional test, not by the fraction.

**D5 — Structured edits: tree-sitter `Node` byte/point ranges, Python binding, three ops.**
New dev dependency `tree-sitter` (Python) in the venv, with the grammar compiled to a shared
library by the already-installed tree-sitter CLI (`tree-sitter build -o` — verified to build
a loadable .so for this grammar; the Python `Language()` load remains the unverified link,
see Risks). Justification: no existing tool exposes programmatic `Node` ranges —
`crates/agentscript-ts` exports only `language()`, and the CLI only runs queries. Ops (all
subcommands of `agentscript`), operating on **source bytes** (the tree-sitter byte ranges are
authoritative; the file is rewritten in place):

- `agentscript ast <file> --json` → a JSON array of nodes:
  `{"type", "field", "byteRange": [start, end), "start": {"row", "col"}, "end": {"row", "col"},
  "children": [...]}` (byte offsets 0-based; rows/cols 0-based, matching tree-sitter Points).
- `agentscript search <file> --query <scm>` → JSON array of matches:
  `{"capture", "byteRange", "start", "end", "text"}`.
- `agentscript edit replace <file> --range <l>:<c>-<l>:<c> --text <s>` / `edit delete --range`
  / `edit insert --at <l>:<c> --text <s>` → JSON receipt
  `{"file", "op", "applied", "range", "newByteLen"}` on stdout, exit 0; a failed application
  prints `{"file", "op", "error"}` and exits non-zero.

Tests (the contract, not a list of ops): parametrised over **form classes** — `defun`,
`defschema`, `defenum`, `let`, `if`, `cond`, `match` arm, `try`, `ctor`, `record`, `qualified`,
`field access` — each op exercised against each applicable class; delete asserts the deleted
range's bytes are **gone** from the post-delete file (not only that a round-trip reproduces
the original); delete+re-insert round-trip reproduces the original bytes exactly; replace
output re-parses and formats idempotently (D5 rides on W3's formatter). If the Python binding
proves unusable for this grammar, the fallback is an edit CLI in a **new `[[bin]]` target**
(`crates/agentscript-ts` is `staticlib + rlib` with no bin today — the fallback names the new
target or a new crate); the ops, JSON surface and tests are unchanged.

**D6 — Formatter correctness gate: `tools/fmt/fmt.py --check <corpus-dir>` plus its test
suite.** For each fixture: format once, format the output again, fail unless pass-2 equals
pass-1; print a per-file verdict. Idempotence alone is trivially satisfied by a no-op
formatter, so the gate **also** requires `tools/fmt/t` green (the recovered stash tests: tree
preservation, comment survival) and a **canonical-output fixture** — a checked-in
`tools/fmt/t/canonical.agentscript` whose expected formatted form is checked in as
`canonical.expected.agentscript` and asserted — which catches a formatter that transforms
nothing (or drops everything). The corpus is *not* re-canonicalised (formatting 77 fixtures
would churn files whose content is bench-measurement input); only idempotence plus the
fixture-level assertions are enforced. `agentscript fmt` gains `--check` as a pass-through.

**D7 — Ratchet semantics: every new lock is exact-match.** `ambiguity.lock`,
`budget.lock`, and `span.lock` all follow the `prelude/coverage.lock` precedent (AGENTS.md):
`--check` **fails on any difference** between the measured figure and the lock — up *or*
down — and `--write` records a new figure deliberately, in the commit that earns it. A loose
"fail if greater" is explicitly rejected: it lets an improvement pass silently without being
recorded (the W2 case) and lets a `--write` of any number, including a regression, stand.
Directional intent is carried by the work items (W2 must land a strictly smaller ambiguity
figure), not by the check.

## §2 Inventory

**Recovered from git objects (materialised into the working tree, then adapted). Exact
recovery commands (note: `git stash show -p 'stash@{0}^3'` does not work — `stash@{0}^3` is
the untracked-files commit, not a stash entry; use `git show`):**

```bash
git show 'stash@{0}^3:as-lang'            > agentscript       && chmod +x agentscript
git show 'stash@{0}^3:tools/fmt/fmt.py'   > tools/fmt/fmt.py
git show 'stash@{0}^3:tools/fmt/t/test_fmt.py' > tools/fmt/t/test_fmt.py
git show b614ec8:tools/bindgen/from_pyi.py > tools/bindgen/from_pyi.py
git show b614ec8:tools/bindgen/t/frames.pyi       > tools/bindgen/t/frames.pyi
git show b614ec8:tools/bindgen/t/frames.expected.as > tools/bindgen/t/frames.expected.agentscript
git show b614ec8:tools/bindgen/t/test_bindgen.py   > tools/bindgen/t/test_bindgen.py
```

**New:** `grammar/ambiguity_audit.py`, `grammar/ambiguity.lock`, `prelude/budget.py`,
`prelude/budget.lock`, `tools/span_coverage.py`, `crates/agentscript-interp/span.lock`,
`tools/t/test_edit.py`, `tools/t/test_interp_diag.py`,
`tools/fmt/t/canonical.agentscript`, `tools/fmt/t/canonical.expected.agentscript`.

**Modified:** `grammar/agentscript.lark` (dead `pattern` alternatives, lines 91–97),
`crates/agentscript-interp/src/{ast.rs,cst.rs,eval.rs}` (spans), plus the new files above.
`grammar/tree-sitter-agentscript/grammar.js` is **deliberately left unchanged**: removing the
lark alternatives leaves grammar.js's seven named pattern rules unmatched on the lark side,
but the accepted language is unchanged (`validate.py` compares verdicts across both grammars
and runs the token-identity probes, which fail the gate on drift), `queries/searches.scm`
references no pattern nodes, and changing grammar.js *would* change node shapes — the worse
drift. This is a recorded decision, not an omission. `prelude/generate.py` untouched (budget
is a separate script, keeping the generator's `--check` scope unchanged); `package.json`
unchanged (`tree-sitter build` needs no change).

**Constraints carried through every item:** the full AGENTS.md gate battery stays green after
each item; no existing gate is weakened — all new gates are additive, and where a v1 gate was
too weak (W4's idempotence-only check) it is tightened, never relaxed.

## §3 Work items (ordered)

### W1 — Ambiguity audit and ratchet
- **What:** `grammar/ambiguity_audit.py` — builds `grammar/parse.py`'s grammar with
  `ambiguity="explicit"` (a local variant of the cached parser; `parse.py` itself is NOT
  changed, so no consumer sees `_ambig` trees), parses `grammar/corpus/{valid,semantic,modules}`
  (modules via recursive glob — its fixtures live in subdirectories), prints per-file `_ambig`
  counts and the total, and in `--check` mode compares the total to `grammar/ambiguity.lock`
  under D7's exact-match rule; `--write` records. The auditor reads the lock from disk — the
  check compares a fresh measurement to the file, never to an internal value.
- **Why:** acceptance axis 1 needs a computable metric before anything can be driven down;
  the lock is what makes "recorded" mean "can regress" in either direction.
- **Gate (fails now):** `.venv/bin/python grammar/ambiguity_audit.py --check`
  ```
  /Library/Frameworks/Python.framework/Versions/3.13/Resources/Python.app/Contents/MacOS/Python: can't open file '/Users/purplelephant/projects/asex/grammar/ambiguity_audit.py': [Errno 2] No such file or directory
  ```
- **Order:** must precede W2, which changes the grammar — the before/after numbers are only
  meaningful if the auditor exists first.

### W2 — Remove dead pattern alternatives; record the residual
- **What:** delete the seven per-prelude-case `pattern` alternatives at
  `grammar/agentscript.lark:91–97` (PCP `l-b1b8`) — `OK`, `ERR`, `SOME`, `NONE`, `LIST`,
  `CONS`, `PAIR` — keeping `enum_pattern` (line 90) and the live `literal | IDENT | WILDCARD`
  (98–100). Measured expectation (in-memory simulation this session): all 77 fixtures still
  parse, total drops 219 → 140. Then examine the largest residual per-file contributors and
  remove any further overlap that is cheap; `--write` the final total into
  `grammar/ambiguity.lock` under D7.
- **Why:** the one known dead source of the ambiguity count; the acceptance allows
  "recorded", so the item's success is a strictly smaller, checked-in number — not
  necessarily zero.
- **Gate:** after removal, `.venv/bin/python grammar/ambiguity_audit.py --check` fails (count
  differs from the lock — down as well as up, per D7) until `--write` records the new figure;
  W2 is complete only when the new lock is **strictly below** the pre-W2 lock. The full
  battery re-runs, in particular `.venv/bin/python grammar/validate.py` — whose
  `token_identity()` block (validate.py:121–140, folded into `main()` at :193 and the exit
  code at :199) fails the gate if any of its 13 cross-grammar span probes drifts, which is
  the pin on "the resolved tree is unchanged".
- **Order:** after W1 (auditor) and before W3 only because W3 re-points `fmt.py` at
  `grammar/parse.py` and should not re-land on a grammar mid-edit; W2 does not touch
  `parse.py`, so the practical coupling is weak — the ordering is for review cleanliness.

### W3 — Re-integrate the formatter, renamed and re-pointed
- **What:** materialise `tools/fmt/fmt.py` + `tools/fmt/t/test_fmt.py` per §2; re-point its
  parser construction and `FORM_KW` at `grammar/parse.py` (`parser()`, `kids()`, `FORM_KW` —
  the stash duplicates all three at fmt.py:160-176 and its :38 block); replace
  `grammar/as-lang.lark` path with `grammar/parse.py`'s `GRAMMAR`; adapt its token set to the
  current grammar (the stash carries `DEFENTRY`/`DEFEXTERN`/`DEFOPAQUE`, which no longer
  exist — `DEFUN`/`DEFSCHEMA`/`DEFENUM` per `grammar/parse.py:20`); accept `*.agentscript`.
- **Why:** the formatter is acceptance axis 3 and the `fmt` subcommand of the distributor;
  re-pointing to `parse.py` kills the third copy of parser construction.
- **Gate (fails now):** `.venv/bin/python -m pytest tools/fmt/t -q`
  ```
  ERROR: file or directory not found: tools/fmt/t
  ```
  AND, at W3's end, the formatter runs over the **entire corpus without error** — every
  fixture under `grammar/corpus` formats (output correctness is W4's gate; W3's additional
  criterion is that no fixture crashes or rejects the printer, because a test suite of
  hand-picked snippets can pass while a corpus fixture breaks).
- **Order:** before W4 (the idempotence gate needs the formatter) and before W5 (edit tests
  use the formatter for idempotence assertions).

### W4 — Formatter idempotence gate on the corpus
- **What:** add `--check <path>` to `tools/fmt/fmt.py` (and pass through in `agentscript fmt
  --check` once W5 lands the CLI): for each `*.agentscript` fixture under the path, format,
  format again, fail unless outputs are equal; print a per-file verdict. Per D6, W4's gate
  also adds the canonical-output fixture pair to `tools/fmt/t` and requires the full
  `tools/fmt/t` suite green — idempotence alone accepts a no-op formatter, a comment-dropper,
  or a deterministic reorderer; the stash's tree-preservation and comment-survival tests plus
  the canonical fixture are what catch those.
- **Why:** acceptance axis 3 verbatim, made non-trivial.
- **Gate (fails now):** `.venv/bin/python tools/fmt/fmt.py --check grammar/corpus`
  ```
  /Library/Frameworks/Python.framework/Versions/3.13/Resources/Python.app/Contents/MacOS/Python: can't open file '/Users/purplelephant/projects/asex/tools/fmt/fmt.py': [Errno 2] No such file or directory
  ```
  plus `.venv/bin/python -m pytest tools/fmt/t -q` (green) — both are W4 completion criteria,
  not just end-of-phase checks.
- **Order:** after W3 (the code under test must exist and parse the current grammar).

### W5 — Distributor `agentscript`, with edit/ast/search
- **What:** materialise the stash shim as `agentscript` at the repo root per §2; apply D1's
  renames and **D1a's checker re-pointing** (this is real work, not renaming: the stashed
  `cmd_check` calls an API that no longer exists — `check.parser()`,
  `check.check_file(parser, f)`, `check.import_cycles(models)`,
  `check.target_capabilities(models, target)` at stash lines 82–90 — and the `TARGETS` load
  at :33 reads a `prelude.json` key that is absent; the re-point is the subprocess-or-import
  choice of D1a, with `--target`/`--rules` dropped per D1a). Prune `BACKENDS` to
  `{"py": "to_python.py", "rs": "to_rust.py"}`, repoint `TREE_SITTER`/`GRAMMAR_DIR` at
  `tree-sitter-agentscript`, glob `*.agentscript`. Extend per D5: `ambiguity` (→ W1's
  auditor, per-file JSON), `tokens` (→ W7's budget), `search` and `edit` per D5 — new dev dep
  `tree-sitter` (pip, into `.venv`), grammar compiled to a shared lib once by
  `tree-sitter build -o`, ops `ast --json`, `search --query`, `edit replace/delete/insert`,
  JSON contracts as specified in D5. `--json` and exit=count conventions extended to the new
  subcommands. Tests: `tools/t/test_edit.py` — D5's parametrised form-class contract
  (replace/delete/insert × the enumerated classes, delete asserts bytes gone, byte round-trip,
  re-parse + idempotent format), plus a CLI smoke test.
- **Why:** PHASES.md: "wired into the distributor"; the shim is the precedent and the home.
- **Gate (fails now):** `.venv/bin/python -m pytest tools/t/test_edit.py -q`
  ```
  ERROR: file or directory not found: tools/t/test_edit.py
  ```
  and `.venv/bin/python agentscript check grammar/corpus/valid` → `can't open file ... agentscript`.
  W5 is complete only when: `agentscript check grammar/corpus/valid` exits **0**;
  `agentscript check` on one `grammar/corpus/semantic` fixture exits **non-zero** (with the
  rejection count); `agentscript tokens` exits 0; the pytest suite is green. The `check`
  smoke tests are gates, not prose — a distributor that ships without a working `check`
  subcommand fails this item.
- **Order:** after W3/W4 (`fmt` and `--check` pass through), before W6–W8 which register
  their subcommands here. If D5's Python-binding mechanism fails, swap the implementation to
  the Rust fallback (new `[[bin]]` per D5) and keep this item's gate and tests unchanged.

### W6 — Re-integrate bindgen
- **What:** materialise `tools/bindgen/from_pyi.py` and `tools/bindgen/t/` from `b614ec8` per
  §2 (the expected file is renamed to `frames.expected.agentscript`); register `bindgen` in the
  distributor. **Amended (orchestrator, post-implementation):** parse-validation of the emitted
  declarations is **exempted** — Core deliberately has no FFI (ROADMAP §3), so there is no
  grammar to parse the FFI forms against. Validation is text-level (the checked-in
  `frames.expected.agentscript` fixture + the 8 bindgen tests). The fork predates the
  prelude-lock work; the expected fixture is adjusted only if the current §6 vocabulary renamed
  something — the diff drives the fixture, not vice versa.
- **Why:** PHASES.md Phase 6 names the bindgen re-integration explicitly.
- **Gate (fails now):** `.venv/bin/python -m pytest tools/bindgen/t -q`
  ```
  ERROR: file or directory not found: tools/bindgen/t
  ```
- **Order:** after W5 (its subcommand lands in the distributor); independent of W7/W8.

### W7 — Token budget ratchet
- **What:** `prelude/budget.py` per D3 — `--check` fails unless `len(HANDBOOK.md)` characters
  **equal** `prelude/budget.lock` (D7 exact-match: growth and shrink both require a
  deliberate `--write` in the same commit that earns the new figure — the commit-coupled
  invariant, stated here because it is the whole ratchet); `--write` records. Register
  `tokens` in the distributor (W5).
- **Why:** the token-budget axis needs a regressible number; D3 chose characters.
- **Gate (fails now):** `.venv/bin/python prelude/budget.py --check`
  ```
  /Library/Frameworks/Python.framework/Versions/3.13/Resources/Python.app/Contents/MacOS/Python: can't open file '/Users/purplelephant/projects/asex/prelude/budget.py': [Errno 2] No such file or directory
  ```
- **Order:** after W5 (subcommand registration); independent of W6/W8.

### W8 — Source spans on interpreter runtime errors
- **What:** in `crates/agentscript-interp`, thread `Span` from `cst.rs` lowering into the 13
  failable `Expr` variants (`Ident`, `Qualified`, `Call`, `FieldAccess`, `If`, `Cond`,
  `Match`, `Try`, `Ctor`, `Record`, `Let`, `Int`, `Fn` — the implementer confirms the set
  against `eval.rs`'s 29 `Err(` sites; `Float`/`Str`/`Bool`/`Unit` are excluded per D4);
  runtime error output becomes `path:line:col: message`; exit codes stay 0/1/2.
  `tools/span_coverage.py` parses `ast.rs`, counts variants-with-`span`-field over the
  **13-variant failable denominator** (the four exclusions recorded in the lock with their
  reason), and `--check`es `crates/agentscript-interp/span.lock` under D7; `--write` records.
  Functional test `tools/t/test_interp_diag.py`: build the interp binary (`rustup run stable
  cargo build -p agentscript-interp`), run it on fixtures that fail at runtime, and — the
  gating contract — exercise **at least one error per failable variant** (the coverage of a
  `span` field is only proven when its error path prints), asserting the stderr matches
  `path:line:col:` with **line and col ≥ 1** (a default `Span{0,0}` produces `path:0:0:`,
  which a bare regex would accept) and the exit status is 1 or 2 as appropriate.
- **Why:** `checker/resolve.py` located diagnostics are the toolchain's standard; the
  interpreter is the dev-loop surface and currently reports nothing located. The axis ends at
  a regressible number (baseline 1/13 failable).
- **Gate (fails now):** `.venv/bin/python -m pytest tools/t/test_interp_diag.py -q`
  ```
  ERROR: file or directory not found: tools/t/test_interp_diag.py
  ```
  AND, as a gate of this item (not prose): `.venv/bin/python backend/differential.py` re-run
  green after spans land. Program mode compares stderr **unconditionally across all four arms
  and against each case's declared stderr value** (differential.py:367–406); W8 changes the
  interpreter's stderr text, so the case declarations must be updated in the same commit if
  the new prefixes appear, and the agreement count must not drop. Never relax the comparison.
- **Order:** last — it is the only Rust-side item and depends on nothing in W1–W7; doing it
  last keeps the Python tooling stable while spans land.

## §4 Acceptance battery (end of phase)

```
.venv/bin/python grammar/ambiguity_audit.py --check          # axis 1: recorded count, locked (D7)
.venv/bin/python tools/fmt/fmt.py --check grammar/corpus    # axis 3: idempotence
.venv/bin/python -m pytest tools/fmt/t tools/t tools/bindgen/t -q   # axis 2 + D6 assertions
.venv/bin/python agentscript check grammar/corpus/valid     # distributor smoke: exit 0
.venv/bin/python agentscript tokens                          # budget via the distributor: exit 0
.venv/bin/python prelude/budget.py --check                  # 12,749-char ratchet (D7)
.venv/bin/python tools/span_coverage.py --check             # span fraction over 13, locked
.venv/bin/python backend/differential.py                    # after W8: four-arm stderr agreement
```

plus the unchanged AGENTS.md battery (`validate.py`, `closure_audit.py`, `generate.py
--check`, `checker/gate.py`, `check_corpus.py`, `monomorphism.py`,
`backend/t bench/algo checker/t`), all of which must stay green after every item.
`differential.py` appears both here and as W8's gate because W8 is exactly when its stderr
comparison is at risk.

## §5 Risks

- **D5's mechanism is partially unverified.** `tree-sitter build -o` succeeds for this
  grammar (a loadable .so was produced in a probe); the Python `tree-sitter` package is not
  installed and its `Language()` load of that .so is untested. If the binding fails, the
  declared fallback is a Rust edit CLI in a new `[[bin]]` target (or a new crate); W5's tests
  are written against the CLI surface and the D5 JSON contract, not the mechanism, so the
  swap is contained.
- **The residual ambiguity after W2 may not go much below 140 cheaply.** Only the `l-b1b8`
  dead alternatives are a known source (219 → 140 in simulation); the rest (largest:
  14-sequenced-bodies at 25) is unmapped. Acceptance permits recording, so the ratchet is
  the contract — but the residual-count attribution work could grow. Mitigation: W1's audit
  prints per-file counts so sources are findable without a second tool.
- **Formatter fit to the current grammar is unverified.** The stash predates the rename and
  carries token names (`DEFENTRY`, `DEFEXTERN`, `DEFOPAQUE`) absent from the current
  `FORM_KW`; the corpus is also larger than whatever the stash's tests covered. W3's pytest
  gate plus its full-corpus run and W4's idempotence gate will expose gaps, but the fix
  effort is unknown until W3 runs.
- **`stash@{0}^3` paths are known good only for the files listed.** `git ls-tree` confirmed
  exactly `as-lang`, `tools/fmt/fmt.py`, `tools/fmt/t/test_fmt.py`; no tree-sitter grammar
  inside the stash, so no grammar drift can be introduced by it. `b614ec8`'s bindgen fixture
  may reference fork-era vocabulary names; the expected file is expected to need edits.
- **Deleting the stash after recovery is not planned.** The stash stays; cleanup is the
  orchestrator's call.
- **Dropped shim features need an orchestrator decision if wanted back.** The stash's
  `--target` capability filtering, `--rules`, `import_cycles`, and `target_capabilities` have
  no counterpart in the current checker; D1a drops them by default. If the orchestrator
  wants them, that is a separate scope decision — not silent W5 growth.
