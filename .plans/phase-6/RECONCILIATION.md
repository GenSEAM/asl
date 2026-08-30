# Phase 6 — Reconciliation (PLAN.md v1 → v2)

Three reviews folded: REVIEW-design (0 blockers / 4 major / 4 minor), REVIEW-exec (2
blockers / 5 non-blocking), REVIEW-coverage (reject; 3 blockers / 3 major).

**Verification method.** Every disposition below was checked against the tree before acting,
not taken from the reviews. Probes run this session (all read-only):

- Ambiguity probe: `Lark(grammar/agentscript.lark, start="start", parser="earley",
  ambiguity="explicit")`, counting trees with `data == "_ambig"` over
  `valid/*.agentscript` + `semantic/*.agentscript` + `modules/**/*.agentscript` →
  `files=77 unparseable=0 total_ambig=219 worst=(25, '14-sequenced-bodies.agentscript')`,
  identical on re-run (deterministic).
- W2 simulation: deleting exactly lines 91–97 of `grammar/agentscript.lark` in memory →
  `total=140 unparseable=0 of 77`, live alternatives `literal | IDENT | WILDCARD` retained.
- `grep -n` on `grammar/agentscript.lark`: dead per-case alternatives at **91–97**, live at
  98–100, `pattern:` head at 90.
- `grep -n 'targets' prelude/prelude.json` → no match; `git show 'stash@{0}^3:as-lang'` line
  33 `["targets"]`, lines 82–90 `check.parser()` / `check.check_file(parser, f)` /
  `check.import_cycles(models)` / `check.target_capabilities(models, target)`.
- `checker/check.py`: 32 lines, thin argparse CLI over `from resolve import check_file`;
  `checker/resolve.py:641 def check_file(path, roots) -> list[Diagnostic]`.
- `backend/differential.py`: program mode compares stdout, stderr, exit across four arms
  against per-case declared values (:367–406, stderr "compared unconditionally and declared
  per case", :388–390).
- `wc -c prelude/HANDBOOK.md` → 12779; `len(read_text())` → 12749.
- `crates/agentscript-interp/src/ast.rs`: 17 `Expr` variants, only `IntLit` carries `Span`;
  `grep -c 'Err(' eval.rs` → 29; `grep -E 'Expr::(Float|Str|Bool|Unit)' eval.rs` → no matches.
- `crates/agentscript-ts/Cargo.toml`: `crate-type = ["staticlib", "rlib"]`, no `[[bin]]`.
- `grammar/validate.py`: `failures += token_identity()` (:193), `return len(failures)` (:199),
  `sys.exit(main())` (:203) — token-identity probe failures fail the gate's exit code.
- `grammar/parse.py:20` `FORM_KW = {"DEFUN", "DEFSCHEMA", "DEFENUM", ...}`.

Duplicate findings across reviews are merged into one row; REVIEW-coverage's
conformant-but-wrong table (9 rows) is elaboration/evidence of its B1/B2/B3/M1/M2 and is
folded with them (rows 1, 2, 9 → row 15; rows 3, 4 → row 3; row 5 → row 17; row 6 → row 6;
rows 7, 8 → row 16). **18 findings in, 18 rows out.**

| # | Source | Finding | Disposition | Where / evidence |
|---|---|---|---|---|
| 1 | design MAJOR-1 | Baseline 219 not reproducible; claims 196 `_ambig` over 79 fixtures (29 valid + 44 semantic + 6 modules), worst 21; "the lock, not the prose, is the baseline" | **reject** (number) | Probe above: **219 over 77** (semantic is 42, not 44), deterministic, worst 25. The architect's figures did not reproduce under the plan's own stated mechanism. The salvageable residue — record the measured baseline with its command, lock supersedes prose — is folded via row 18 and §1's rewrite. |
| 2 | design MAJOR-2 | W2's cited range `lark:93-101` deletes live grammar; dead set is at 91–97; removal verified safe (all fixtures parse, count drops) | **accept-modified** | Line range confirmed and corrected to **91–97** (live `literal|IDENT|WILDCARD` at 98–100). Modified: the reviewer's post-removal figure (196→121) did not reproduce; my simulation gives **219→140**, all 77 fixtures parsing. Plan records 140 as the measured expectation and the lock as authority (D2, W2). |
| 3 | design MAJOR-3 + coverage B2 (+ table rows 3–4) | W1's "fail if greater" contradicts W2's gate; a reduction passes silently without `--write`; a `--write` of any number (even a regression) stands; auditor could be wired to `--write`'s argument or run in `resolve` mode | **accept** | Resolved to D7: **exact-match ratchet** on every new lock (`--check` fails on any difference, up or down; `--write` deliberate, commit-coupled). Chosen over coverage's suggested `--accept-regression` flag because exact-match is strictly stronger and matches the repo's `coverage.lock` precedent. W1's spec now states the auditor reads the lock from disk against a fresh measurement, and parses with `ambiguity="explicit"` (row 4's countermeasures). W2's gate: fails under D7 until `--write`; complete only when the new lock is strictly below the pre-W2 lock. |
| 4 | design MAJOR-4 | W5 under-scoped: stashed shim reads `prelude.json["targets"]` (absent) and calls `check.parser()` / `check_file(parser, f)` / `import_cycles` / `target_capabilities` (all gone; current surface is `checker/check.py` over `resolve.check_file(path, roots)`); cannot start | **accept** | Verified (stash :33, :82–90; `checker/check.py` is a 32-line CLI; `resolve.py:641`). W5 now scopes D1a: rewrite `cmd_check` against the current checker (subprocess or import), `TARGETS` from `BACKENDS` keys, `--target`/`--rules` dropped and flagged for the orchestrator (§5 last bullet). |
| 5 | design MINOR-1 | §1 says "12,779 chars (`wc -c`), 2,454 bytes" — inverted; D3's mechanism records `len()` characters → baseline should be 12,749 chars (12,779 is bytes) | **accept** | Verified: `wc -c` 12779, `len(read_text())` 12749. §1 and W7/D3 now state **12,749 characters** as the unit and baseline. |
| 6 | design MINOR-2 + coverage M2 (+ exec N3, + table row 6) | Span denominator 17 counts `Float/Str/Bool/Unit`, which never reach an `Err(` site — fraction can never reach 17/17 without pointless plumbing; and a defaulted `Span{0,0}` passes a bare `path:line:col:` regex, so field-presence is not value-presence | **accept** | Verified: no `Expr::Float|Str|Bool|Unit` sites in eval.rs. D4/W8: denominator is the **13-variant failable subset**, exclusions recorded with reason in `span.lock`; `test_interp_diag.py` must exercise ≥1 error per failable variant and assert `line, col ≥ 1` (rejects `path:0:0:`). |
| 7 | design MINOR-3 | Post-W2 grammar.js/lark node-shape drift is invisible to every gate; "only if node shapes change (not expected)" should be a recorded decision, not a hope | **accept** | §2 now records the decision with its rationale: accepted language unchanged, `validate.py` compares verdicts and runs the token-identity probes, `queries/searches.scm` references no pattern nodes, and changing grammar.js would be the worse drift. |
| 8 | design MINOR-4 | D5's fallback is thin: spec the JSON contracts now; `crates/agentscript-ts` has no `[[bin]]`, so the fallback needs a new bin target or crate | **accept** | Verified Cargo.toml (`staticlib + rlib`, no bin). D5 now specifies the JSON output contract for `ast --json`, `search`, and the edit receipts, and the fallback names a new `[[bin]]` target. |
| 9 | exec B1 | No gate runs `backend/differential.py` after W8, though W8 changes interpreter stderr and program mode compares stderr across four arms and against declared per-case values | **accept** | Verified (differential.py:367–406, :388–390). W8's gate now literally includes `.venv/bin/python backend/differential.py` (case declarations updated in the same commit if prefixes appear; agreement count must not drop), and §4 lists it explicitly with a note on why. |
| 10 | exec B2 | W2's gate does not pin the 13 `validate.py` token-identity probes; a silently flipped probe could pass | **reject** | The hole does not exist: `grammar/validate.py:193` adds `token_identity()` failures to `failures`, :199 returns the count as the exit code, :203 `sys.exit(main())` — any probe failure makes `validate.py` exit non-zero, and W2's gate already requires `validate.py` green. W2's What now names this protection explicitly (documentation, not a new gate). |
| 11 | exec N1 | W3's gate stops at pytest; no per-item requirement that the formatter handles the full corpus (the actual fit surface) | **accept-modified** | Folded, but split rather than collapsed: W3's completion criterion adds "every corpus fixture formats without error" (fit), while idempotence remains W4's gate — pulling `--check` into W3 would merge two items whose failing-now gates are separate. |
| 12 | exec N2 | `git stash show -p 'stash@{0}^3'` fails (`not a stash-like commit`); recovery prose should be the exact working commands | **accept** | §2 now carries the exact `git show 'stash@{0}^3:<path>' > <path>` command block (including the bindgen files and the expected-file rename). |
| 13 | exec N4 | `agentscript tokens` (the W5 surface of W7's budget) is never gated | **accept** | §4 adds `.venv/bin/python agentscript tokens` (exit 0); W5's completion criteria include it. |
| 14 | exec N5 | `agentscript check grammar/corpus/valid` is the acceptance proof but only appears "in passing"; a distributor without a working `check` fails no gate | **accept** | W5's gate now requires `check grammar/corpus/valid` exit 0 AND `check` on one semantic fixture exit non-zero, and states these are gates, not prose. |
| 15 | coverage B1 (+ table rows 1, 2, 9) | W4's idempotence-only gate is trivially passed by a no-op formatter, a comment-dropper, or a deterministic reorderer; the catching tests run only at end-of-phase, not in W4 | **accept** | D6/W4 redefined: the gate is `fmt.py --check grammar/corpus` **plus** `pytest tools/fmt/t` green (tree preservation, comment survival) **plus** a checked-in canonical-output fixture pair asserting the formatter's canonical form — all as W4 completion criteria, not just §4 items. |
| 16 | coverage B3 (+ table rows 7, 8) | W5's edit tests are a list, not a contract: no per-form-class coverage, no assertion that delete actually removes bytes, source-bytes-vs-tree semantics unstated | **accept** | D5 now: edits operate on source bytes (tree-sitter ranges authoritative, file rewritten in place); tests parametrised over 12 enumerated form classes; delete asserts the deleted bytes are gone (row 8's countermeasure); round-trip byte-exact. |
| 17 | coverage M1 (+ table row 5) | Budget ratchet's `len <= lock` makes the lock a one-shot number; the commit-coupled `--write` invariant is implicit | **accept-modified** | Folded with the D7 rewrite rather than as stated: `budget.py --check` is **exact-match** (stronger than the reviewer's ask), and the commit-coupled invariant ("`--write` in the commit that earns the figure") is stated verbatim in W7. Baseline corrected to 12,749 chars per row 5. |
| 18 | coverage M3 | Plan claims 43 parseable fixtures; actual count differs (reviewer counted 77 = 29+42+6); the 219 total is correct | **accept** | Verified: 29 valid + 42 semantic + 6 modules = **77**, total 219, worst 25. §1 corrected; also records the recursive-glob requirement for `modules` (its fixtures live in subdirectories — a non-recursive glob finds 0 and would corrupt the count). |

## Orchestrator attention

- **Design reviewer's measurements did not reproduce.** Both its headline figures (196/79/21
  and 196→121) differ from the direct probes above (219/77/25 and 219→140). Its *mechanism*
  descriptions were accurate and its non-numeric findings all verified. Weight accordingly
  in future waves.
- **Decision flagged, not made:** the stashed shim's `--target` capability filtering,
  `--rules`, `import_cycles`, and `target_capabilities` are dropped by default (D1a);
  reinstating them is a scope call for the orchestrator, recorded in §5.
- **Stash retention** remains the orchestrator's call (unchanged from v1).

## Order and gates

Work-item ordering is unchanged from v1 (W1→W8; every item still fails before its
predecessor lands). No gate was weakened: W1/W7 locks moved from "fail if greater" to
exact-match (strictly stronger), W4's gate gained two mandatory assertions, W5 gained three
smoke gates, W8 gained a differential gate, and the two numeric corrections (rows 2, 18) fix
prose, not checks.
