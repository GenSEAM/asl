# REVIEW — Phase 6 plan, executability & gates lens

**Lens:** Each work item W1–W8 has (a) a literal failing-now gate that attributes to
it (not a later item) and (b) a working gate command the implementer can run; the
acceptance battery reproduces the AGENTS.md set; new gates are additive, not
weakening.

**Verdict:** approve-with-amendments

---

## Blockers

### B1. Acceptance battery omits the differential gate after W8 — exactly when its stderr comparison is at risk
- **What:** Phase 6's §4 acceptance battery is the new gates plus an unenumerated
  "AGENTS.md battery". W8 changes the interpreter's stderr text (adding
  `path:line:col:` prefixes to runtime errors). `backend/differential.py` program
  mode compares stderr text **across arms** and against a per-case declared value
  (`differential.py:368-388` — `seen["python"] == seen["rust"] == seen["wasm"] ==
  seen["interp"]` and `seen["python"] == want` where `want` includes `case["stderr"]`).
  The case files (`backend/cases/`) declare stderr as a literal string (e.g.
  `"not-found\n"` at `differential.py:431`). Adding a `path:line:col:` prefix to
  the interpreter's stderr will break program-mode agreement on every failing-path
  case (not-found, permission-denied, etc.) and break the declared-value check on
  the same cases. The plan acknowledges the risk in §5 ("Span threading touches
  the differential gate's stderr comparison … must be checked before W8 lands and
  strengthened, never relaxed") but no item, gate, or acceptance command in §3 or
  §4 runs `differential.py` against the post-W8 interpreter. There is no gate
  attributable to W8 that would catch a regression where the new stderr text
  diverges from the old case declarations.
- **Evidence:** `differential.py:368-388` (programs()), `differential.py:430-435`
  (19-io-errors declared stderr), `.plans/phase-6/PLAN.md:198-219` (§4 lists five
  new gates plus "the unchanged AGENTS.md battery" as prose only).
- **Make it right:** Add to §4 a literal `differential.py` invocation against
  the post-W8 interpreter with a checked-in expected (the current case
  declarations are a baseline; either update them or compare prefixes only). Add
  to W8's gate a re-run of `.venv/bin/python backend/differential.py` that fails
  if agreement count drops. As written, "differential.py … must be re-run after"
  is an instruction without a gate, and the instruction's enforcement is the
  whole point of AGENTS.md's gate section.

### B2. `validate.py` token-identity probes are not in any per-item gate — and W2's grammar edit is exactly the surface they protect
- **What:** `grammar/validate.py:108-187` (`token_identity()`) runs 13 probes that
  compare spans across the two grammars for terminals the two parsers once
  disagreed on (qualified types, sign-and-digits, division operator, etc.). W2
  deletes per-case `pattern` alternatives at `grammar/agentscript.lark:93-101`
  (the plan's PCP `l-b1b8`). W2's stated gate is `.venv/bin/python
  grammar/ambiguity_audit.py --check` plus `.venv/bin/python grammar/validate.py`
  (the latter currently passes — see plan). The plan asserts "the resolved tree
  is unchanged; verify by re-running all gates" but the resolved tree is the
  Earley resolution result; the token-identity probes check **spans** of named
  terminals, which the grammar edit could move. No per-item gate pins "after
  W2, the 13 token-identity probes still agree". If W2 lands and a probe starts
  failing, the plan's only protection is the per-item check it already names —
  and W2's gate does not distinguish a passing `validate.py` from a passing
  `validate.py` whose token-identity block silently flipped.
- **Evidence:** `grammar/validate.py:108-187` (token_identity), `grammar/agentscript.lark:93-101`
  (target of W2 edit), `.plans/phase-6/PLAN.md:118-126` (W2 gate is `validate.py`
  plus ambiguity check).
- **Make it right:** Either (a) split the W2 gate to print `validate.py`'s
  per-probe line and fail if any `token identity/*` line is FAIL, or (b) add to
  §4 an explicit `python -m grammar.validate` whose output diffs against a
  locked baseline of the 13 probe verdicts. The plan has the right intent ("the
  resolved tree must be unchanged"); it does not have a check.

---

## Non-blocking

### N1. W3's gate does not run the new `fmt --check grammar/corpus` over the current corpus — only pytest
- **What:** W3's failing-now gate is `.venv/bin/python -m pytest tools/fmt/t -q`.
  W4 adds the `fmt --check grammar/corpus` gate but its failing-now evidence is
  the missing script, not a corpus-level run. The plan's own §5 says "Formatter
  fit to the current grammar is unverified" — and the fit surface is the full
  corpus (43 fixtures), not the test suite alone. A test that asserts the
  formatter runs on three hand-picked snippets will pass while a corpus fixture
  breaks idempotence.
- **Evidence:** `.plans/phase-6/PLAN.md:127-142` (W3) and `.plans/phase-6/PLAN.md:144-156`
  (W4).
- **Make it right:** W3's exit criterion should be "the full pytest suite for
  fmt passes AND `tools/fmt/fmt.py --check grammar/corpus` reports idempotent
  for every fixture". Currently W3 stops at the smaller one and W4 stops at
  the existence of `--check` — there is no per-item gate that requires the
  corpus-level check is green at W3's end.

### N2. Materialisation recipe works but the prose phrase "`git stash show -p stash@{0}^3`" would fail
- **What:** The plan refers to the stash parent as `stash@{0}^3` in §1 and §2.
  `git stash show -p stash@{0}^3` returns `fatal: 'stash@{0}^3' is not a stash-like commit`
  (verified). The actual recovery command is `git show 'stash@{0}^3:<path>'`,
  which works for all three files. The plan never instructs `git stash show -p`
  explicitly, but a reviewer or implementer copying the prose would hit the
  error.
- **Evidence:** verified: `git stash show -p 'stash@{0}^3'` returns the fatal
  message; `git show 'stash@{0}^3:as-lang'` returns the 202-line script.
- **Make it right:** In §2, replace "stash@{0}^3 (`git show 'stash@{0}^3:<path>'`)"
  phrasing with an explicit recovery command, e.g.
  `git show 'stash@{0}^3:as-lang' > agentscript && chmod +x agentscript`.

### N3. Plan lacks a gate for `tools/span_coverage.py` counting every variant — easy to ship a check that always passes
- **What:** W8 introduces `tools/span_coverage.py` which parses `ast.rs` and
  counts variants-with-`span` over total `Expr` variants. The baseline is 1/17
  (`ast.rs:53-63` carries the only `Span`). An implementer who adds `pub span:
  Span` to a variant but never threads the value from `cst.rs` will trip no
  gate: the count rises, the lock can be `--write`d to the new figure, and the
  runtime-error stderr test (`tools/t/test_interp_diag.py`) only asserts a
  regex match on *one* error path. A regression that adds a `span` field to a
  variant whose `Eval` site prints nothing located would still pass.
- **Evidence:** `.plans/phase-6/PLAN.md:226-242` (W8).
- **Make it right:** `test_interp_diag.py` should exercise at least one error
  per **runtime-failure branch** in `eval.rs` (the plan names 11 variants; an
  implementer covering all of them is the gating contract). Alternatively, have
  `span_coverage.py` only count a variant when a regex finds a reference to it
  inside `eval.rs`'s error sites.

### N4. `prelude/budget.py` is checked at §4 but not run after W5 lands the `tokens` subcommand — coupling is implicit
- **What:** W7 adds `prelude/budget.py --check`; W5 registers a `tokens` subcommand
  that delegates to it. The plan orders W7 after W5. The acceptance battery in
  §4 lists `prelude/budget.py --check` but no per-item gate for W5 includes
  "after W5 lands, `agentscript tokens` exits 0 on the current HANDBOOK". The
  shell command `.venv/bin/python prelude/budget.py --check` is the only check,
  and it does not exercise the distributor surface that W5's order-coupling
  claims to protect.
- **Evidence:** `.plans/phase-6/PLAN.md:211-224` (W7), `.plans/phase-6/PLAN.md:164-181`
  (W5).
- **Make it right:** Either include a `agentscript tokens` invocation in §4 or
  explicitly drop the "after W5" ordering claim and accept that W7's budget.py
  test is the contract.

### N5. Plan does not specify `agentscript check grammar/corpus/valid` as a gate even though it's the §3 acceptance proof
- **What:** §5 in PHASES.md says acceptance for Phase 6 includes formatter,
  bindgen, and the distributor hosting them. W5's gate mentions `agentscript
  check grammar/corpus/valid` as a CLI smoke test in passing, but it is not a
  per-item gate. If the implementer leaves `agentscript` with no `check`
  subcommand after W5, no gate fails.
- **Evidence:** `.plans/phase-6/PLAN.md:164-181` (W5 prose).
- **Make it right:** W5's gate should be `.venv/bin/python agentscript check
  grammar/corpus/valid` exits 0 AND on `grammar/corpus/semantic/<one-fixture>`
  exits non-zero.

---

## Verified

- **W1** gate command fails now with the literal `[Errno 2] No such file or
  directory` for `grammar/ambiguity_audit.py`. Verified by running it.
- **W3** gate command fails now with `ERROR: file or directory not found:
  tools/fmt/t`. Verified.
- **W4** gate command fails now (script missing). Verified.
- **W5** gate command fails now (pytest target missing AND `agentscript` script
  missing). Verified.
- **W6** gate command fails now (`tools/bindgen/t` missing). Verified.
- **W7** gate command fails now (`prelude/budget.py` missing). Verified.
- **W8** gate command fails now (`tools/t/test_interp_diag.py` missing).
  Verified.
- **Stash materialisation works.** `stash@{0}^3` is the untracked-files commit
  at `4e8d92fb815b8540296a24c8fdf9c77ca81a64df` (`git rev-parse 'stash@{0}^3'`)
  and contains exactly three relevant blobs: `as-lang` (100755, 202 lines),
  `tools/fmt/fmt.py` (932 lines), `tools/fmt/t/test_fmt.py` (485 lines). All
  three recover cleanly via `git show 'stash@{0}^3:<path>'`.
- **Bindgen materialisation works.** `b614ec8` contains exactly the four
  bindgen files listed (`from_pyi.py`, `t/frames.pyi`, `t/frames.expected.as`,
  `t/test_bindgen.py`). All four recover cleanly via `git show b614ec8:<path>`.
- **Per-W1 auditor ordering is correct.** The auditor does not yet exist; W2's
  grammar edit must come after W1, not before, otherwise the "before/after
  numbers" the lock records are not measurable. Plan orders correctly.
- **W3/W4 ordering is correct.** The formatter script must exist before its
  gate can be run; W4's gate references the script W3 produces.
- **W5's ordering claim is supported.** `agentscript` references
  `tools/fmt/fmt.py` (the import path is hard-coded at `stash@{0}^3:as-lang:14`
  — `sys.path.insert(0, str(ROOT / "tools" / "fmt"))`) and `tools/fmt/fmt.py`
  in turn references `grammar/as-lang.lark` (the path the implementer will
  rename to `grammar/agentscript.lark` or replace with `parse.GRAMMAR`).
- **Phase 5 interp is built and binary exists** (referenced from
  `differential.py:243`). W8's `cargo build -p agentscript-interp` will work
  without bootstrapping.
- **`validate.py` will exercise `corpus/valid` + `corpus/invalid` + rglob
  `corpus/semantic` + `corpus/modules`** — so removing the `pattern`
  alternatives (W2) cannot silently change a fixture's verdict class unless
  resolution diverges. This is a real protection, just not the one B2 names.
- **`closure_audit.py` reports closure and executed coverage today** (ran it:
  `OK: spec and corpus are closed, and every builtin is executed`,
  `107/107 (100%)`). W1/W2 do not add or remove vocabulary, so this gate's
  count is preserved by construction.
- **`prelude/generate.py --check` is unaffected.** Plan explicitly notes
  budget is a separate script (`PLAN.md:88-89`) — verified: there is no
  coupling through `prelude.json`.
- **Plan does NOT re-canonicalise the corpus** (explicit `PLAN.md:78-82`,
  `PLAN.md:D6`). Confirmed — the formatter's `--check` compares its own output
  to itself, not to on-disk fixtures, so `bench/algo/*.agentscript` and
  `backend/cases/*.agentscript` byte-identity is preserved.

---

## Unverified

- **Whether W2's removal of the `pattern` alternatives preserves the resolved
  tree's span structure for the 13 token-identity probes.** I did not re-derive
  the probe sources through a tree-sitter parse; the probes are complex
  expressions (qualified types, type applications, negative literals) but none
  of them uses a `pattern` rule. The risk is that removing an Earley alternative
  changes how the grammar's lexer disambiguates, which can move token spans
  even on probes that never match the rule. The plan's "verify by re-running
  all gates" hedge is correct but loose.
- **Whether `tree-sitter build -o` succeeds for `grammar/tree-sitter-agentscript/`.**
  Plan §5 calls this out as unverified; I did not test it either. W5 has a Rust
  fallback plan that keeps the surface unchanged.
- **Whether `frames.expected.as` from `b614ec8` parses under the current
  grammar and resolves against the current `prelude/prelude.json`.** Plan §5
  acknowledges this; the expectation is that the implementer edits the fixture.
- **Whether `tools/fmt/fmt.py` from the stash will run unchanged against the
  current grammar.** Plan §5 acknowledges this and lists three token names that
  no longer exist. I confirmed `DEFENTRY`/`DEFEXTERN`/`DEFOPAQUE` are absent
  from `parse.py:24-28`'s `FORM_KW` (it lists `DEFUN`/`DEFSCHEMA`/`DEFENUM`).
  The fix effort is unknown until W3 runs.
- **The 219 ambiguity baseline.** I ran a probe (190 `_ambig` nodes across
  `corpus/valid` + `corpus/semantic` alone — close to but not equal to the
  plan's 213 + 6 = 219; the plan includes `corpus/modules` which I did not
  count). The mechanism works; the exact total is approximate and the lock
  will pin whatever the implementer's first run produces.
