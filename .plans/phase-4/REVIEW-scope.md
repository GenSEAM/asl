# REVIEW — Phase 4 plan · scope + gate integrity lens

Iteration: `asl-selfhosted-runtime-v1`.
Reviewed: `.plans/phase-4/PLAN.md` (5 items, 176 lines).

## Lens

Scope conformance to `.plans/PHASES.md` and the AGENTS.md gate contract; gate integrity
(fail-now / pass-after); anti-weakening. I read files; I did not run any heavy gate and
did not modify the plan.

## Verdict

**approve-with-amendments** — one non-blocking correction (see A2). No blockers.

## Independent verifications

| Plan claim | Evidence |
|---|---|
| 37 `.asl` files under `packages/` | `find ... -name '*.asl' \| wc -l` → **37** ✓ |
| 14 packages carry `.asl` | `sed 's\|.*/packages/([^/]+)/.*\|\1\|' \| sort -u \| wc -l` → **14** (asl-agent-bus, asl-codec, asl-eddie, asl-fsm, asl-harness, asl-lint, asl-mem, asl-parser, asl-search, asl-sh, asl-skyloom, asl-sql, asl-vdom, asl-voice) ✓ |
| Item 1 gate fails today: `grep -q "agentscript lint packages/" tools/hooks/pre-commit` | exits **1** (verified) ✓ |
| Item 1 source hook is missing lint and clone-check | `tools/hooks/pre-commit:17-33` runs 6 gates, none is `agentscript lint` or `clone-check`; `.git/hooks/pre-commit:17-36` runs 7 gates and contains both (lines 29, 32). The two files are genuinely divergent. ✓ |
| Item 2 gate fails today: `pytest tools/tests/test_native_parse_all.py -q` | `tools/tests/test_native_parse_all.py` does **not** exist (`ls` → "No such file or directory"). Module `tools.native_parser` does **not** exist either — `from tools.native_parser import parse_native` → `ModuleNotFoundError` (verbatim). ✓ |
| Acceptance criterion verbatim: `node .../pcp.js actualize && npm run build:web` | `.plans/PHASES.md:20` matches exactly. ✓ |
| AGENTS.md pytest gate includes `tools/tests` | `AGENTS.md:41` — `... backend/tests bench/algo checker/tests tools/tests -q` ✓ |

## Roadmap conformance — checklist

- **Final item re-runs the criterion verbatim.** PLAN.md:124-127 quotes the literal `node .../pcp.js actualize && npm run build:web` (PLAN.md:126) and adds `bash .git/hooks/pre-commit` after it (PLAN.md:127). The `&&` chain in PHASES.md is honored by also running the hook; the plan is faithful.
- **"Full 7-gate CI" interpretation is captured.** Plan treats the 7-gate hook + AGENTS.md wider gates as two distinct sets (PLAN.md:22 "installed 7-gate hook + the AGENTS.md wider gates"). Item 3 runs the wider gates (PLAN.md:90-94). Item 4 runs the installed hook (PLAN.md:108). Item 5 runs both plus the criterion (PLAN.md:124-127). No gate is dropped or added silently.
- **PHASES.md goal's "24 packages"** is explicitly corrected to 37 files / 14 packages (PLAN.md:11-15, scope-correction block). The header at PLAN.md:1-3 restates it ("CI hardening: native parser over every package, full gate chain, zero regressions"). ✓
- **Item 2 target is `packages/**/*.asl`.** PLAN.md:60 says "globs `packages/**/*.asl`, feeds each of the 37 files". Matches PHASES.md's "all 24 packages" goal translated to "every package's `.asl`". ✓

## Gate integrity

- **Item 1** — gate runs `grep -q` against the source hook; currently exits 1, will pass after gates 5/6 are appended. Distinguishable. ✓
- **Item 2** — gate runs the new pytest; currently fails with `No module named 'tools.native_parser'` (PLAN.md:78). Distinguishable once the test and parser module exist. ✓
- **Items 3-5** — gates are the commands themselves (PLAN.md:96, 113, 134). Status is **unverified-by-me**, as the plan declares. I did not run `validate.py`, `closure_audit.py`, `check_corpus.py`, `monomorphism.py`, `differential.py`, `prelude/generate.py --check`, `checker/gate.py`, `npm run build:web`, or `pcp.js actualize`. Per evidence standard these remain unverified.
- **Risk note (unverified).** Item 2's pytest imports `from tools.native_parser import parse_native`. Phase 3's actual entry point may not be `parse_native` (PLAN.md:148 acknowledges this: "entry-point name this plan assumed ... was a probe guess"). The gate command does not depend on the symbol name — it depends on the file existing — so this is a low-risk item for the implementer to fix at import-binding time. Not a blocker.

## Anti-weakening

- **Item 2's spec hard-fails on zero files** (PLAN.md:60 "The test hard-fails on zero files found, so a broken glob cannot green it"). ✓
- **Reports every failure, not first-fail** (PLAN.md:60 "reports **every** offending file with its diagnostic (not first-fail)"). ✓
- **No gate is weakened** — item 1 is pure strengthening, item 2 is a new check on top of existing gates, items 3-5 run the existing gate set verbatim, including the order and command lines from AGENTS.md:33-41.
- **"Not permitted" clause** at PLAN.md:80 forbids editing the test, fixtures, or any gate to make the parse-all pass — a parser defect routes to Phase 3's artifact, not the test.

## Non-blocking

- **A1 (cosmetic).** PLAN.md:50 cites the source hook as `tools/hooks/pre-commit:1-33`; the file is 36 lines. Trivial.
- **A2 (scope-completeness).** Item 2 enumerates `37 files` (PLAN.md:60) but only names one representative case ("other 13 packages"). Not a blocker — the implementer reads the glob, not the count. Worth keeping the explicit 37 because the `-->` N/M echo renumbering and the file count are the only numbers that auditors will cross-check against `find`.
- **A3 (silent assumption).** PLAN.md:13 says "14 packages, including `asl-parser`'s own `src/ast.asl`, `lexer.asl`, `reader.asl`". This is a fine scope statement, but it does not call out `asl-parser/tests/fixtures/{ast_driver,exec_smoke,tokenize_driver}.asl` and `asl-parser/tests/{lexer,reader}_test.asl` — those 5 files in fixtures/tests are included in the 37 and will be parsed by the native parser. Confirming intent is one sentence; not a blocker.
- **A4 (sub-step description).** Item 1's plan says "Copy gates 5 ... and 6 ... from the installed `.git/hooks/pre-commit:20-27` into `tools/hooks/pre-commit`". The actual installed-hook gate bodies sit at `.git/hooks/pre-commit:29-33`, not `:20-27`. The function names (`agentscript lint packages/` / `agentscript clone-check packages/ --threshold 0.15`) are correct; the line range is off by ~9. Cosmetic; not a blocker.
- **A5 (phase-criterion amplification).** PLAN.md:127 appends `bash .git/hooks/pre-commit` after the PHASES.md criterion. Strictly the PHASES criterion is the first half only; the second half is the plan's own addition. Worth recording in the commit that item 5 runs criterion + hook, not just criterion. Not a blocker — the criterion is run first, then the hook, which is what the goal text demands.

## Unverified

- Current pass/fail of: `validate.py`, `closure_audit.py`, `prelude/generate.py --check`, `checker/gate.py`, `backend/check_corpus.py`, `backend/monomorphism.py`, `backend/differential.py`, the four pytest packages (`backend/tests bench/algo checker/tests tools/tests`), `npm run build:web`, `pcp.js actualize`. Plan labels these "unverified-by-me" (PLAN.md:97, 113, 134); I confirm and follow the same constraint.
- Whether `.pcp/` is currently breach-free — only `pcp.js actualize` can say (PLAN.md:160).
- Node 22 LTS availability (PLAN.md:162) — not probed.

## Out of scope confirmed

- Not promoting native-parse test into hook as 8th gate (PLAN.md:167-169). Documented decision; already covered by AGENTS.md pytest gate. ✓
- Not fixing parser defects Phase 3 surfaces (PLAN.md:170-172). Phase boundary. ✓
- Not changing gate commands/thresholds/fixtures (PLAN.md:173). ✓
- Not migrating other Lark tools (PLAN.md:174). ✓

## Findings against the reviewer question

> *What would a conformant-but-wrong implementation still pass?*

- **Item 1:** a conformant implementation that *adds* lint+clone-check but breaks `prelude/generate.py --check` (e.g. deletes the checker gate by mistake) would still pass grep. The plan does not require running the hook after the edit — it requires only that the gate command (grep) passes. Item 4 runs the full hook and would catch it. Net: gate coverage holds.
- **Item 2:** a conformant implementation that adds a `try/except` swallowing parse errors would pass pytest. The "report every failure" and "hard-fail on zero files" specifications (PLAN.md:60) constrain that, but enforcement relies on the implementer honoring the spec, since the plan does not demand the test be reviewed for `try/except: pass` patterns. The plan's "Not permitted" clause at PLAN.md:80 documents the rule. Net: gate coverage is by convention + reviewer.
- **Items 3-5:** these are command-recording items. A conformant-but-wrong implementation that runs the commands but pastes fabricated "green" output would pass the gate. Mitigated by the broader reviewer's verify lens (records are data, not truth — the next reviewer re-runs).

No conformant-but-wrong path slips through silently.

## Amendments requested

1. **A4 (cosmetic line-range correction).** Update PLAN.md:50 from `tools/hooks/pre-commit:20-30` / `tools/hooks/pre-commit:1-33` and PLAN.md:46 from `installed .git/hooks/pre-commit:20-27` to the actual line ranges (source hook `tools/hooks/pre-commit:17-36`; gate bodies in installed hook `.git/hooks/pre-commit:29-33`). Optional — does not change what is built.
2. **A2/A3 (scope completeness sentence).** Item 2's "What" can add one line acknowledging that the 37 includes `asl-parser/tests/fixtures/*.asl` and `asl-parser/tests/*_test.asl`, so a reviewer of the test knows those are in scope and not exempted.
