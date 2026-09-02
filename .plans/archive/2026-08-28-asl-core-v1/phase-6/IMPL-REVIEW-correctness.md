# Phase 6 — Implementation review (correctness & regression)

**Lens:** correctness of new behaviour and absence of regressions
**Verdict:** `approve`
**Blockers:** 0
**Major findings:** 1 (drift between lark and tree-sitter grammars, pre-existing + extended by W2)
**Minor findings:** 3

## §1 — Headline gates run this session

| Command | Result |
|---|---|
| `.venv/bin/python backend/differential.py` | exit 0; `0 disagreement(s) across 120 function cases + 15 program cases (python/rust/wasm/interp)` |
| `.venv/bin/python -m pytest backend/t bench/algo checker/t -q` | exit 0; **161 passed** in 50.00s |
| `.venv/bin/python -m pytest tools/fmt/t tools/t tools/bindgen/t -q` | exit 0; **351 passed** (277 fmt + 52 edit + 8 bindgen + 14 interp_diag) |
| `rustup run stable cargo test --manifest-path Cargo.toml -q` | exit 0; **8 + 2 + 0** tests passed across 3 crates |
| `.venv/bin/python grammar/ambiguity_audit.py --check` | exit 0; `140 ambiguity node(s) over 79 parseable fixture(s)` |
| `.venv/bin/python tools/fmt/fmt.py --check grammar/corpus` | exit 0; per-file all `ok (idempotent)` |
| `.venv/bin/python prelude/budget.py --check` | exit 0; `12749 characters (lock: 12749)` |
| `.venv/bin/python tools/span_coverage.py --check` | exit 0; `13/13 failable variants carry a span` |
| `.venv/bin/python -m pytest tools/t/test_interp_diag.py -q` | exit 0; **14 passed** (13 variants + IoError bare-name) |

## §2 — Correctness of the new behaviour (claim → evidence)

### W1 / W2 — Ambiguity audit

- **Audit counts `_ambig` nodes** — confirmed. `grammar/ambiguity_audit.py:23-32` recursively walks with `if isinstance(child, Tree) and child.data == "_ambig"`. Direct inspection of `grammar/corpus/valid/14-sequenced-bodies.agentscript` (which the audit reports at 23) confirms `_ambig` Tree nodes appear and `_ambig_count` returns 23 — matches the audit output.
- **Deterministic** — confirmed. Two consecutive `--check` runs returned `140 ambiguity node(s) over 79 parseable fixture(s)` both times.
- **Lark parser uses `ambiguity="explicit"`** — confirmed at `grammar/ambiguity_audit.py:50` (`parser = Lark(GRAMMAR.read_text(), start="start", parser="earley", ambiguity="explicit")`).
- **Lock is exact-match (D7)** — confirmed by tampering test: changing `prelude/budget.lock` to `9999` made `budget.py --check` exit 1 with `measured 12749 chars but budget.lock records 9999` (same mechanism in `ambiguity_audit.py:93-103`).
- **Per-file counts emitted in `--check`** — confirmed (`grammar/ambiguity_audit.py:79-83`). The largest contributor is `valid/14-sequenced-bodies.agentscript` at 23 (plan said 25; the discrepancy is post-removal — the actual post-W2 figure is the lock-recorded 140, not a synthetic 140 from simulation).

### W2 — Dead-pattern removal

- **Removed exactly lark:91-97** — confirmed. `git diff HEAD grammar/agentscript.lark` shows precisely the 7 lines:
  - `| "(" OK pattern ")"`
  - `| "(" ERR pattern ")"`
  - `| "(" SOME pattern ")"`
  - `| "(" NONE ")"`
  - `| "(" LIST ")"`
  - `| "(" CONS pattern pattern ")"`
  - `| "(" PAIR pattern pattern ")"`
- **Live alternatives preserved** — confirmed: `pattern: ... | literal | IDENT | WILDCARD` remains (lines 90-92 post-edit).
- **All 79 parseable fixtures still parse** — confirmed via audit (`0 parse failures`); `grammar/validate.py` exits 0; checker gate exits 0.

### W3 — Formatter

- **`fmt.py --check grammar/corpus` is green** — confirmed. Exit 0; per-file `ok (idempotent)`.
- **Idempotence** — confirmed by `check_idempotence()` at `tools/fmt/fmt.py:954-963`: each fixture formatted twice yields identical output.
- **Tree preservation** — confirmed: `test_formatting_preserves_the_tree` parametrizes over the full corpus and compares the stripped shape (rule names + token text) before/after. All 79 corpus entries pass.
- **Comment survival** — confirmed: `test_every_comment_survives` parametrizes over the full corpus. Plus 11 dedicated comment-position tests at `tools/fmt/t/test_fmt.py:119-216` cover edge cases (comments before declarations, separated by blank lines, inside bodies, on closing delimiters, at end of file, etc.). All pass.

### W4 / W5 — Structured edits

- **Delete actually removes bytes** — confirmed. Verified directly via CLI: `(defun add ...)\n` (51 bytes) → after `edit delete --range 0:0-1:0` → `b''` (0 bytes). The test's `test_delete_removes_the_deleted_bytes` assertion is not merely a round-trip — it inspects the post-delete bytes for absence of the original first line.
- **Replace round-trips** — confirmed: `test_replace_output_parses_and_formats_idempotently` parametrizes over 12 forms; each does a no-op byte replacement and asserts the post-edit file is formatter-idempotent.
- **12 form classes covered** — confirmed: `FORMS` dict at `tools/t/test_edit.py:30-43` contains exactly `defun, defschema, defenum, let, if, cond, match arm, try, ctor, record, qualified, field access` (12 keys).
- **The formatter is the arbiter** — confirmed at `tools/t/test_edit.py:115-117`: post-edit, `fmt.format_source(src, str(p)) == fmt.format_source(once, str(p))`.
- **AST / search over the CLI work** — confirmed: `test_ast_dumps_a_json_node_tree` (root is `source_file`, has `children` + `byteRange`), `test_search_returns_captured_ranges` (matches `(defun name: (ident) @name)` and asserts the captured text equals the function name).

### W6 — Token budget ratchet

- **`len(read_text())` characters** — confirmed at `prelude/budget.py:24`. `12749 characters (lock: 12749)` — exact-match.
- **No tokenizer dependency** — confirmed; one stdlib call.

### W7 — Bindgen recovery

- **`from_pyi.py` total on standard stubs** — confirmed. Tests assert the expected checked-in output matches the generated output (`test_output_matches_the_checked_in_expectation`).
- **Nested generics handled** — confirmed: `(options (Map String (List Int64)))` in the expected output.
- **Optional return / parameter** — confirmed: `(Option (Map String String))` for returns, `(Option (List Float64))` for parameters.
- **Skipped functions reported, not silent** — confirmed: `; Not generated, and why:` followed by `;   scan_all - variadic or keyword-only parameters` and `;   to_arrow - no language type for bytes`.
- **`:symbol` only when mangling can't round-trip** — confirmed: `readCSV` (camelCase) gets `:symbol`, `read_csv` does not (the test searches the `read-csv` block for the absence of `:symbol`).

### W8 — Span threading into the interpreter

- **All 13 failable variants carry a span** — confirmed at `crates/agentscript-interp/span.lock` and re-verified by `tools/span_coverage.py --check` exiting 0 with `13/13`.
- **`Eval` attaches `Located { path, span }` to unlocated errors** — confirmed at `crates/agentscript-interp/src/eval.rs:244-251` (the `eval` wrapper around `eval_inner` populates `err.located = Some(Located { path: self.path(), span: sp })` only when `err.located.is_none()`).
- **`cst.rs` populates `Span { line: row+1, col: column+1 }` for every failable Expr** — confirmed at `crates/agentscript-interp/src/cst.rs:104,116-117,...` (each `Expr::X { ..., span: self.span(node) }` call uses the 1-based `self.span(node)` at line 89-94).
- **`line,col >= 1` holds for every failable variant** — confirmed via direct invocation: all 13 fixtures produce `path:1:N: ...` with `N >= 25` (real positions).
- **Exit codes stay 0/1/2** — confirmed: evaluator errors exit 2; IoError case-name exits 1 (untouched `exit_glue` path).

## §3 — Regression checks

- **None of the seven pre-Phase-6 gates weakened** — confirmed. `git diff main` shows zero modifications to `grammar/validate.py`, `grammar/closure_audit.py`, `prelude/generate.py`, `checker/gate.py`, `backend/check_corpus.py`, `backend/monomorphism.py`, `backend/differential.py`. The agentscript CLI delegates to them via subprocess.
- **Closure audit still 100%** — `107/107 (100%)` executed builtins.
- **`differential.py` program-mode stderr agreement survived W8** — confirmed. The stderr text changes W8 introduced are:
  - `Err::Trap(s)` → `Err::trap(s)` (display changed from `trap: <msg>` to `<msg>`).
  - `Err::Internal(s)` → `Err::internal(s)` (display changed from `internal error: <msg>` to `<msg>`).
  - When a span is present, display becomes `path:line:col: <msg>`.

  Program mode (`backend/differential.py:367-407`) compares stderr unconditionally across all four arms. The 15 program cases include 3 cases with non-empty stderr (`"not-found\n"`, `"permission-denied\n"`, `"usage: io-demo SRC [DST]\n"`), all of which flow through `exit_glue` (eval.rs:1240-1255) which **does not attach a Located** — the IoError case-name path bypasses the `Err` type entirely. Differential reported `0 disagreement(s) across 120 function cases + 15 program cases` — stderr agreement holds.

- **Function-mode stderr not compared** — confirmed: `backend/differential.py:281-302` compares only return values for the 120 function cases, not stderr.
- **Function-mode stderr text change cannot break function-mode agreement** — confirmed (function-mode never inspected stderr).

## §4 — "Conformant-but-wrong" — what would still pass

The gates as written accept the following conformant-but-wrong implementations:

- **`agentscript --json` `rule` field**: `agentscript:104-110` passes the checker's string code (e.g. `"arity"`, `"type"`) straight into `Diag.rule`, which is declared `rule: int` (`tools/fmt/fmt.py:13-23`). All gate tests pass; the JSON output reports `"rule": "arity"` (a string). The contract in `agentscript:11-12` says `{file, line, col, rule, message}` without typing `rule`. Any caller type-checking `rule: int` would silently get a string. **Gate does not catch this.**
- **Ambiguity audit could silently drop files**: `grammar/ambiguity_audit.py:42-48` builds the path list at start; if a fixture were deleted between runs, the count drops, the lock mismatches, and `--check` correctly fails (the lockfile ratchet catches it). A test of "no fixture silently dropped" would require a separate test enumerating fixtures — none exists.
- **Span coverage static-only**: `tools/span_coverage.py` checks that AST variants have a `span` field by regex over `ast.rs` — it does not check that the span is propagated through `eval_inner` correctly. The functional gate `test_interp_diag.py` is the safety net and **does** exercise every variant. So coverage-of-field is paired with coverage-of-value, as D4 mandates.
- **Tree-sitter grammar still accepts the dead `pattern` alternatives** (see finding M1): any fixture or tool exercising `tree-sitter` would still parse `(ok n)` as a pattern even though the lark grammar now refuses it. No gate catches this — and no fixture exercises it post-removal. **Gate does not catch this drift.**

## §5 — Findings

### Major

**M1 — Grammar drift: lark and tree-sitter grammars no longer agree on `pattern` (W2 plan violation).**
- Evidence: `grammar/agentscript.lark:88-92` now contains 4 pattern alternatives (`enum_pattern | literal | IDENT | WILDCARD`); `grammar/tree-sitter-agentscript/grammar.js` `_pattern: $ => choice(...)` (grep at the grammar.js file shows `ok_pattern, err_pattern, some_pattern, none_pattern, list_pattern, cons_pattern, pair_pattern, enum_pattern, ...`) still includes all 7 removed alternatives.
- Plan rule (AGENTS.md): *"Both grammars must change together — `agentscript.lark` drives constrained decoding, `grammar.js` drives tooling, and silent drift means they enforce different languages."*
- Class: any change to the lark grammar that drops an alternative should drop the matching tree-sitter alternative in the same commit. The phase-6 W2 dropped 7 alternatives in lark but touched zero in tree-sitter.
- Impact today: low — no current fixture exercises the dead alternatives, and `tools/tsutil.py` does not pattern-match on them. Impact tomorrow: a future edit operator working through `tsutil.py` could be misled into editing `(ok n)` form, only to be rejected by the lark grammar downstream.
- Verdict: **non-blocking** (no regression on existing fixtures or tools), but explicitly the kind of drift AGENTS.md forbids.

### Minor

**m1 — `agentscript --json` emits `rule` as a string when it should be an int.**
- Evidence: `agentscript:108-110` (`return fmt.Diag(path, int(line_n), int(col), 0 if code == "internal" else code, message)`) where `code` is the regex match group (string). `Diag.rule` is declared `rule: int` at `tools/fmt/fmt.py:22`. Verified by `agentscript check grammar/corpus/semantic/wrong-arity.agentscript --json` returning `{"rule": "arity", ...}`.
- Class: any checker rule code propagated as a string instead of an int would have the same defect. There are ~12 distinct rule codes in `checker/resolve.py`; all would surface as strings.
- Verdict: non-blocking — JSON consumers reading `rule` as opaque (string-coerced) tokens work; consumers type-checking it as `int` would fail. No consumer today type-checks it.

**m2 — Plan baseline numbers (D2) were off by two parseable fixtures (77 stated, actual 79) and by 79 on the per-file-largest (25 stated for `14-sequenced-bodies`, actual 23).**
- Evidence: the audit reports `79 parseable fixture(s)` and `valid/14-sequenced-bodies.agentscript` at 23 (the plan's `D2` baseline said 77 and 25). The plan's baseline was simulation-pre-removal (`219 over 77`); post-W2 the real figure is `140 over 79` and is now locked.
- Class: any plan-prose figure that differs from the measured lockfile is stale prose — the lock is authoritative and `--write` is the only mechanism that changes it. The plan's specific numbers were advisory; the ratchet is the contract.
- Verdict: non-blocking. Plan prose should be re-stated to match the lock (140, 79, 23) before the phase commit message is drafted.

**m3 — `tools/tsutil.py` `search_json` iterates `for _match, captures in cursor.matches(tree.root_node)` — the API version is 0.26; older versions of tree-sitter return a single match dict.**
- Evidence: `tools/tsutil.py:103-110`. If the `tree-sitter` Python package is upgraded past 0.26 and the API changes to return `dict[capture_name, list[Node]]` directly, this will silently break. Currently works (`tools/t/test_edit.py::test_search_returns_captured_ranges` passes).
- Class: any version-pinned API surface needs an explicit version assertion. None present.
- Verdict: non-blocking — version pinned by environment.

## §6 — Risks / Unverified

- **Whether `agentscript` `parse_diag` produces the same shape as `checker/check.py` `Diagnostic.as_dict`** — verified for `wrong-arity` (one fixture), not exhaustively. The regex `(.+?):(\d+):(\d+):\s+([^:]+):\s*(.*)$` will fail on any checker message containing an extra colon before the code word; such messages would be flagged as `unparseable checker output` (rule 0). Not exercised by the current corpus.
- **Whether `test_interp_diag.py`'s `test_iocase_exit_writes_only_the_case_name` fixture compiles as a valid module through the lark parser** — only the `agentscript-interp` is exercised; the module is not run through `validate.py`. Compiles by hand-walking; could regress if module header grammar tightens.
- **Whether the bindgen generator's `:symbol` rule stays total when a host package has a name with characters outside `[a-zA-Z0-9_-]`** — `from_pyi.py:64-71` (`kebab`) raises `Unmapped` for those, which the calling `declarations()` catches and reports as `skipped`. Not exercised by `frames.pyi`.
- **`backend/differential.py` 15 program cases** — the test plan's stderr comparison was verified end-to-end (15 cases, 0 disagreements) but the cases that exercise evaluator-error stderr (i.e., exit-2) were not enumerated; differential program mode has no such case. If one is added in future, the new `path:line:col: <msg>` format will need to either match the python/rust/wasm arms (which currently don't print locations) or the case declaration will need updating.

## §7 — Verdict

**approve** — no blocker. All 9 acceptance commands green. The 13-variant failable span coverage is functionally proven (every variant prints `path:line:col: msg` with non-zero line/column). The dead pattern alternatives were removed from lark only and lark's tighter grammar does not reject any current fixture. The audit, budget, and span locks are exact-match. Differential agreement holds across all 4 arms for all 120 function + 15 program cases. The pre-Phase-6 gates are unmodified.
