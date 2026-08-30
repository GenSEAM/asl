# Phase 7 plan reconciliation

Input: `.plans/phase-7/PLAN.md` v1; `REVIEW-design.md` (6 findings), `REVIEW-exec.md`
(7 findings), `REVIEW-coverage.md` (7 findings); plus one carried-risk note from the design
review's risk section. 21 items in; 17 rows out — three duplicate clusters merged
(design M1 + exec W5-cd; design m1 + exec 23-numeric; exec B2 + coverage B2 + coverage m2).
Every disposition below was checked against the cited file this session before acting.

| # | Finding (review · id) | Disposition | Where in v2 / evidence |
|---|---|---|---|
| 1 | design · B1 — frozen `--noEmit --strict --target es2020 --module commonjs` cannot resolve `node:fs`/`process` types from `/tmp` build dirs (TS2307/TS2580, exit 2) | **accept** | D4 flag set gains `--typeRoots <repo>/node_modules/@types --types node`, marked non-optional with the failure mode spelled out; W3/W4/W5 gate literals carry it; W2 records the verified-green set. Verified `rt.ts:546-547` imports and `:637` `process.argv` in the stash. |
| 2 | design · M1 — W3 gate redirects before `mkdir`; W5 gate `cd /tmp/p7-io` breaks relative paths afterward (merged with exec's "W5 redundant cd" note) | **accept** | W3/W4/W5 gate text rewritten: `mkdir`/`cp` first, repo-root cwd, no path-breaking `cd`, the one needed `(cd /tmp/p7-io && …)` subshell scoped with `test $? -eq 1` inside it. |
| 3 | design · M2 — Node `error.code` mapping omits `ENOTDIR`/`EISDIR` → `invalid-path` | **accept-modified** | D2's table gains the `ENOTDIR`/`EISDIR` row. **Modified:** the reviewer's "keep `EINVAL` (defensive)" is rejected on evidence — both duals map `EINVAL` to `other` (Python `_ERRNO` has no key 22, `runtime.py:269-273` falls to the `.get` default; Rust `_ => IoError::Other`, `rt.rs:266-268`), so a TS `EINVAL→invalid-path` would itself be the divergence D2 forbids. `ENAMETOOLONG` likewise → `other`. Table is dual-faithful case for case. |
| 4 | design · M3 — fork's pattern matcher has no prelude-union seeding; `(err (not-found))` drops its tag test and matches every `err` | **accept** | W3 gains rework 4: seed `vocab.unions()` cases into the matcher, with the consequence spelled out; §5 gains the matching risk. Verified: `to_python.py:57-60` seeds; grep of the stash transpiler for `unions\|IoError\|vocab` → zero hits; `arm()` at stash `:401-416` hardcodes `ok/err/some` only. |
| 5 | design · m1 — "23-numeric is the one function-task source containing `import`" is false (merged with exec's function-mode-coverage note, which confirms zero `:import` clauses across function tasks) | **accept** | D1's evidence replaced: seven module fixtures (06, 09-13, 15, each with `:import`/`(import`) + program cases 13/15; the function-mode need is stated as currently vacuous but required by the no-skip principle. Verified: the only `import` token in `23-numeric.agentscript` is `__import__` inside its `; run:` comment (line 12). Decision unchanged. |
| 6 | design · m2 — D4's `@types/node` risk understates; the verified-green flag set should be recorded in W2, not just version pins | **accept** | W2 "what changes" records the full flag set alongside the pins; D4 carries the verified facts (no `"type": "module"`, no post-ES2020 API in `rt.ts`, node 22). |
| 7 | design review, carried-risk section — stash `rt.ts:564-572` swallows a failing stdin read into `""`; live hosts map stdin failure to an `IoError` (`runtime.py:283-295`) | **accept** | §2 `rt.ts` inventory line names the swallow; W5 routes the stdin catch through `codeToIoError`. Not a numbered finding — folded because it is a live divergence in the code being recovered. |
| 8 | exec · B1 — W1's gate only asserts every builtin has a `ts` key; the widened `validate_templates()` is never run, so 107 parse-clean-but-broken templates pass | **accept** | W1's gate is now a three-way conjunction: key presence, the widened validator filtered to `ts` complaints (must be empty), then `generate.py --check`; the tuple widening is pinned to happen before the gate runs. Verified: tuple is `("py","js","rs")` at `generate.py:165` and the validator only iterates that tuple. Gate strictly tightened. |
| 9 | exec · B2 — W7's gate cannot catch a TS arm that miscounts function-mode cases or silently returns `[]` (merged with coverage · B2 — forwarding-stub arm agrees trivially, `differential.py:407` has no per-arm execution proof; and coverage · m2 — no asserted summary string) | **accept** | One row, one fix. W7: function-mode length guard explicitly extends to `len(ts)`; program-mode agree gains `seen["ts"]`; the gate runs the full differential, requires exit 0, and greps the summary for `python/rust/wasm/interp/ts`. §1 gains the "Anti-stub measures" block recording the chosen measures (per-task instruction): (1) independent `tsc` over every fixture's emitted TS via W6, (2) five-arm summary string asserted, (3) declared stderr bytes derived independently per host. Gate strictly tightened. |
| 10 | exec · NB — W4's "fails before writing" claim is accurate but fragile; gate should also check the rendered module carries qualified names as mangled identifiers | **accept** | W4's gate gains `grep -qE '[A-Za-z0-9]+_[A-Za-z0-9]+__' main.ts` (the defining-path prefix form `to_python.py:47-51` produces), so an import-discarding `link()` fails on content, not just on `tsc`. |
| 11 | exec · NB — W3's quoted gate output path prefix | **reject** | The reviewer's own verification concludes the wording is right ("The gate's wording is right") and the absolute path is whatever cwd expands to. Not a defect; nothing to change. |
| 12 | exec · NB — acceptance battery step 9 is editorial, not a command (`exec_coverage.py --check` does not exist) | **accept** | §4 item 9 rewritten as plain prose stating the no-new-floor decision and the tracer's Python-only scope. |
| 13 | coverage · B1 — W6's string-presence gate accepts a stub transpiler: a fixture whose TS transpile "succeeds" with empty/stub output gets `tsc: ok` or a skipped column | **accept** | W6 gains two fail-loud rules written into the plan: a TS transpile failure appends to `fails` exactly as the python/rust columns do (`check_corpus.py:104-108` shape, verified), and an empty emitted source is itself a `FAIL`. D5's `build_typescript` raises on empty emission too. Gate strictly tightened. |
| 14 | coverage · B3 — W5's gate pins only `not-found` (and W7 adds `permission-denied`); the other four IoError cases have no failing-path differential case | **accept-modified** | Closed at the unit level rather than by inventing differential fixtures: W5's gate gains part 2 — a TS harness calling the exported `codeToIoError` on all six cases of D2's table — and W5/§5 state plainly that the differential pins 2/6 by stderr bytes, matching `prelude/coverage.lock:512-515` (verified: all four listed `unproven` with unreachable-host-mapping reasons). No gate weakened; the gap is enforced where the mapping is the unit under test. |
| 15 | coverage · M1 — stash prelude is v0.3 vs live v0.2; `validate_templates()` checks format arity only, so cross-version recovery carries unenforced signature assumptions | **accept-modified** | The arity half is already closed by finding 8's widened-validator gate (arity is checked against the live declared type). The symbol half — a template emitting an `rt.ts` helper that does not exist — is enforced only on the exercised surface (W6's tsc column), the same level live `js` keys have; that residual is recorded verbatim in §5 risk 1 rather than papered over with a new exhaustive gate nobody scoped. Verified: versions `0.2`/`0.3` at `prelude.json:5` both sides; validator body checks format only. |
| 16 | coverage · M2 — coverage/exec figures unchanged by ts templates, but the claim is not enforced | **reject** | Already handled by the plan, and the reviewer's own conclusion is "no amendment is needed": v1 §4 item 9 and §5 already state the tracer is Python-only (`backend/exec_coverage.py:31-32`, `:127`, `:140-153` — verified) and figures live in `prelude/coverage.lock`. v2 keeps the statement as prose (finding 12). |
| 17 | coverage · m1 — tsgo switchover lacks a recorded criterion; W3's minimal fixture would not exercise `bigint` | **accept-modified** | The decision point is moved to W6's corpus-wide compile (every fixture, including the bigint-heavy ones, must compile under classic tsc or the switch is re-recorded with the failing construct shown). D4 and §5 updated accordingly. |

## Tally

- accept: 11 (rows 1, 2, 4, 5, 6, 7, 8, 9, 10, 12, 13)
- accept-modified: 4 (rows 3, 14, 15, 17)
- reject: 2 (rows 11, 16)
- 17 rows / 21 items in (20 numbered findings + 1 carried-risk note); nothing dropped.

## Gate-tightening check (hard rule)

Every gate amendment adds checks; none removes or loosens one: W1 gains the widened-validator
conjunction; W4 gains the mangling grep; W5 gains the six-case mapping harness; W6 gains the
transpile-failure and empty-emission fail rules; W7 gains the exit-0 run and the five-arm
summary assertion. No declared differential value, no existing AGENTS.md gate, and no arm
count changed.

## Orchestrator attention

One reviewer claim was corrected on evidence, not preference: design M2's suggestion to keep
`EINVAL → invalid-path` would have introduced exactly the cross-arm divergence D2 exists to
prevent (both Python and Rust map `EINVAL` to `other` — `runtime.py:269-273`,
`rt.rs:266-268`). Row 3 records it; no other reviewer citation failed verification.
