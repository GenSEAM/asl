# Phase 7 — TypeScript backend

## §1 Scope and acceptance

Re-integrate the fork's TypeScript backend (stash `stash@{1}`, worktree
`worktree-agent-af55939e9461a0011`, untracked tree `f7abc02` against `b614ec8`) and wire it
into the gates. `.plans/PHASES.md:70-74`: *"a third arm on `differential.py` runs and agrees;
`tsc` accepts the emitted output."* The "third arm" wording predates the interp and wasm arms;
today differential has four arms in program mode (python/rust/wasm/interp,
`backend/differential.py:393`) and three in function mode (`backend/differential.py` `functions()`,
runners at `:195/:214/:240`). TS becomes a **fifth arm in program mode and a fourth in function
mode**, in both modes it fully participates — no skip mechanism, no partial columns.

Acceptance, each ending in a command:

1. **Every builtin has a `ts` lowering in `prelude/prelude.json`**, the widened
   `validate_templates()` reports no broken `ts` template, and
   `prelude/generate.py --check` stays green with `"ts"` in the validation tuple.
2. **`tsc --noEmit --strict` accepts the emitted output for every fixture `check_corpus.py`
   gates** (corpus valid + bench, `backend/check_corpus.py:20-23`), and a fixture whose TS
   transpile fails or emits nothing is a recorded gate failure, not a skipped column.
3. **The differential gate agrees on five arms** in program mode and four in function mode,
   against the unchanged declared `stdout`/`stderr`/`exit`/`want` values, exits 0, and its
   summary names all five arms.

### Decisions (recorded, each the laziest correct option)

**D1 — Module linking: scope IN.** Port the Python `link()`/`module_prefix` semantics
(`backend/to_python.py:111-121`, helpers `grammar/modules.py` `closure`/`imports`/
`declared_path`, prefix rule `to_python.py:47-51`) into the TS transpiler. The restricted
no-import arm loses, on these grounds: `check_corpus.py` globs every valid fixture
(`backend/check_corpus.py:25-27`) and **seven** of them use modules — 06, 09, 10, 11, 12, 13, 15,
each verified to carry an `:import`/`(import` form — so a no-import arm forces a skip list into
a gate whose docstring forbids one; and program-mode differential cases 13/15 need linking
(`backend/differential.py:451-463`). No function-mode task imports today (verified across
fixtures 16-29 and `bench/algo/variants/tight.agentscript`: zero `:import` clauses), so the
function-mode need is currently vacuous — but the no-skip principle means W7's function mode
must not crash the first time a task does import, so W4 lands before W7 unconditionally. The
port is bounded — the fork's `mangle` already flattens `alias/member` (`backend/to_typescript.py`
stash, `mangle`), what is missing is per-module emission with the defining-path prefix and the
alias→prefix map (`to_python.py:123-131`).

**D2 — Error model: adapt to the closed `IoError` union; agreement, not divergence.** The
differential program mode compares stderr and exit status unconditionally
(`backend/differential.py:379-408`), so a documented divergence is just a permanent disagreement.
The fork's `rt.ts` carries `ASResult<T,string>` / `RT.fail(message: string)`; the live
contract is the six-case union (`backend/runtime.py:274-275`, mirrored by `rt::IoError`,
`backend/rust/rt.rs:256-272`): `not-found, permission-denied, already-exists, invalid-path,
interrupted, other`. Node maps `error.code`, the dual of Python's `_ERRNO`
(`backend/runtime.py:269-281`) and Rust's `ErrorKind` (`rt.rs:256-272`). The dual-faithful
table, case by condition class:

| Node `error.code` | IoError case | Duals |
|---|---|---|
| `ENOENT` | `not-found` | errno 2 / `NotFound` |
| `EACCES`, `EPERM` | `permission-denied` | errno 13 / `PermissionDenied` |
| `EEXIST` | `already-exists` | errno 17 / `AlreadyExists` |
| `ENOTDIR`, `EISDIR` | `invalid-path` | errno 20/21 / `NotADirectory \| IsADirectory` (`rt.rs:266-268`) |
| `EINTR` | `interrupted` | errno 4 / `Interrupted` |
| everything else, incl. `EINVAL`, `ENAMETOOLONG` | `other` | default arm on both duals |

`EINVAL` and `ENAMETOOLONG` map to `other`, **not** `invalid-path`: Python's `_ERRNO` has no 22
or 63 key and falls through to `"other"` (`runtime.py:269-273`), and Rust's match arm is
`_ => IoError::Other` — a TS mapping that sent them to `invalid-path` would be the divergence
D2 exists to prevent. The mapping lands in `rt.ts` and only the differential proves the arms
agree.

**D3 — Prelude templates: keep the live `js` keys, add `ts` alongside.** Verified against the
stash: live prelude has 107 builtins keyed `py/js/rs`; the fork's has 103 keyed `py/ts/rs`.
100 names are shared and carry a recoverable `"ts"` template; 7 are live-only
(`not-found`, `permission-denied`, `already-exists`, `invalid-path`, `interrupted`, `other`,
`file-append`) and get new templates; 3 fork templates are orphans with no live builtin
(`args`, `env-get`, `process-run`) and are dropped. Renaming live `js`→`ts` (what the fork did)
would orphan the JavaScript story for no gain. `prelude/generate.py:165` tuple
`("py", "js", "rs")` → `("py", "js", "ts", "rs")`. Fork `ts` templates that no longer format at
their live arity are a W1 gate failure, not a silent port. The fork prelude is version `0.3`
against live `0.2` (`prelude.json:5` both sides) — name-matched recovery copies only the `ts`
value, and the residual signature/type assumptions are carried in §5.

**D4 — `tsc` from npm, classic 5.x first.** Verified: `node_modules/.bin/` holds only
`tree-sitter`; no `tsc` exists. Install `typescript` (classic compiler, exact version pinned at
install; start at `^5.9`) and `@types/node` as devDependencies. The fork's `^7.0.2` is the
native tsgo compiler and is unverified against the emitted constructs; classic tsc with
`--target es2020` natively handles `bigint` under node 22 (verified: `rt.ts` uses no
post-ES2020 library API — no `replaceAll`/`.at(`/`hasOwn`/`structuredClone`/`findLast`; live
`package.json` has no `"type": "module"`, so CommonJS output runs under node). If classic tsc
mis-handles an emitted construct, switching to tsgo is a deliberate gate decision, recorded then
(see W6 — the corpus-wide compile is the decision point, not W3's minimal fixture). Gate flags
fixed across every use:

```
--noEmit --strict --target es2020 --module commonjs \
  --typeRoots <repo-root>/node_modules/@types --types node
```

The `--typeRoots`/`--types` pair is not optional decoration: W3-W5 build under `/tmp/p7-*` and
W6/W7 under `tempfile.TemporaryDirectory()`, and `tsc` resolves `@types/*` by walking up from
the input file's directory — a `/tmp` build dir has no path to the repo's `node_modules`.
Without the pair, every gate dies on `TS2307: Cannot find module 'node:fs'` /
`TS2580: Cannot find name 'process'` (exit 2) — infrastructure failure, not the code under
test (`rt.ts:546-547` imports `node:fs` and `node:child_process`; `process.argv` at `:637`).
With the pair, the identical invocation exits 0 (verified this session). The flags emit once,
for execution, with `--outDir` in the differential builder only; W2 records the verified-green
set alongside the version pins.

**D5 — Differential arm: both modes, no skip mechanism.** `build_typescript(src, d)` transpiles,
copies `rt.ts`, emits with `tsc --outDir`, returns `["node", <d>/dist/main.js]` — `RT.args()`
reads `process.argv.slice(2)`, so the existing `cmd + argv` per-case form works unchanged.
`build_typescript` raises on a transpile or `tsc` failure **and on an empty emitted source** —
a transpiler that swallows a form and writes nothing cannot enter the arm. Function mode: a
driver like the Rust `J` harness, serializing each return to the canonical JSON (`bigint`
printed as bare digits so Python's `json.loads` reads Int32/Int64 as ints; `NaN/±Infinity` as
`"nan"/"inf"/"-inf"` to match `NORMALISE`, `backend/differential.py:158-173`). Tables
(`functions()` `:279ff`, `programs()` `:366ff`), the agree expressions, and the summary string
gain the arm. A TS transpile or `tsc` failure inside the gate is a raised error — the gate
fails, nothing is skipped.

**Anti-stub measures (what stops a wired-but-fake TS arm).** A `build_typescript` that forwarded
the python arm's output, or emitted a stub, would otherwise "agree" trivially
(`differential.py:407` compares observed outputs, not provenance). Three measures, together:

1. **The independent `tsc` gate runs over every fixture's emitted TS** (W6): each fixture's
   transpile output must be non-empty, must compile under `--strict`, and a transpile failure
   is a recorded `fails` entry — there is no output a forwarding arm could borrow, because the
   emitted TS per fixture is compiled on its own before anything executes.
2. **Per-arm visibility in the gate output**: the differential summary string must name all
   five arms — `(python/rust/wasm/interp/ts)` — and W7's gate greps for it; a summary
   rewritten to drop `ts` fails the gate.
3. **Per-case execution proof by declared bytes**: the program-mode declared stderr
   (`not-found`, `permission-denied`) is derived independently per arm from the host error
   surface; the differential's byte-for-byte comparison plus W5's direct six-case mapping check
   (below) pins that the TS arm runs its own runtime.

### Decisions on scope boundaries

No new floor is added for `exec_coverage.py` (see §4 item 9); `monomorphism.py` stays py+rs
(adding a ts arm there is a separate, unclaimed decision).

## §2 Inventory

**Recovered (from stash, unchanged where possible):**
- `backend/to_typescript.py` — `git show 'stash@{1}^3:backend/to_typescript.py'` (485 lines);
  stale: `from boundary import ...` (no `backend/boundary.py` in the live tree), its own
  `Lark(grammar/as-lang.lark)` (live grammar is `grammar/agentscript.lark`; the live drivers
  use `grammar/parse.py` — `FORM_KW` at `parse.py:20`, `parser()` at `:28`), `defentry`/`asMain`
  entry (`:152-171`; live has no `defentry` — programs declare `(defun ! main ...)` and the
  Python driver emits `main_exit(main(_sys.argv[1:]))` at `to_python.py:181-183`),
  `LOWER = b["ts"]` (fine once W1 lands).
- `backend/ts/rt.ts` — `git show 'stash@{1}^3:backend/ts/rt.ts'` (664 lines); stale: string
  error model (D2), no `mainExit`; `readLine`/`readAll` swallow a failing stdin read into `""`
  (`rt.ts:564-572`) where the live hosts map stdin `OSError` to an `IoError`
  (`backend/runtime.py:283-295`) — W5 routes the stdin catch through `codeToIoError` instead of
  swallowing.
- 100 `"ts"` templates — `git show 'stash@{1}:prelude/prelude.json'`, matched by builtin name.

**New:** 7 prelude `"ts"` templates (the six `IoError` constructors + `file-append`); the
function-mode TS serialization driver; the errno/`error.code` → `IoError` case mapping in
`rt.ts` (D2's table, exported so W5's gate can call it directly).

**Modified:** `prelude/prelude.json`, `prelude/generate.py:165`, `package.json` (devDeps),
`backend/check_corpus.py` (new `ts`/`tsc` column mirroring the rustc column `:96-112`),
`backend/differential.py` (arm in both modes, tables, summary).

**Unchanged, verified safe to leave alone:** `backend/exec_coverage.py` instruments
`to_python.LOWER` only (`:127`, `:140-153`; execution recorded on the Python side only,
`:31-32`); `backend/monomorphism.py` compiles py+rs; `checker/gate.py`,
`grammar/closure_audit.py`, `grammar/validate.py` read names, not template keys. No existing
gate is weakened; all declared differential values stand.

## §3 Work items

### W1 — Prelude `"ts"` templates and the generator tuple

**What changes:** `prelude/prelude.json` gains `"ts"` on all 107 builtins (100 recovered by
name from `git show 'stash@{1}:prelude/prelude.json'`, 7 written new: the six `IoError`
constructors lower to tagged values, e.g. `not-found` → the runtime's `not-found` case
constructor; `file-append` → an `RT.fileAppend` call). The 3 fork orphans are not added.
`prelude/generate.py:165`: `("py", "js", "rs")` → `("py", "js", "ts", "rs")` — **this widening
is part of W1's edit, before the gate runs**, so the validator actually covers the new targets.
Recovered templates that fail `validate_templates()` at their live arity are fixed in
prelude.json, not weakened out of the validator.

**Why:** acceptance 1; the transpiler reads `LOWER = {b["name"]: b["ts"] ...}` and cannot start
without them. The vocabulary stays one-source: templates live only in prelude.json.

**Gate (fails now):** key presence, then the widened validator over the live arity of every
builtin, then the generator check:
```
.venv/bin/python -c "
import json
bs=json.load(open('prelude/prelude.json'))['builtins']
missing=[b['name'] for b in bs if 'ts' not in b]
assert not missing, f'{len(missing)} builtin(s) lack a ts lowering, first five: {missing[:5]}'
" && .venv/bin/python -c "
import sys; sys.path.insert(0, 'prelude')
from generate import validate_templates
bad = [x for x in validate_templates() if '[ts]' in x or 'no ts' in x]
assert not bad, f'{len(bad)} broken ts template(s), first: {bad[:3]}'
" && .venv/bin/python prelude/generate.py --check
```
Current verbatim output of the first assert:
```
AssertionError: 107 builtin(s) lack a ts lowering, first five: ['+', '-', '*', '/', 'mod']
```
(The validator half fails today differently: with the tuple un-widened it finds no `ts`
complaints, which is exactly why key presence alone — the v1 gate — could pass with 107
templates that never got format-checked. The conjunction closes that.)

**Order justification:** every later item's transpile crashes on `KeyError: 'ts'` without it;
W2–W7 all depend on this file existing in its new shape.

### W2 — TS toolchain in devDependencies

**What changes:** `package.json` devDeps gain `typescript` (classic, pinned; D4) and
`@types/node`; `npm install` records them in `package-lock.json`. No source changes. W2 also
records the verified-green invocation — version pins plus the exact gate flag set from D4
(including `--typeRoots`/`--types node`) — so W3's first `tsc` run exercises a known-good
command, not a first guess.

**Why:** the accept oracle of the whole phase. Every later gate invokes
`node_modules/.bin/tsc`.

**Gate (fails now):** `test -x node_modules/.bin/tsc && node_modules/.bin/tsc --version`
Current output: silent, exit 1 (`tsc` does not exist; verified `ls node_modules/.bin/` →
`tree-sitter` only).

**Order justification:** W3's gate is the first `tsc` invocation; installing after it would
make W3 unfalsifiable.

### W3 — Recover and re-point the transpiler and runtime to the live tree

**What changes:** `backend/to_typescript.py` and `backend/ts/rt.ts` recovered verbatim, then
four reworks:
1. drop the `boundary` import (and `TargetMismatch`/`NotLowered`/`check_target` uses — the live
   tree has no `backend/boundary.py`);
2. parse via `grammar/parse.py` (`FORM_KW`, `parser()`), not a private `Lark(grammar/as-lang.lark)`
   — the live keyword set replaces the fork's wholesale, not merged;
3. replace the `defentry`/`asMain` host entry (stash `:152-171`) with the live driver shape — a
   `defun` named `main` returns `(Result Unit IoError)`, and the emitted tail becomes the TS
   counterpart of `to_python.py:181-183`: `RT.mainExit(main(process.argv.slice(2)))` under a
   main-module guard;
4. **seed the prelude union cases into the pattern matcher**: the live Python transpiler seeds
   `vocab.unions()` cases into its pattern table so a case of `IoError` lowers by exactly the
   path a user `defenum` case takes (`backend/to_python.py:57-60`); the fork's matcher has no
   seeding — its `arm()` hardcodes `ok/err/some/...` and falls through to user-`defenum` cases
   only (stash `:401-416`). Without the seeding, `(err (not-found))`
   (`grammar/corpus/valid/08-io.agentscript:14`, `18-pattern-binders.agentscript:12`) silently
   drops its tag test and matches every `err` — a defect the fixtures would pass with.
   Port the seeding (source: `prelude/vocab.py:41-44`).

`rt.ts` keeps its option/result/term machinery; the error-type rework is W5, so at this item
`mainExit` may exist only as the calling convention (full IoError semantics gated in W5) — W3's
gate is type acceptance, not error agreement.

**Why:** the fork artifacts cannot start against the live tree (missing `boundary`, missing
grammar file, entry form removed from the language). This item makes one no-import fixture
transpile and typecheck end to end, which is the smallest unit every later item builds on.

**Gate (fails now)** — run from the repo root; `mkdir`/`cp` precede any redirection; no `cd`
breaks the relative paths:
```
mkdir -p /tmp/p7-basics \
  && .venv/bin/python backend/to_typescript.py grammar/corpus/valid/01-basics.agentscript \
       > /tmp/p7-basics/main.ts \
  && cp backend/ts/rt.ts /tmp/p7-basics/rt.ts \
  && node_modules/.bin/tsc --noEmit --strict --target es2020 --module commonjs \
       --typeRoots "$PWD/node_modules/@types" --types node \
       /tmp/p7-basics/main.ts /tmp/p7-basics/rt.ts
```
Current verbatim output:
```
python: can't open file '/Users/purplelephant/projects/asex/backend/to_typescript.py': [Errno 2] No such file or directory
```

**Order justification:** needs W1 (templates) and W2 (`tsc`); W4–W6 are each a widening of the
surface this item proves on the minimal fixture.

### W4 — Module linking in the TS transpiler

**What changes:** `backend/to_typescript.py` gains the ported `link()`/`module_prefix()`
machinery (D1): dependency closure over the search roots, per-module emission under the
defining-path prefix, `alias_prefix` resolution for qualified names, prefix-collision check.
The fork's `NotImplementedError` on QUALIFIED names goes away.

**Why:** acceptance 2 — `check_corpus.py` globs all valid fixtures, and the seven module
fixtures (06, 09-13, 15) are unreachable without linking; program-mode differential cases 13/15
need it too (D1).

**Gate (fails now)** — same shape discipline as W3, plus a content assertion: the emitted
source must carry the defining-path prefix mangling (the `<seg>_<seg>__` form
`to_python.py:47-51` derives), so a `link()` that discards imports and emits a root-only file
fails here even if `tsc` would accept its output:
```
mkdir -p /tmp/p7-mod \
  && .venv/bin/python backend/to_typescript.py grammar/corpus/valid/13-module-program.agentscript \
       --root grammar/corpus/modules > /tmp/p7-mod/main.ts \
  && cp backend/ts/rt.ts /tmp/p7-mod/rt.ts \
  && grep -qE '[A-Za-z0-9]+_[A-Za-z0-9]+__' /tmp/p7-mod/main.ts \
  && node_modules/.bin/tsc --noEmit --strict --target es2020 --module commonjs \
       --typeRoots "$PWD/node_modules/@types" --types node \
       /tmp/p7-mod/main.ts /tmp/p7-mod/rt.ts
```
Current output: the transpiler raises before writing — the fork emits `NotImplementedError` on
qualified names (same failure class the digest reports; re-confirmed by the transpiler's
absence today, per W3's gate output).

**Order justification:** W3 must exist first (the file is recovered there); W5's error agreement
and W6's corpus-wide gate both run fixtures 08/19 and the module set — linking is what makes
"every fixture transpiles" an honest claim rather than a column of `-`.

### W5 — `IoError` in `rt.ts`: case mapping and `mainExit`

**What changes:** `backend/ts/rt.ts`: the error parameter of `ASResult` and every I/O helper
moves from `string` to the closed six-case union (D2); a `codeToIoError` mapping implementing
D2's table exactly (`ENOENT`→`not-found`, `EACCES`/`EPERM`→`permission-denied`,
`EEXIST`→`already-exists`, `ENOTDIR`/`EISDIR`→`invalid-path`, `EINTR`→`interrupted`, else
`other`) and **exported**; `mainExit(result)` returns 0 on `ok`, writes the case name + `\n` to
stderr and exits 1 on `err`, rejecting a non-Result/non-IoError payload the way
`runtime.py:340-357` does. All `fileRead`/`fileWrite`/`fileAppend`/stdin/stdout helpers route
through the mapping — including the stdin catch, which must produce an `IoError` rather than
swallowing into `""` (stash `rt.ts:564-572`; the live hosts map stdin failure to the union,
`runtime.py:283-295`).

**Why:** program mode compares `stderr` + `exit` byte-for-byte against declared values
(`differential.py:379-408`); the declared `not-found`/`permission-denied` stderr lines
(`:418-421`, `:436-439`) are exactly what this item produces and nothing else can.

**Honest scope note:** the differential pins only `not-found` and `permission-denied` by
failing-path bytes — no portable program case reaches `already-exists`, `invalid-path`,
`interrupted`, or the fallback (this is already recorded as `unproven` in
`prelude/coverage.lock:512-515`). This item does not pretend otherwise: it closes the gap at
the unit level, where the mapping itself is the unit under test.

**Gate (fails now)** — two parts. Part 1, the 08-io failing write end to end against the
declared bytes (repo-root cwd, no path-breaking `cd`):
```
mkdir -p /tmp/p7-io \
  && .venv/bin/python backend/to_typescript.py grammar/corpus/valid/08-io.agentscript \
       --root grammar/corpus/modules > /tmp/p7-io/main.ts \
  && cp backend/ts/rt.ts /tmp/p7-io/rt.ts \
  && node_modules/.bin/tsc --strict --target es2020 --module commonjs \
       --typeRoots "$PWD/node_modules/@types" --types node \
       /tmp/p7-io/main.ts /tmp/p7-io/rt.ts --outDir /tmp/p7-io/dist \
  && printf 'hello from a file\n' > /tmp/p7-io/sample.txt \
  && (cd /tmp/p7-io && node dist/main.js sample.txt nodir/out.txt > out.txt 2> err.txt; \
      test $? -eq 1) \
  && test ! -s /tmp/p7-io/out.txt && test "$(cat /tmp/p7-io/err.txt)" = "not-found"
```
Part 2, the mapping's six cases directly — a small TS harness importing the exported
`codeToIoError`, compiled with the D4 flags, run under node, asserting each case of D2's table
(`ENOENT`→`not-found`, `EACCES`→`permission-denied`, `EEXIST`→`already-exists`,
`ENOTDIR`→`invalid-path`, `EISDIR`→`invalid-path`, `EINTR`→`interrupted`, an unknown code →
`other`); it fails now because neither the file nor the export exists.

Current output: fails at the first `to_typescript.py` invocation exactly as W3's gate does
(file absent); once W3/W4 land it still fails because `rt.ts` models errors as strings and
emits no `not-found` stderr.

**Order justification:** needs W3 (files) and W4 (this fixture's transpile path); W6/W7's
program-mode value comes from this mapping, so the mapping must exist before the gates that
measure agreement across it.

### W6 — `check_corpus.py` gains the TS column

**What changes:** `backend/check_corpus.py`: for every fixture in `CORPUS`, a third transpile
column running `to_typescript.py` (`transpile("to_typescript.py", f)` alongside `:83-84`), and
for successful transpiles a `tsc` compile step mirroring the `rustc` step `:96-112` —
`rt.ts` + emitted `main.ts`, the D4 flag set, `FAIL` recorded into `fails` on rejection. Header
widened. No skip list (the module docstring already forbids one). Two fail-loud rules the rustc
column's shape already implies and this column makes explicit:

- a TS transpile failure appends to `fails` exactly as the python/rust columns do
  (`:104-108`) — a fixture the transpiler cannot lower fails the gate, it does not print `-`
  and pass;
- an emitted source that is empty (or contains no emitted program) is itself a `FAIL`
  (`"<name>: ts backend emitted no source"`) — a transpiler that swallows a form and writes
  nothing gets nothing past the tsc step and does not get a silent `ok` either.

**Why:** acceptance 2, and the AGENTS.md doctrine this file exists to enforce: parsing
proving well-formed is not the target accepting it. This is the "new tsc gate" of the
acceptance battery; the differential only runs the fixtures with declared cases, this runs
all of them — and it is the first anti-stub measure (a forwarding arm has no per-fixture TS
of its own to compile).

**Gate (fails now):**
```
.venv/bin/python -c "
import pathlib
s = pathlib.Path('backend/check_corpus.py').read_text()
assert 'to_typescript' in s, 'check_corpus.py has no ts column'
" && .venv/bin/python backend/check_corpus.py
```
Current verbatim output of the assert half:
```
AssertionError: check_corpus.py has no ts column
```

**Order justification:** W3-W5 must land first or the column would be a wall of FAIL with no
diagnostic value; running it before W7 means the differential arm joins a corpus that already
typechecks, so any disagreement W7 finds is semantics, not syntax. W6 is also the toolchain
decision point: if classic tsc rejects a legitimate emitted construct anywhere in the corpus,
the switch to `typescript@7` (tsgo) is re-recorded here with the failing construct shown
verbatim — not absorbed silently, and not decided on W3's minimal fixture alone.

### W7 — Differential: the TS arm in both modes

**What changes:** `backend/differential.py`: `build_typescript(src, d)` (transpile via
`ROOTS`, copy `rt.ts`, `tsc --outDir`, return `["node", d/dist/main.js]`; D4 flags; raises on
transpile, `tsc`, or empty-emission failure) used in `programs()`'s runner dict `:393`, and a
`run_typescript(src, task)` in function mode with the bigint-safe canonical JSON driver (D5).
Function mode's length guard `:284-289` extends to
`len(py) == len(rs) == len(ip) == len(ts) == len(task["cases"])` — a truncated or empty `ts`
result list is the existing `RuntimeError`, not a silently shorter comparison. Program mode's
agree expression `:407` gains `seen["ts"]`. Tables and summary gain `ts`: the `functions()`
header, the `programs()` header `:370`, and the summary string `:507` become
`(python/rust/wasm/interp/ts)`. Declared case values and existing arms untouched. Exit code
stays the disagreement count.

**Why:** acceptance 3. This is the gate that has caught cross-target defects nothing else
could (I/O mapping, nested-form lowering); TS joins the property instead of claiming it. The
summary-string and non-empty-emission requirements are the per-arm visibility half of the
anti-stub measures (§1).

**Gate (fails now)** — the assert half, then a full run that must exit 0 (zero disagreements)
**and** print a summary naming all five arms:
```
.venv/bin/python -c "
import pathlib
s = pathlib.Path('backend/differential.py').read_text()
assert 'build_typescript' in s, 'differential.py has no typescript arm'
" \
  && out=$(.venv/bin/python backend/differential.py) || { printf '%s\n' "$out"; exit 1; }
printf '%s\n' "$out"
printf '%s\n' "$out" | grep -q "python/rust/wasm/interp/ts"
```
Current verbatim output of the assert half:
```
AssertionError: differential.py has no typescript arm
```

**Order justification:** last — it is the integration point over every artifact W1-W6 produce;
running it earlier would measure an incomplete backend and burn the one-fix-pass budget on
findings W3-W5's cheaper gates already catch.

## §4 Acceptance battery (the phase is done when all of these pass, in this order)

1. `.venv/bin/python grammar/validate.py`
2. `.venv/bin/python grammar/closure_audit.py`
3. `.venv/bin/python prelude/generate.py --check`
4. `.venv/bin/python checker/gate.py`
5. `.venv/bin/python backend/check_corpus.py`   ← now includes the ts/tsc column
6. `.venv/bin/python backend/monomorphism.py`
7. `.venv/bin/python backend/differential.py`   ← five arms in program mode, four in function mode
8. `.venv/bin/python -m pytest backend/t bench/algo checker/t -q`
9. No new coverage floor: `backend/exec_coverage.py` instruments the Python lowering only
   (`:127`, `:140-153`; Python-side execution recording per `:31-32`), the TS templates never
   enter `to_python.LOWER`, and the figures are data in `prelude/coverage.lock`. They are
   expected to be unchanged by this phase; if any figure moves anyway, it moves in the commit
   that earns it, per AGENTS.md.

## §5 Risks

- **Fork `ts` templates vs live arities and signatures** — the 100 recovered templates were
  written against the fork's prelude (version `0.3`) while live is `0.2`; whether each still
  formats at its live declared arity is unknown until W1 runs the widened
  `validate_templates()`. Contained: W1's gate fails loudly and the fix is local. Residual,
  recorded honestly: `validate_templates()` checks format-string arity against the live
  declared type, but not that a template's emitted symbols exist in the live `rt.ts`; that
  agreement is enforced only on the surface the corpus exercises (via W6's tsc column) — the
  same enforcement level the live `js` keys have today. A `ts` template emitting a
  nonexistent `RT.*` helper for a builtin no fixture reaches passes W1-W7 silently; if that
  residual is ever closed, it is closed for `js` at the same time or with the same mechanism.
- **Fork transpiler coverage of live-only corpus forms** — the fork was built before fixtures
  16-29 existed (recursive schemas, nested cons, map lifecycle, string transforms, numeric
  edge cases). Whether its special forms and type mapping cover them is unverified; W6's gate
  is where this surfaces. This is the largest unknown in the phase; if a form is missing, the
  work is a lowering fix in `to_typescript.py`, not a gate change. W6's empty-emission rule
  exists so this surfaces as a failure, never as a quiet `ok`.
- **Pattern-matcher seeding** — the fork's matcher holds user-`defenum` cases only; without
  W3's rework 4, `(err (not-found))` drops its tag test and matches every `err`, and the
  fixtures pass while wrong. The seeding is part of W3's gate surface (08-io typechecks at W5,
  but only the differential's declared stderr proves the tag was tested).
- **`permission-denied` observability on macOS** — the differential case seeds a `0o000` file
  (`differential.py:436-437`); under some sandboxed/root environments the OS may not return
  `EACCES`. Pre-existing condition for python/rust/wasm (they pass today), so node should see
  the same errno; if it does not, that is a genuine disagreement the gate is designed to catch.
- **tsgo vs classic tsc** — D4 pins classic 5.x; the decision point is W6's corpus-wide
  compile, and a switch to `typescript@7` (tsgo) must be recorded with the failing construct
  shown, not absorbed silently. W3's minimal fixture alone does not justify the switch.
- **`@types/node` major (26.x) vs node 22 runtime** — types-only, so runtime behavior is
  unaffected; if the typing surface fights the emitted code, pinning an older `@types/node`
  matching node 22 is acceptable and recorded in W2.
- **`.plans/PHASES.md` "third arm" wording is stale** — the acceptance sentence is read as
  "a new arm on differential.py runs and agrees" (parent task statement); the arm counts in §1
  are as measured today from `differential.py`, not from PHASES.md.
- **Program-mode run directory seeding for node** — differential seeds each runner's cwd with
  case files (`:384-390`); node resolves relative paths against cwd, same as the python arm,
  so no change expected — unverified until W7 runs.
- **Four IoError cases have no failing-path differential case** — `already-exists`,
  `invalid-path`, `interrupted`, `other` are pinned at the unit level only (W5's part-2 gate);
  this matches `prelude/coverage.lock:512-515` and is stated here so nobody later mistakes the
  differential's 2/6 stderr pinning for full mapping coverage.
