# Phase 6 — Implementation review (conformance & gate integrity)

**Lens:** conformance to PLAN.md v2 (`232aae2`) + gate integrity
**Verdict:** `approve-with-amendments`
**Blockers:** 0
**Major findings:** 1 (conformance evidence only)
**Minor findings:** 2

## §1 — Acceptance battery (run this session)

Every gate in PLAN.md §4 was run independently. Verbatim results:

| Command | Result |
|---|---|
| `.venv/bin/python grammar/ambiguity_audit.py --check` | exit 0; `140 ambiguity node(s) over 79 parseable fixture(s)` |
| `.venv/bin/python tools/fmt/fmt.py --check grammar/corpus` | exit 0; per-file verdicts all `ok (idempotent)` |
| `.venv/bin/python -m pytest tools/fmt/t tools/t tools/bindgen/t -q` | exit 0; **277 + 52 + 8 passed** |
| `.venv/bin/python agentscript check grammar/corpus/valid` | exit 0; `0 diagnostic(s) across 29 file(s)` |
| `.venv/bin/python agentscript tokens` | exit 0; `12749 characters (lock: 12749)` |
| `.venv/bin/python prelude/budget.py --check` | exit 0; `12749 characters (lock: 12749)` |
| `.venv/bin/python tools/span_coverage.py --check` | exit 0; `13/13 failable variants carry a span` |
| `.venv/bin/python backend/differential.py` | exit 0; `0 disagreement(s) across 120 function cases + 15 program cases (python/rust/wasm/interp)` |
| `.venv/bin/python -m pytest tools/t/test_interp_diag.py -q` | exit 0; **14 passed** (one per failable variant + IoError bare-name regression) |

Plus the seven AGENTS.md gates and `pytest backend/t bench/algo checker/t`:

| Command | Result |
|---|---|
| `.venv/bin/python grammar/validate.py` | exit 0; `0 failure(s)` |
| `.venv/bin/python grammar/closure_audit.py` | exit 0; `executed builtins 107/107 (100%)` |
| `.venv/bin/python prelude/generate.py --check` | exit 0 |
| `.venv/bin/python checker/gate.py` | exit 0; `0 failure(s)` |
| `.venv/bin/python backend/check_corpus.py` | exit 0; `0 failure(s)` |
| `.venv/bin/python backend/monomorphism.py` | exit 0; `400 probes; rustc: ok; py_compile: ok` |
| `.venv/bin/python -m pytest backend/t bench/algo checker/t -q` | exit 0; **161 passed** |

Spot-runs of `cargo` are delegated to the orchestrator; the implementer's report (`cargo build -p agentscript-interp` succeeded, `test_interp_diag.py:14` build-and-run) was verified through the test passing.

## §2 — Per-item conformance (W1–W8)

### W1 — Ambiguity audit and ratchet

- `grammar/ambiguity_audit.py` materialised, builds a local `Lark(... ambiguity="explicit")` per call to `measure()` (`grammar/ambiguity_audit.py:71`), parses valid + semantic + modules via recursive globs (`ambiguity_audit.py:51–55`), counts `_ambig` recursively (`ambiguity_audit.py:35–43`).
- `--check` compares against the on-disk lock; `--write` records. **`--check` exit code 1 on any difference up or down** — the exact-match (D7) ratchet is implemented (`ambiguity_audit.py:101–110`).
- `grammar/ambiguity.lock = "140\n"` (`grammar/ambiguity.lock:1`) — strictly below the pre-phase baseline 219.

**Conformance: conformant.**

### W2 — Remove dead pattern alternatives; record the residual

- `git diff 232aae2 -- grammar/agentscript.lark` deletes the seven per-case `pattern` alternatives `OK/ERR/SOME/NONE/LIST/CONS/PAIR` (the diff hunk is exactly lines 91–97 of the pre-phase file), retaining the live `enum_pattern | literal | IDENT | WILDCARD`. Live alternatives verified at `grammar/agentscript.lark:91–94`.
- Auditor reported **140 over 79 parseable fixture(s)** — note 79, not the 77 cited in PLAN.md §1 / RECONCILIATION row 18. The implementer's measurement is fresh and the lock reflects it. PLAN.md prose (29 valid + 42 semantic + 6 modules = 77) is reconciled in `ORCHESTRATOR-LOG.md:310` ("the lock is authoritative, prose to be reconciled"). Both `validate.py` and `closure_audit.py` green.
- `--write` is the only path to a lower number, enforced by the exact-match ratchet.

**Conformance: conformant.** The 77/79 discrepancy is a prose-vs-lock drift recorded at ORCHESTRATOR-LOG.md:310; lock is authoritative.

### W3 — Re-integrate the formatter, renamed and re-pointed

- `tools/fmt/fmt.py` and `tools/fmt/t/test_fmt.py` materialised. The formatter's parser construction now imports `from parse import parser as _grammar_parser, FORM_KW as _TOOLCHAIN_FORM_KW` (`tools/fmt/fmt.py:51`), kills the third copy of parser construction, and adapts the keyword set to today's grammar (`FORM_KW = _TOOLCHAIN_FORM_KW - {"BANG"}` at `tools/fmt/fmt.py:62`).
- `*.agentscript` accepted everywhere. The 277-test suite (`pytest tools/fmt/t`) green; full corpus runs without error.

**Conformance: conformant.**

### W4 — Formatter idempotence gate on the corpus

- `tools/fmt/fmt.py --check grammar/corpus` runs the full corpus (77 fixtures excluding `invalid/`): every file reports `ok (idempotent)`.
- `tools/fmt/t/canonical.agentscript` + `canonical.expected.agentscript` materialised as a checked-in fixture pair asserting the canonical form is not the identity (`tools/fmt/t/canonical.agentscript:1`, `tools/fmt/t/canonical.expected.agentscript:1`). The test `test_canonical_fixture_formats_to_its_expected_form` is part of `test_fmt.py` and is among the 277 passing.
- `test_formatting_is_idempotent` + `test_formatting_preserves_the_tree` + `test_every_comment_survives` are parametrised over the same corpus (`tools/fmt/t/test_fmt.py:46–63`). A no-op formatter is rejected by `test_canonical_fixture_formats_to_its_expected_form`; a comment-dropper is rejected by `test_every_comment_survives`.

**Conformance: conformant.**

### W5 — Distributor `agentscript`, with edit/ast/search

- `agentscript` materialised at the repo root (`/Users/purplelephant/projects/asex/agentscript:1`). Re-uses `as-lang`'s `--json` and exit-code conventions.
- `BACKENDS = {"py": "to_python.py", "rs": "to_rust.py"}` (`agentscript:30`); `TREE_SITTER`/`GRAMMAR_DIR` repointed to `tree-sitter-agentscript` (`agentscript:31–32`); `--target`/`--rules`/`import_cycles`/`target_capabilities` are dropped per D1a (no D1a re-pointing happens in this file, but `cmd_check` runs the live `checker/check.py` subprocess — verified below).
- `cmd_check` delegates to `checker/check.py` as a subprocess with `--root grammar/corpus/modules` (`agentscript:80–91`). `--root` is the one argument the stashed shim did not pass; the corpus's search-path modules live under `grammar/corpus/modules`, and the checker must resolve against them.
- Subcommands added: `ambiguity`, `tokens`, `ast`, `search`, `edit`, `bindgen`, plus `check`, `build`, `fmt` (`agentscript:178–266`).
- D5 ops (replace/delete/insert) over source bytes; `agentscript edit` writes file in place. `tree-sitter build -o` produces `agentscript.so`; Python `Language()` load via ctypes (`tools/tsutil.py:48–55`).
- Smoke gates verified live:
  - `agentscript check grammar/corpus/valid` → exit 0, `0 diagnostic(s) across 29 file(s)`.
  - `agentscript check grammar/corpus/semantic/wrong-arity.agentscript` → exit 1, `1 diagnostic(s) across 1 file(s)` (W5's non-zero gate is satisfied per-fixture; the directory-level call returns exit 50 because the convention is exit = problem count, which is a stronger property than the plan's per-fixture gate).
  - `agentscript tokens` → exit 0.
- `pytest tools/t/test_edit.py -q` → **52 passed** (12 form classes × {replace, delete, insert}; delete-bytes-gone; round-trip; replace+reformat; ast dump; search; CLI smoke for build py/rs).

**Conformance: conformant.**

### W6 — Re-integrate bindgen (recorded gate-scope exemption)

- `tools/bindgen/from_pyi.py` + `tools/bindgen/t/{frames.pyi,frames.expected.agentscript,test_bindgen.py}` materialised from `b614ec8` per PLAN.md §2; expected file renamed `.expected.as` → `.expected.agentscript` (`tools/bindgen/t/frames.expected.agentscript:1`).
- 8 bindgen tests green (`pytest tools/bindgen/t -q` → `8 passed`). `bindgen` registered in the distributor (`agentscript:254–266`).
- **FFI parse-validation is exempted, not silently dropped.** Per `.plans/ORCHESTRATOR-LOG.md:308`: "W6 (bindgen) landed at **text level** ... but its emitted FFI declarations cannot parse-validate against Core because Core deliberately has no FFI (ROADMAP §3). **Orchestrator decision: accept text-level bindgen validation and record the FFI parse-validation exemption** — bindgen's output targets a future FFI surface." The underlying rationale is in `AGENT_SPEC_CORE.md:43–48` ("No FFI *yet* … reintroducing FFI later is additive rather than breaking") and `ROADMAP.md:90` ("Deliberately excluded: … FFI …"). This is durable (orchestrator log + spec + roadmap), not a subagent reply.
- `test_bindgen.py` contains no `parse` / `grammar` assertions — by design, since the parser has no FFI surface to validate against (`tools/bindgen/t/test_bindgen.py:1–66`, confirmed by inspecting the full file).

**Conformance: conformant under the recorded exemption.**

### W7 — Token budget ratchet

- `prelude/budget.py` records `len(HANDBOOK.md)` (`prelude/budget.py:23`); `--check` exact-match (`prelude/budget.py:35–43`); `--write` deliberate (`prelude/budget.py:30`).
- `prelude/budget.lock = "12749\n"` — matches the plan's 12,749-char baseline.
- `agentscript tokens` returns exit 0 with the recorded figure.

**Conformance: conformant.**

### W8 — Source spans on interpreter runtime errors

- `crates/agentscript-interp/src/ast.rs` re-shapes the 13 failable `Expr` variants to carry a `span: Span` field, with the four excluded variants (`Float`/`Str`/`Bool`/`Unit`) carrying none (`ast.rs:73–88`). `Int(IntLit)` reuses `IntLit.span`.
- `Expr::span()` method enumerates exactly the 13 failable variants (`ast.rs:91–110`).
- `crates/agentscript-interp/src/cst.rs` lowers tree-sitter node positions into each `span` field (`cst.rs:116–132` and following).
- `crates/agentscript-interp/src/eval.rs`: `Err` is now a struct carrying `located: Option<Located>`; `Display` writes `path:line:col: message` when located (`eval.rs:41–55`); `eval()` attaches the failing expression's span to otherwise-unlocated errors (`eval.rs:239–250`); `exit_glue` for IoError (case name only) is preserved by `test_iocase_exit_writes_only_the_case_name`.
- `crates/agentscript-interp/span.lock` records `denominator: 13, covered: 13, excluded: {Float, Str, Bool, Unit, each with reason}, covered_variants: [Ident, Qualified, Call, FieldAccess, If, Cond, Match, Try, Ctor, Record, Let, Int, Fn]` — every failable variant accounted for, exclusions named.
- `tools/t/test_interp_diag.py`: one fixture per failable variant; each stderr is asserted to match `^.*:(\d+):(\d+): ` with `line >= 1, col >= 1` (rejects `path:0:0:`). **14 passed** including the IoError regression.
- `differential.py` re-run: **0 disagreement(s) across 120 function cases + 15 program cases** with all four arms. The interpreter's stderr is now prefixed with `path:line:col:` for evaluator errors; program-mode IoError cases still emit the bare case name (`test_iocase_exit_writes_only_the_case_name` pins this). The `permission-denied`, `not-found`, `--labels`, `--slurp`, `log.txt` rows show full four-arm agreement.

**Conformance: conformant.**

## §3 — Gate integrity

`git diff 232aae2 -- backend/differential.py prelude/coverage.lock backend/cases backend/exec_coverage.py` → **empty** (verified). These four gates are untouched.

`git diff 232aae2 --name-only` shows exactly six modified paths:
- `.gitignore` — adds `grammar/tree-sitter-agentscript/*.so` (necessary because W5 builds the shared lib into the grammar dir; this is the tree-sitter CLI's default output location per `tools/tsutil.py:50`).
- `.plans/ORCHESTRATOR-LOG.md` — orchestrator's W6-decision note.
- `crates/agentscript-interp/src/{ast,cst,eval}.rs` — W8.
- `grammar/agentscript.lark` — W2 (7-line deletion, no additions).

Plus untracked (per `git status --short`):
- `agentscript` (W5), `crates/agentscript-interp/span.lock` (W8), `grammar/ambiguity.lock` (W1/W2), `grammar/ambiguity_audit.py` (W1), `prelude/budget.lock` (W7), `prelude/budget.py` (W7), `tools/bindgen/` (W6), `tools/fmt/` (W3/W4), `tools/span_coverage.py` (W8), `tools/t/` (W5/W8), `tools/tsutil.py` (W5).

**No pre-existing gate was weakened.** Every change to existing code is additive or strictly stronger:
- `validate.py`, `checker/gate.py`, `monomorphism.py`, `check_corpus.py`, `closure_audit.py`, `generate.py` — all byte-unchanged from `232aae2` (verified by running them; their exit code path was inspected and is unaffected by the W8 stderr change since the gate test suite compares the lowering pipeline's outputs, not raw interpreter stderr).
- `differential.py` — unchanged. Its `0 disagreement(s)` proves no agreement dropped under the new stderr prefix.
- `prelude/coverage.lock` / `backend/cases/` / `backend/exec_coverage.py` — diff is empty.

**No new gate is silently weaker than an old one.** Three new ratchets are exact-match (D7), which is strictly stronger than the design-reviewer's "fail if greater" alternative.

## §4 — W6 exemption durability check

The FFI parse-validation exemption is recorded in three durable places:

1. `.plans/ORCHESTRATOR-LOG.md:308` — the W6-decision paragraph, dated and attributed to the orchestrator.
2. `AGENT_SPEC_CORE.md:43–48` — "No FFI *yet*. This is a staging decision, not a permanent boundary".
3. `ROADMAP.md:90` — "Deliberately excluded: agents, UI, async, FFI, JSON serialization, I/O".

PLAN.md §3 W6 still describes parse-validation as part of the implementation, but `REVIEW-coverage.md` and the orchestrator log together document that the gate was downgraded (not silently: with reasoning). The implementer's `test_bindgen.py` correctly contains no parse assertion — a non-silent signal that the gate was deliberately not implemented.

**Durability: confirmed.**

## §5 — Major finding

### M1 — Plan §3 W6 prose says parse-validation was done; it was not

PLAN.md §3 W6 (line 296): "validate that the emitted declarations parse under the current grammar via `grammar/parse.py`". The implementer's `test_bindgen.py` does no such validation. The exemption is correctly recorded in `ORCHESTRATOR-LOG.md:308`, but the plan text is now stale. **Not a blocker** — the orchestrator decision to drop the gate is documented, and the gate it would have enforced does not exist (Core has no FFI). Class enumeration: the same gap would apply to any future "W6-style" work that depends on a parser feature Core deliberately lacks. The plan should be amended in a follow-up commit, not silently contradicted.

## §6 — Minor findings

### m1 — Plan §1 fixture count (77) does not match the auditor's fresh measurement (79)

PLAN.md §1 + RECONCILIATION row 18 both state 77 (29 valid + 42 semantic + 6 modules). The auditor's fresh run reports 79. `ORCHESTRATOR-LOG.md:310` records the disagreement and asserts the lock is authoritative. Not a blocker; the lock is the source of truth per D7.

### m2 — Stale stashes left in place

`stash@{0}` and `stash@{1}` (the latter is Phase 7's TS backend) are still present. PLAN.md §5 records "Deleting the stash after recovery is not planned. The stash stays; cleanup is the orchestrator's call." Not a conformance defect; flagged for the orchestrator.

## §7 — Risks

- **D5's Python `Language(init())` ctypes load is unverified by the implementer at review time.** The 52 `test_edit.py` tests passed in this session, which proves the mechanism works in practice; the loading path (`tools/tsutil.py:46–55`) is exercised by every test. Risks that future tree-sitter upgrades or grammar changes break this binding remain. The fallback (Rust edit CLI in a new `[[bin]]`) is documented but not staged.
- **`stash@{0}` contains a `grammar/as-lang.lark` that the plan did not recover.** `validate.py` and `closure_audit.py` are green, which means the live grammar is consistent; but if someone later materialises the stash's grammar file by accident, it could re-introduce a duplicate grammar. Worth deleting the stash (or its grammar file) before Phase 7 starts.

## §8 — Unverified

- The implementer's report that the `--root grammar/corpus/modules` argument to `checker/check.py` is required to resolve the corpus's search-path modules was not directly probed (the smoke test passes with `--root` set, but no negative control was run to confirm it fails without).
- `crates/agentscript-interp/src/main.rs` was not fully reviewed for stderr-shape guarantees beyond the `Display` impl on `Err` — the IoError path's exit-code discipline was confirmed only via the targeted test.

## §9 — Verdict

**`approve-with-amendments`** — every W1–W8 item landed as PLAN.md v2 specifies (M1 is a documentation drift, not a code defect); all 16 acceptance commands green; no pre-existing gate weakened; the W6 FFI exemption is durably recorded; the three exact-match ratchets (D7) are exact-match.
