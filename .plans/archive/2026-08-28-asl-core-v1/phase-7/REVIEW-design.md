# Phase 7 plan review — design & feasibility lens

Reviewer: steps-architect-pro (critic, plan-review wave).
Target: `.plans/phase-7/PLAN.md`. Every citation below was read by the reviewer in this session;
stash artifacts were extracted to `/tmp/stash-to_typescript.py` and `/tmp/stash-rt.ts` via the
plan's own recovery commands before being read.

## Verdict

**approve-with-amendments** — 1 blocker, 3 major, 2 minor. The blocker is in D4's fixed gate
flags, not in the architecture; all five decisions survive with the amendments below. No
decision needs reversing.

---

## Findings

### B1 — BLOCKER: the fixed `tsc` flag set cannot type-check `rt.ts` from the build dirs the gates use

D4 freezes the gate flags as `--noEmit --strict --target es2020 --module commonjs` "across
every use" (PLAN.md §1 D4). The W3/W4/W5 gates build in `/tmp/p7-*` and W6/W7 build in
`tempfile.TemporaryDirectory()` (`backend/check_corpus.py:33-41`, `backend/differential.py:386-392`).
`tsc` resolves `@types/*` by walking up from the directory containing the input file toward
`tsc`'s own location; a build dir under `/tmp` (or `/var/folders/...` on macOS) has no path to
the repo's `node_modules`.

Empirical (reviewer ran this session; scratch under `/tmp/tsctx`):

- `tsc --noEmit --strict --target es2020 --module commonjs a.ts` with cwd and file both under
  `/tmp`, `rt.ts`-style content (`import * as fs from "node:fs"; ... process.argv ...`):
  ```
  a.ts(1,21): error TS2307: Cannot find module 'node:fs' or its corresponding type declarations.
  a.ts(4,13): error TS2580: Cannot find name 'process'. Do you need to install type definitions for node? ...
  ```
  exit 2. This is exactly `backend/ts/rt.ts:546-547` (`import * as fs from "node:fs"`,
  `import * as childProcess from "node:child_process"`) plus `process.argv` at rt.ts:637.
- Same invocation with `--typeRoots <repo>/node_modules/@types --types node`: **exit 0**.

Consequence: as written, every W3–W7 gate fails on type-resolution infrastructure, not on the
code under test, and the recorded "current output" of those gates would be replaced by a
different infrastructure failure after W2. The flags must be amended in D4 before execution:
add `--typeRoots <repo-root>/node_modules/@types --types node` to the frozen set (verified
green). Building under the repo root instead of `/tmp` is the alternative; it puts generated
artifacts in the tree and needs its own cleanup rule — the `--typeRoots` fix is lazier.

### M1 — MAJOR: two gate commands, as written, do not produce their recorded failures

- W3 gate (PLAN.md §3 W3) redirects to `/tmp/p7-basics/main.ts` **before** `mkdir -p
  /tmp/p7-basics`; the plan's own parenthetical admits the literal text is out of order. The
  recorded current output (`can't open file .../backend/to_typescript.py`, verified by reviewer:
  exit 2) is what the *first* invocation produces, but the command sequence fails earlier on the
  redirection. The gate must be re-ordered `mkdir && cp` first, exactly as the parenthetical says.
- W5 gate (PLAN.md §3 W5) runs `mkdir -p /tmp/p7-io && cd /tmp/p7-io && .venv/bin/python
  backend/to_typescript.py ...` — after `cd /tmp/p7-io` the relative interpreter and source paths
  no longer exist. Either keep cwd at the repo root (build dir passed as redirect target) or use
  absolute paths after the `cd`.

Both gates fail now, but not verbatim as recorded; the protocol requires the recorded failure to
be the gate's actual failure. Fix is text-only, no reordering of work items.

### M2 — MAJOR: D2's errno table misses `ENOTDIR`/`EISDIR`, breaking dual faithfulness on `invalid-path`

The plan's proposed Node mapping sends `EINVAL`/`ENAMETOOLONG` → `invalid-path` but omits
`ENOTDIR` and `EISDIR`. Both sibling mappings cover that condition class:

- Python: errno 20 (ENOTDIR) and 21 (EISDIR) → `invalid-path` (`backend/runtime.py:269-270`).
- Rust: `NotADirectory | IsADirectory` → `InvalidPath` (`backend/rust/rt.rs:266-268`).

Node surfaces `EISDIR` when writing a path that is a directory and `ENOTDIR` for a path whose
parent component is a file — the same syscalls Python/Rust see. With the table as recorded, the
TS arm would report `other` where the other three arms report `invalid-path` on exactly the
condition the `invalid-path` case exists for. No declared differential case reaches it today
(program-mode cases at `backend/differential.py:418-421, 436-439` declare only `not-found` and
`permission-denied`), so this is not a blocker — but D2's whole purpose is faithful duality, and
the fix is two table entries: `ENOTDIR`/`EISDIR` → `invalid-path`. `EINVAL` should stay
(defensive), `ENAMETOOLONG` has no Python/Rust dual in the current tables — harmless to keep but
note the asymmetry in the commit.

### M3 — MAJOR: unrecorded port obligation — prelude union cases must be seeded into the fork's `match` machinery

The live Python backend seeds prelude unions into its pattern table so a case of `IoError` is
lowered by exactly the path a user `defenum` case takes (`backend/to_python.py:57-60`, source
`prelude/vocab.py:41-44` → `{'IoError': ['not-found', ...]}`). The fork's transpiler has no
seeding at all (grep of `/tmp/stash-to_typescript.py` for `unions|IoError`: none); its `arm()`
only hardcodes `ok/err/some/none/list/cons/pair` and falls through to `head in self.enums`,
which holds user-`defenum` cases only.

Consequence for the recovered code: a pattern like `(err (not-found))`
(`grammar/corpus/valid/08-io.agentscript:14`, `18-pattern-binders.agentscript:12`) drops its
sub-test silently — `_leaf()` returns `None` for an unseeded enum pattern, and the arm matches
**any** `err`. Those two fixtures happen to have only the not-found err path, so they would pass
while wrong: precisely the "asserting the code matters more than asserting rejection" failure
class AGENTS.md documents, and exactly the defect shape the differential was built to catch
(AGENTS.md, `differential.py` docstring: agreement alone cannot see a defect the arms share).
The W3 inventory ("recovered verbatim, then: [drop boundary, re-point parser, replace entry]")
must gain a fourth rework: seed `vocab.unions()` cases into the fork's `self.enums` (or its
equivalent) so IoError patterns test their tag. `19-io-errors` escapes today only because
`label` uses `cond` + equality, not `match` (`grammar/corpus/valid/19-io-errors.agentscript:11-19`).

### m1 — MINOR: D1's function-mode evidence is factually wrong (the decision itself still stands)

The plan claims "function-mode task `23-numeric.agentscript` imports modules (verified: it is
the one function-task source containing `import`)". False: the only `import` token in the file is
`__import__` inside its `; run:` comment (`grammar/corpus/valid/23-numeric.agentscript:12`); its
module header (`:14-17`) has no `:import` clause. Reviewer grepped every function-task source
(fixtures 16–29 plus `bench/algo/variants/tight.agentscript`): zero `:import` clauses. Also
"six of which use modules (06, 09-13, 15)" — that parenthetical lists seven fixtures
(06,09,10,11,12,13,15), each verified to contain `:import`/`(import`.

D1 remains correct on the remaining grounds: `check_corpus.py` globs all valid fixtures
(`backend/check_corpus.py:25-27`) and program-mode differential cases 13/15 need linking
(`backend/differential.py:451-463`). The no-import arm would still force a skip list into a gate
whose docstring forbids one (`backend/check_corpus.py:15-18`). Amend D1's stated evidence; keep
the decision.

### m2 — MINOR: D4's "@types/node 26.x vs node 22" risk understates that types must match the flags

Verified: live `package.json` has no `"type": "module"` (CommonJS is the default, so
`--module commonjs` output runs under node), node is v22.22.3, and `backend/ts/rt.ts` uses no
post-ES2020 library API (scan for `replaceAll`/`.at(`/`hasOwn`/`structuredClone`/`findLast`:
none), so `--target es2020` is sufficient for `bigint` and the emitted constructs. The residual
is only the resolution problem of B1. The fork's `^7.0.2` tsgo + `@types/node@^26.2.0`
(stash `package.json`, verified) is correctly rejected as the default. Record the verified-green
flag set in W2, not just the version pins.

---

## Verified claims (hold as stated)

- **Recovery commands are concrete and work.** `stash@{1}` exists ("as-lang TS backend");
  `stash@{1}^3` contains exactly `.venv`, `backend/to_typescript.py` (485 lines),
  `backend/ts/rt.ts` (664 lines). All three `git show 'stash@{1}^3:<path>'` extractions succeeded.
- **D3 counts are exact.** Live prelude: 107 builtins, keys `py/js/rs` (+`type/sec/doc/effect`),
  0 with `ts`. Fork prelude: 103 builtins, all with `ts`, 0 with `js`. Shared: 100. Live-only:
  exactly the 7 claimed (`not-found, permission-denied, already-exists, invalid-path,
  interrupted, other, file-append`). Fork-only orphans: exactly the 3 claimed (`args, env-get,
  process-run`). Fork prelude also uses `effects`/`sw` keys absent live — the name-matched
  recovery must copy only the `ts` value, which D3 already says.
- **`generate.py --check` is safe under the tuple change.** `validate_templates()` at
  `prelude/generate.py:155-176` iterates the tuple at `:165` (verified `("py", "js", "rs")`);
  adding `"ts"` demands a ts template on all 107 — exactly W1's gate, whose current output was
  reproduced verbatim (`AssertionError: 107 builtin(s) lack a ts lowering, first five: ['+', '-',
  '*', '/', 'mod']`). Generated docs render name/type/doc only, so `--check` (currently exit 0)
  is unaffected by template keys.
- **Coverage/closure gates are unaffected.** `backend/exec_coverage.py` instruments
  `to_python.LOWER` only (`:127-153`); `backend/monomorphism.py` compiles py+rs only
  (`:179-180`); `grammar/closure_audit.py` reads names via `vocab` (`:88-89`). W2's gate
  reproduces the recorded failure (`node_modules/.bin/tsc` absent, exit 1).
- **Dropping `backend/boundary.py` is sound.** It does not exist live (`ls backend/`); the live
  grammar has zero `defextern`/`defopaque` productions (grep of `grammar/agentscript.lark`: 0),
  so `check_target` has no input domain left. The fork's uses are confined to the import
  (`/tmp/stash-to_typescript.py:26`) and the `__main__` handler (`:480-485`); inlining
  `TargetMismatch`/`NotLowered` or deleting both is a judgment call, not a design risk.
- **Entry-shape rework is correctly scoped.** Live programs declare `(defun ! main [(args (List
  String))] -> (Result Unit IoError)` (`08-io.agentscript:22`, `19-io-errors.agentscript:48`) and
  the Python driver emits the exit glue at `backend/to_python.py:181-183`; the fork's
  `defentry`/`asMain` (`/tmp/stash-to_typescript.py:152-171`) predates that shape. Live
  `parse.py` exposes `FORM_KW`/`parser()` (`grammar/parse.py:20-33`) with a `BANG` terminal the
  fork's private `FORM_KW` lacks — the fork's keyword set must be replaced wholesale, not merged.
- **`RT.args()` works with the existing `cmd + argv` form** (rt.ts:636-638,
  `process.argv.slice(2)`), and `mainExit`'s contract (`runtime.py:340-357`: shape-checked,
  case name + `\n` to stderr, exit 1) is fully specified for the W5 port.
- **try-inside-fn refusal is currently safe.** All five `try`-bearing fixtures parsed: 0 have a
  `try` inside an `fn_form` (reviewer AST scan). The fork's `NotImplementedError` there
  (`/tmp/stash-to_typescript.py:337-338`) cannot fire on the current corpus.
- **Function-mode vocabulary is complete by construction.** Since the live-only set is exactly
  the 7 in W1's "new" list, every builtin used by fixtures 20–29 is among the 100 shared names
  carrying fork `ts` templates — so D5's "lower every function case" is achievable at the
  template level; residual risk is special-form/type mapping, which the fork implements for
  every form the current fixtures use.

## D5 assessment (the plan's "riskiest assumption")

No-skip is the right call, **conditional on B1/M1–M3**. Reasoning: a recorded skip re-opens the
exact hole `check_corpus.py:15-18` exists to prevent ("a `skipped` column still exits 0"); the
wasm arm's function-mode absence is a mode that does not exist for that arm, not a skip list, so
it is no precedent. A transpile failure on a fixture the fork never saw (16–29) fails loudly at
the right layer with a concrete fix target (a lowering in `to_typescript.py`), and
`backend/t` + the declared differential values provide independent expectations, so the gate is
not blind to shared defects the way a two-arm comparison would be. The risk is real (fork predates
fixtures 16–29; its Map/bigint/string-transform templates were never executed against them) but
the plan already carries it in §5 risk #2 with the correct containment (W6 surfaces it, fix is a
lowering, never a gate change). Keep D5.

---

## Risks (unverified, carried forward)

- **Grammar node-name drift between `as-lang.lark` (fork) and `agentscript.lark` (live)** beyond
  the recorded entry/keyword changes. Contained by W3's gate (01-basics must tsc-accept), but a
  drifted rule name would surface as a lark `KeyError`/missing-child, not a type error.
- **`readLine`/`readAll` error paths diverge by construction**: rt.ts:564-572 swallows a failing
  stdin read into `""` (never returns `err`), while `runtime.py:283-295` maps stdin `OSError`
  to an IoError. No declared case reaches a failing stdin, but a future one would disagree.
  Flag for W5: route the catch through `codeToIoError`, do not swallow.
- **`permission-denied` observability on this machine** (plan §5 risk #3) — pre-existing for all
  arms; nothing to add.
- **tsgo fallback trigger** — plan §5 risk #4 is well-formed; B1's fix removes the most likely
  false trigger.

## Amendments required before execution

1. D4: add `--typeRoots <repo>/node_modules/@types --types node` to the frozen flag set (B1).
2. W3/W5 gate text: reorder `mkdir`/`cp` before redirection; remove the `cd` that breaks
   relative paths or use absolute paths (M1).
3. D2 table: add `ENOTDIR`/`EISDIR` → `invalid-path` (M2).
4. W3 inventory: add seeding of `vocab.unions()` cases into the recovered pattern matcher (M3).
5. D1: strike the 23-numeric import claim; rest on check_corpus fixtures 06/09/10/11/12/13/15
   and program cases 13/15 (m1).
