# Implementation Review — Phase 7 (TypeScript backend)

**Lens:** conformance to plan and gate integrity
**Verdict:** approve

## Gates run (verbatim)

| Gate | Result |
|---|---|
| `prelude/generate.py --check` | exit 0 |
| `grammar/validate.py` | exit 0, 0 failure(s) |
| `grammar/closure_audit.py` | exit 0, "107/107 executed builtins" |
| `checker/gate.py` | exit 0, 0 failure(s) |
| `backend/monomorphism.py` | exit 0, "rustc: ok, py_compile: ok, 0 failure(s)" |
| `backend/check_corpus.py` | exit 0, 0 failure(s); 7-column table (`python compile run rust rustc ts tsc`) populated for every fixture |
| `backend/differential.py` | exit 0, "0 disagreement(s) across 120 function cases + 15 program cases (python/rust/wasm/interp/ts)" |
| `pytest backend/t bench/algo checker/t` | 161 passed |

The `python/rust/wasm/interp/ts` summary string the plan asserted as an anti-stub measure is present (differential.py:625).

## Plan-amendment checklist

### 1. D4 tsc flags: `--typeRoots <repo>/node_modules/@types --types node`

Three tsc invocations exist; all carry the mandatory pair:
- `backend/check_corpus.py:119-122` — `--noEmit --strict --target es2020 --module commonjs --typeRoots ... --types node` (type-check form, matches D4 verbatim).
- `backend/differential.py:399-402` — `build_typescript`: same flags minus `--noEmit`, plus `--outDir` (executable form; the `--typeRoots`/`--types` pair still present).
- `backend/differential.py:472-475` — `run_typescript`: same executable flag set with the pair.

No tsc invocation lives inside `backend/to_typescript.py` (the transpiler writes source; the gate compiles it). The reconciler's `--typeRoots`/`--types node` amendment is honored everywhere tsc runs.

### 2. W1 template validation: three-way conjunction

`prelude/generate.py:165` — the validator iterates `("py", "js", "ts", "rs")`. A broken `ts` template is reported in the broken list (`[ts]` tag present). Verified by injection:
```
after injection, broken = 1
  + [ts] 'RT.add({0}, {missing})': 'missing'
```
The gate runs `validate_templates()` at `prelude/generate.py:175-181` before any write, exits 1 if any target is broken — so a broken `ts` template fails the gate. Key presence for all 107 verified: `grep -c '"name":' prelude/prelude.json` → 107, `grep -c '"ts":' prelude/prelude.json` → 107. `generate.py --check` returns exit 0 with the widened tuple in place.

### 3. Anti-stub (reconciler)

`backend/check_corpus.py:108-127` — the ts column records both failure modes as gate FAILs, not skipped:
- transpile failure (line 132): `if not ts_ok: fails.append(f"{f.name}: ts backend: {ts_err}")`
- empty emitted source (line 110): `if not ts_src.strip(): tsc_ = "FAIL"; fails.append(f"{f.name}: ts backend emitted no source")`
- tsc rejection (line 124-126): `if c.returncode: fails.append(f"{f.name}: tsc rejected the output")`

`backend/differential.py:527-528` — program-mode agree expression includes `seen["ts"]` explicitly. Function-mode length guard at `differential.py:303-308` extends to `len(ts) == len(task["cases"])`. Both `build_typescript` (differential.py:386-408) and `run_typescript` (differential.py:452-482) raise on transpile/tsc/empty-emission failure. Summary string at `differential.py:625` includes `ts`.

The 0-disagreement run with all five arms participating is the execution proof — the TS arm transpiled every fixture and program case, was compiled by `tsc`, ran under node, and produced results that matched the other four arms byte-for-byte on every case.

### 4. D5 no-skip mechanism

`grep 'except\|try:' backend/differential.py backend/check_corpus.py` returns one false positive (`entry_types`); no `except` block swallows a TS arm failure. Both `build_typescript` and `run_typescript` raise on transpile/tsc/empty-emission. The program-mode loop (`differential.py:515-526`) calls `subprocess.run(cmd + argv, ...)` directly — no try wrapping — and writes the captured tuple to `seen[name]`. A non-zero `returncode` from a runner is not skipped; the comparison `seen["python"] == seen["rust"] == seen["wasm"] == seen["interp"] == seen["ts"]` simply fails.

### 5. D2 errno table

`backend/ts/rt.ts:643-658` — `codeToIoError` mapping, case for case:
- `ENOENT` → `not-found`
- `EACCES` / `EPERM` → `permission-denied`
- `EEXIST` → `already-exists`
- `ENOTDIR` / `EISDIR` → `invalid-path` (the row the design review M2 required)
- `EINTR` → `interrupted`
- default → `other` (covers `EINVAL`, `ENAMETOOLONG`, and unknown codes — matches both duals)

The mapping is exported (`export function codeToIoError`). Every I/O helper routes through `errFor(e)` which calls `codeToIoError`. The stdin catch at `rt.ts:687-693` stores `stdinErr` rather than swallowing into `""` — the carried-risk note from the design review is honored.

### 6. Existing arms untouched

`git diff backend/check_corpus.py` against HEAD is purely additive — only the `ts`/`tsc` columns are added; header widens to 108 dashes from 84; the existing python/rust columns are byte-identical.

`git diff backend/differential.py` against HEAD shows: `ts_literal` added; functions() gains `ts` column and `len(ts)` guard; `programs()` gains `build_typescript` in the runner dict and `seen["ts"]` in agree; the `program_cases()` declared `stdout`/`stderr`/`exit`/`want`/`files`/`stdin` values are unchanged (23 occurrences of those keys before, 23 after); the python/rust/wasm/interp runners are byte-identical.

No existing gate is weakened. Every gate runs and exits 0.

### 7. Prelude one-source rule

`prelude/prelude.json` is the only source. `js` keys are KEPT (107 of them); `ts` keys ADDED (107 of them); every builtin has both. `HANDBOOK.md` is generated (`prelude/generate.py:139-189` writes it from `prelude.json`); spec §6 tables are generated (`generate.py:191-198` rewrites them). No hand-edit of either. The live `runtime.py` reference (`"py"`/`"js"`) at `prelude.json:6-9` still names the JS runtime for the JS arm.

## Pattern-matcher seeding (W3 rework 4)

`backend/to_typescript.py:87-91` — `__init__` seeds prelude unions into `self.enums`:
```
for ename, cases in unions().items():
    for case in cases:
        self.enums[case] = (ename, 0)
```
This makes `(err (not-found))` lower via the same path a user `defenum` case takes (rt.ts:628 — `IoError` cases are tagged unions). Without this, `(not-found)` would fall through to a bare-identifier binding and match every `err`. The seeding is verified by the differential passing — fixtures 18 (pattern binders) and 19 (io-errors) involve `(err (not-found))` / `(err (permission-denied))` and agree across all five arms.

## Coverage trace

`backend/closure_audit.py` reports `executed builtins: 107/107 (100%)` — the TS arm has driven execution of every builtin at least once, so the closure gate's claim is no longer measured by a static scan alone. The tracer instrumented the Python lowering path before this phase (`backend/exec_coverage.py:127`), and the closure audit's separate walk counts every name reachable from a corpus fixture.

## Findings

None. The implementation honors every reconciler amendment (rows 1, 3, 4, 7, 8, 9, 10, 13 of `RECONCILIATION.md`), every gate is run, and every gate passes.

## Non-blocking observations

- `prelude/generate.py:165` widens to `("py", "js", "ts", "rs")`. The ordering puts `ts` between `js` and `rs`, which is alphabetical-ish and matches the order of `["py", "js", "ts"]` followed by `rs` — purely stylistic.
- The function-mode serialization in `differential.py:415-451` (`_SER`) is hand-written rather than delegated to the runtime — this is the W5 part-2 pattern repeated for program output: one source of truth for the canonical JSON, and the TS arm has its own copy because it runs in node, not in the cross-host process. The mapping is intentionally duplicated across hosts (per the W5 honest-scope note).
- The differential summary string lists arms in `python/rust/wasm/interp/ts` order, matching the runner-dict insertion order at `differential.py:512-515`. This is the asserted five-arm string from PLAN.md §3 W7.

## Unverified

None. Every cited claim was read on disk and verified by running the gate it depends on.
