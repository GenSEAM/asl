# REVIEW — coverage lens

**Lens:** coverage — what conformant-but-wrong implementations still pass this plan's gates?

**Verdict:** reject

**Blocker count:** 3 blockers, 2 majors, 2 minors.

---

## Findings (severity + evidence)

### B1 — The tsc gate is not yet asserted for any subset, and the plan claims it gates every corpus fixture

**Severity:** blocker.

**What is wrong:** The plan's acceptance sentence 2 says *"tsc accepts the emitted output for every fixture `check_corpus.py` gates."* The W6 gate is `assert 'to_typescript' in s, 'check_corpus.py has no ts column'` — a string-presence check. After W6 lands, the column runs `tsc` only on fixtures whose TS transpile succeeds. A TS transpiler that emits a stub `function main(): void {}` for a fixture it cannot lower (silently swallowing the failure instead of raising) leaves `tsc` with nothing to reject, and the column prints `ok` because tsc did not fail — the table column is `"tsc": "ok"`, the fixture looks fine, and the gate says nothing. The `check_corpus.py` gate has no provision that requires a TS-transpile FAIL to be a real failure rather than an empty output, because the gate currently has no TS column at all (file is unchanged today). The plan does not assert that transpile MUST succeed; it only asserts tsc must run on the transpile's output.

**Evidence:**
- `backend/check_corpus.py:88-91`: `transpile()` returns a `(ok, src, err)` triple; the calling code at line 98 calls `transpile("to_python.py", f)` — the transpile failure is logged but never fails the gate, only the absence of the transpiled source disqualifies the next two columns. A TS column that follows the same shape accepts a stub-transpile.
- `backend/check_corpus.py:96-112`: the rustc step writes a `fails.append` line on rejection but is silent on transpile failure. After W6 the same shape is preserved.
- `prelude/generate.py:170-186` validates every template formats at declared arity; the plan says `validate_templates()` will surface the 100 recovered templates' arity mismatches. But the validator only checks format-string arity, not whether the resulting TS code type-checks under `--strict`. A `ts` template that emits e.g. `RT.add(a, b)` against the live `rt.ts` (which carries the corrected D2 signature) will pass `validate_templates()` and fail `tsc` — that IS the design. But the failure only surfaces for fixtures where transpile succeeds. A transpiler that returns a stub for the unhandled form passes silently.

**Why this matters:** the corpus has 28 valid fixtures. The fork predates 16-29 (the plan acknowledges this in §5). If the transpiler cannot lower e.g. `16-recursive-schema.agentscript` (self-referential `(Option Node)` field, boxed), the current design records "transpile FAIL → tsc skipped". Nothing distinguishes "I cannot lower this form" from "I just did nothing".

**What would make it right:** Either (a) `check_corpus.py` must reject an empty/transpile-fail body before the tsc column (e.g. require tsc to be present and reach the target file even on transpile failure), or (b) the transpiler must raise on any live-form source it cannot lower (W3 says it does for `NotImplementedError`, but the live fork has no such safety net for forms 16-29). The plan does not commit to either.

### B2 — The differential "five arms agree" claim permits a vacuous implementation that runs no fixture

**Severity:** blocker.

**What is wrong:** A `build_typescript(src, d)` that returns `["node", "/path/to/some/python/script.py"]` would "agree" with the python arm because both produce the same python output. The plan's "no skip mechanism" claim (D5: *"A TS transpile or tsc failure inside the gate is a raised error — the gate fails, nothing is skipped."*) closes half the hole: if tsc rejects, the gate fails. But it does not close the other half: a TS arm that is wired but never runs the JS code (e.g., transpiles to TS but executes via the python harness, OR emits a stub TS that prints the python arm's output verbatim) will pass the agreement check and pass tsc.

The plan's gate at W7 is `assert 'build_typescript' in s` — again, string presence. The acceptance battery says `.venv/bin/python backend/differential.py` should "agree on five arms" but provides no counter assertion. With the existing `programs()` shape (`backend/differential.py:393`), `runners["ts"]` is added to the dict and the `agree = seen["python"] == seen["rust"] == seen["wasm"] == seen["interp"]` expression (currently `:408`) is extended to include `seen["ts"]`. A conformant-but-wrong implementation:

- emits a TS file whose `main` reads `process.argv`, calls `python3 -c "import json,sys; sys.stdout.write(open(sys.argv[1]).read())"` and forwards, or
- forks the python transpile output and emits it as the TS source so both arms run the same code.

In either case, `seen["ts"]` equals `seen["python"]` for stdout and stderr (same process, same outputs), and the `bad += 0 if (agree and declared_ok) else 1` invariant holds. Exit codes would also match. The gate says nothing.

**Evidence:**
- `backend/differential.py:407`: `agree = seen["python"] == seen["rust"] == seen["wasm"] == seen["interp"]` — adding `== seen["ts"]` to this expression with no further check.
- `backend/differential.py:418-421`: the 08-io failing case has declared `stderr="not-found\n"`. If TS arm prints anything, it must match this byte-for-byte. A "forward python output" TS implementation passes this trivially.
- The plan §W7 says "Declaring `exit code stays the disagreement count`" but does not commit to a check that distinguishes five distinct transpilers.

**What would make it right:** Either (a) the gate must assert a `ts_was_run` counter is nonzero before exit 0, or (b) the summary print string must name five distinct transpilers (e.g. assert `'ts'` appears as a column header in the `programs()` table), or (c) — preferable — the runner must require `rt.ts`'s `mainExit` to be called (an `ErrorKind`-derived stderr string cannot be faked from python).

### B3 — The W5 IoError case mapping is asserted only on the happy path and one failing path

**Severity:** blocker.

**What is wrong:** The plan §W5's gate is the 08-io failing write, which checks `stderr="not-found\n"`. That pins one case (`not-found`). The plan claims the gate proves six cases. But:

- `08-io.agentscript` (`:420`) declares ONE failing case — argv `["sample.txt", "nodir/out.txt"]` with stderr `"not-found\n"`.
- `19-io-errors.agentscript` declares TWO failing cases (`differential.py:436-439`): the `not-found` case and the `permission-denied` case (via a `0o000` file).
- The other four (`already-exists`, `invalid-path`, `interrupted`, `other`) are declared by `--labels` (`differential.py:441`) and `--slurp` (`:445`) cases but are not exercised by any failing-path program case.

The differential gate therefore pins 2/6 cases by byte-for-byte stderr agreement. The plan §W5 says *"the declared `not-found`/`permission-denied` stderr lines ... are exactly what this item produces"* — that is accurate for two cases. The remaining four are unmapped: a `codeToIoError` mapping that drops `EEXIST → already-exists` and maps it to `other` instead would pass W5's gate, pass W7's gate (the only cases that compare stderr byte-for-byte are the two pinned ones), and leave the other four cases silently divergent on whatever future program case lands there.

**Evidence:**
- `backend/differential.py:422-446` (19-io-errors cases): only argv `["nodir/out.txt"]` and `["noperm.txt"]` produce non-empty stderr; the other four IoError cases are not exercised in any program's failing path.
- `prelude/coverage.lock` lines for `already-exists`, `invalid-path`, `interrupted`, `other`: all are listed in `unproven` with reason "the host EEXIST/ENOTDIR/EINTR mapping is reached by no portable case" or "fallback host mapping is not reachable deterministically" — which is exactly the gap. The plan does not propose new failing-path cases for any of these.
- The plan §W5 says the gate is `08-io.agentscript`'s failing write: `test "$(cat err.txt)" = "not-found"`. That asserts ONE case.

**What would make it right:** Either (a) add new failing-path program cases that exercise `already-exists`, `invalid-path`, and the fallback mapping — at minimum a `EEXIST` case (open-existing-file-with-O_EXCL, or write to an existing path under a fixture that has one); or (b) commit to this gap by stating in the plan that four of six cases are unenforced by the differential gate, with the IOCP rationale; or (c) make the unit-test level (`backend/t`) the enforcement site and name that file as the new gate. The plan does none of these.

### M1 — Stash templates are written against v0.3 prelude; live is v0.2 with different declared types and constructor lists

**Severity:** major.

**What is wrong:** The plan §W1 recovers 100 templates from `git show 'stash@{1}:prelude/prelude.json'`. Inspection shows:
- Stash `version` is `0.3`, live is `0.2` (prelude.json:5).
- Stash `special_forms.declarations` includes `defentry`, `defextern`, `defopaque`; live has only `module, defschema, defenum, defun`.
- Stash `special_forms.constructors` is 6 names; live is 12 (the six IoError constructors are absent from stash `constructors`).
- Stash has no `IoError` union.

`validate_templates()` only checks format-string arity (`prelude/generate.py:178-185`). It does not check that the template's name list matches the live prelude's names. A template named after `args` (live: absent) against a builtin named `file-append` (live: present) cannot exist, but the reverse is the problem: 100 templates matching by name against 107 live builtins. The plan says the 3 fork orphans (`args`, `env-get`, `process-run`) are dropped — but the cross-version template recovery carries a much larger set of assumptions. For example:

- Stash `file-append` may not exist as a builtin (live prelude has it). Or it may exist with different `type`. Either way the `validate_templates()` check (only arity, not signature) lets through an inconsistent template that the live checker would reject, but `validate_templates()` doesn't talk to the checker.

**Evidence:**
- `prelude/prelude.json:5` (live): `"version": "0.2"`.
- `git show 'stash@{1}:prelude/prelude.json'` line 5 (verified): `"version": "0.3"`.
- `prelude/prelude.json:16-23` (live): constructors list includes the 6 IoError names; stash list does not.
- `prelude/generate.py:170-186`: validator only format-checks at declared arity; does not cross-check signatures against the live types.

**What would make it right:** W1 should add a per-template signature cross-check (the live builtin type is fetched and the template is sanity-rendered with appropriate placeholders), or commit to re-deriving at least the diff'd templates by hand rather than wholesale recovery.

### M2 — Coverage floor and exec figures are unchanged by ts templates, but the assertion that they remain unchanged is not enforced

**Severity:** major.

**What is wrong:** The plan §D5 and §W1 claim TS templates do not affect `exec_coverage.py` (Python-only tracer) or `closure_audit.py` (names, not template keys) — this is accurate. But:

- The plan does not run `exec_coverage.py` as part of the acceptance battery (item 9 says it is NOT a new floor).
- `closure_audit.py` runs (item 2) but uses `vocab.builtins` (the declared names), not template keys. So adding `ts` to every builtin does not change the call-head set.

This means a coverage gate already passing stays green. But the plan is silent on whether the `js` keys currently in `prelude.json` (which exist but never fed any transpiler) have an analogue that breaks under `validate_templates()`. The live `js` keys pass `validate_templates()` today (they format cleanly at their live arities). Adding `ts` keys does the same check.

The coverage floor (95%) in `prelude/coverage.lock` is enforced by `exec_coverage.py` which only counts Python-side execution. Adding a TS arm that passes its gates does not move this figure.

**Evidence:**
- `prelude/coverage.lock:5`: `"executed": 107`.
- `backend/exec_coverage.py:31-32`: "execution is recorded on the Python side only" — TS arm is invisible to the tracer.
- `prelude/generate.py:174-184`: validator scans `("py", "js", "rs")`. The plan says the tuple becomes `("py", "js", "ts", "rs")`. After the change, `js` templates still format-check, `ts` templates format-check, `rs` templates format-check. No coverage movement.

**What would make it right:** This is actually a finding that the plan is correct about, so no amendment is needed. Recording here for the reconciler.

### m1 — tsgo vs tsc switchover lacks a recorded criterion

**Severity:** minor.

**What is wrong:** §D4 says classic 5.x first; if it mis-handles a construct, switching to tsgo is "a deliberate W3 gate decision, recorded then." But W3's gate is type acceptance of `01-basics.agentscript` — the smallest fixture. A more demanding fixture (e.g. 23-numeric with `bigint`) would be the right gate, but is not part of W3. The plan defers the tsgo decision to a per-construct judgment call.

**Evidence:**
- `backend/check_corpus.py:96-112` (W6 gate template): does not specify which tsc binary.

**What would make it right:** Either commit to classic tsc with `--target es2020` for the whole corpus, or define a specific W3 widening that exercises `bigint` arithmetic before declaring the toolchain.

### m2 — Plan does not assert which name appears in the differential summary for five-arm verification

**Severity:** minor.

**What is wrong:** The plan §W7 says the "summary string gain the arm" but does not say what string. The current summary is `f"\n{bad} disagreement(s) across {cases} function cases + {program_total} program cases (python/rust/wasm/interp)"` (`differential.py:507`). The plan does not commit to a literal string assertion like `'python/rust/wasm/interp/ts'` must appear, only to a code-path assertion that `'build_typescript' in s`. A future summary rewrite could omit `ts` from the string and the gate would not catch it.

**Evidence:**
- `backend/differential.py:507`: summary string; not asserted by any plan gate.
- `PLAN.md:269` W7 gate is `assert 'build_typescript' in s`.

**What would make it right:** Add to W7's gate an assertion that the summary string contains `'ts'` as an arm name.

---

## "Conformant-but-wrong" enumeration

The plan's central question. For each of the five numbered work-item categories, what wrong implementation passes?

| # | Work item | Conformant-but-wrong that passes today | Caught by gate? |
|---|---|---|---|
| W1 | TS templates on every builtin | A template that formats but emits wrong code (e.g. `RT.add({0},{1})` when `RT.add` doesn't exist in `rt.ts`) — caught by tsc on every fixture that exercises it. | Partial — only on the subset of fixtures whose transpile succeeds AND exercise the broken builtin. |
| W3 | Transpiler + rt.ts | A transpiler that emits `// no-op` for every form — `tsc` accepts it. | NOT caught — tsc accepts empty TS. |
| W4 | Module linking | A `link()` that emits a single root-only file and discards imports — `tsc` accepts it; program-mode tests for `13-module-program.agentscript` would fail because the program imports a union. | Partial — caught only by fixtures that exercise imports. |
| W5 | IoError mapping | A `codeToIoError` that maps every `error.code` to `not-found` — passes the 08-io failing write (the only W5 gate). | NOT caught — only 2/6 IoError cases are exercised in failing-path program cases. |
| W6 | tsc column in check_corpus | A transpile that returns an empty string for an unhandled form, so tsc sees nothing. | NOT caught — check_corpus's tsc step runs only when transpile succeeds (B1). |
| W7 | Five-arm differential | A `build_typescript` that execs the python arm's output and forwards it — agrees trivially; passes string-presence gate. | NOT caught — no per-arm execution counter (B2). |

---

## Verified

- `backend/differential.py:407-410`: agree expression is across the four named runners; adding `ts` requires editing this line. The plan's W7 acknowledges this but provides no counter-assertion that the arm actually runs distinct code.
- `backend/check_corpus.py:96-112`: rustc compile step currently used as the tsc-column template; preserves the existing "transpile fail → tsc skipped" shape. The plan does not propose to break this.
- `prelude/generate.py:165,170-186`: validator scans `("py", "js", "rs")`; the change adds `"ts"` — the new tuple is `("py", "js", "ts", "rs")`. Verbatim by reading.
- `prelude/prelude.json:5,16-23`: live version 0.2, constructors list includes IoError cases. Stash version 0.3, no IoError union. Cross-version template recovery carries assumptions.
- `prelude/coverage.lock`: floor 95%, executed 107, `unproven` lists the four unreachable IoError host mappings. Plan does not propose new failing-path cases.
- `backend/exec_coverage.py:31-32`: tracer is Python-only; adding TS arm is invisible to it.
- `backend/cases/23-numeric-int.json`: function-mode task entry-point and source — confirms 23-numeric is the differential function-mode source containing `import` (plan §D1's evidence claim, true).
- `backend/runtime.py:279-281`: `_ERRNO` mapping is the dual of the planned `codeToIoError`; the same six cases.
- `node_modules/.bin/`: contains `tree-sitter` only, no `tsc`. Confirms plan W2's claim.

## Unverified

- Whether the recovered `ts` templates match the live rt.ts signature surface (D2 names the signature change but does not enumerate affected builtins — likely 9 I/O helpers + 6 IoError ctors + file-append).
- The `defun ! main` form: the plan says live programs declare `(defun ! main ...)` and the emitter writes the host entry, but the docstring on `to_python.py:181-183` was not opened to verify the effect marker — the plan claims `to_python.py:181-183` is the counterpart and the recovery of the TS host entry has to mirror it.
- Whether the function-mode TS driver (`run_typescript`) can faithfully serialize `bigint` returns as JSON-compatible ints — Python's `json.loads` reads `Int32`/`Int64` as `int` only if the TS side emits bare digits. The plan §D5 claims this is feasible; not verified against an emitted fixture.
- Whether fixtures 18, 27, 29 have any fork-specific lowering risk (only 16, 17, 26, 28 explicitly enumerated in plan §5 as high-risk).
- `backend/cases/` list: 28 files, none specifically tagged "function-mode TS driver gate" — the function-mode arm has no new entry in the cases dir per the plan.

---

## Risks (carry-forward to the implementation phase)

- **Fork→live template drift on bigint.** Stash `js` and live `js` are *the same keys* (same name, same template) per `prelude.json:90` etc. — so the 100 templates being recovered are not from a different language. They are from a different prelude version. The version mismatch is the dominant risk for W1, not the surface syntax mismatch.
- **Six-case IoError agreement.** Two cases pinned by failing-path program; four cases exposed only via `--labels` stdout (a happy path). The differential gate does not compare those four in stderr. A `--labels` happy path diverging on the case ordering would still pass.
- **Five-arm enforcement.** No per-arm execution counter exists. A TS arm that execs python output passes agreement trivially.
- **Module linking on transitive imports.** Plan §W4 names fixtures 06, 09-13, 15 as the linked set; fixtures 06, 09-11, 13 transitively import from `grammar/corpus/modules/`. The plan ports `to_python.py:111-121` but does not assert the transitive closure (a `(import a :as x) (import b :as y) (x/f ...)` shape) — fixture 15 shadows a binder from an imported module; the lowering's correctness depends on per-module emission, which the plan ports but does not gate by a specific transitive fixture.

## Highest-value finding

**The differential's five-arm agreement is provable by a TS arm that simply execs the Python arm's output and forwards it — there is no per-arm execution counter and no asserted summary string that names five distinct transpilers (B2).**
