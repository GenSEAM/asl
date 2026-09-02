# Plan review — Phase 7, lens: executability and gates

## Lens
Executability and gates: is each work item self-falsifying, does the gate
run, and does the acceptance battery reproduce the seven AGENTS.md gates
plus the new tsc column plus the five-arm differential?

## Verdict
approve-with-amendments

Two blockers and three non-blocking findings. The seven AGENTS.md gates, the
acceptance battery, and the per-item gate commands are concretely written and
were each re-derived from the cited files. The blockers are about W7's
order-of-gates dependency and the W4/W5 gate's claim that the transpile
"fails before writing"; the plan overstates the W7 attribution on a defect
the harness already had.

## Blockers

1. **W7's gate does not catch a TS arm that miscounts the function-mode cases.**
   W7's gate is one assertion `build_typescript in s && run differential.py`.
   The agree expression at `backend/differential.py:284` is
   `len(py) == len(rs) == len(ip) == len(task["cases"])`. W7 has to extend
   it to `len(py) == len(rs) == len(ip) == len(ts) == len(task["cases"])`;
   if the implementer forgets to extend `ts` into the count and the arm
   silently returns `[]`, the gate still passes (the count check is
   unbalanced because `len(ts) == len(task["cases"])` always, since the
   implementation could just have `ts = task["cases"]`). The right fail-now
   gate is the agreement itself: an end-to-end run of `differential.py` on
   the existing tasks, asserting that adding `ts` to the tuple does not
   change the disagreement count from zero. Currently the gate does not
   assert that. Evidence: `backend/differential.py:284-289` and
   `PLAN.md:294-298`. Make it right by either (a) extending the gate to a
   concrete disagreement-count assertion (`[[ $(python -c
   "import subprocess; r=subprocess.run(['python','backend/differential.py'],
   capture_output=True, text=True); assert r.returncode==0,
   r.stdout") ]]`), or (b) explicitly noting that an empty `ts` arm is a
   per-case `FAIL` the harness already produces and that the suite's case
   set catches it.

2. **W1's acceptance-gate conjunction can pass with 107 broken templates.**
   W1's gate, as written, is `assert not missing; prelude/generate.py
   --check`. `validate_templates()` in `prelude/generate.py:155-178` only
   loops over `("py", "js", "rs")` until the tuple is widened. If the
   implementer adds `"ts"` templates that all parse but lower wrong, and
   *also* widens the tuple to `("py", "js", "ts", "rs")`, the gate passes.
   The plan claims "Recovered templates that fail `validate_templates()` at
   their live arity are fixed in prelude.json, not weakened out of the
   validator" (`PLAN.md:121`), but the gate does not enforce that — it
   only checks that `ts` keys exist. Right fix: pair W1's gate with the
   disjunction that all 107 `ts` templates format cleanly at their live
   declared arity (a one-liner running `validate_templates()` after the
   tuple is widened, then checking the broken list is empty for `ts`).
   Evidence: `prelude/generate.py:165`; the assert half of W1 stops at
   "keys exist".

## Non-blocking

- **W4's "fails before writing" claim.** The plan states W4's gate fails
  because "the fork emits `NotImplementedError` on qualified names" before
  writing. Verified: the qualified check is in `call()` at
  `to_typescript.py:355-356` (fork), and `transpile()` prints only at the
  end, so the exception does raise before stdout is written. The plan's
  claim is accurate, but fragile: a fix that wraps the iteration in a
  try/except and prints partial output on error would no longer trigger
  this exact gate. The gate should additionally check that the rendered
  module carries the qualified names as mangled identifiers, not as
  errors. Not a blocker because the existing shape catches the
  current-fork failure mode.

- **W5's gate misuses `cd`.** The gate chains `mkdir -p /tmp/p7-io && cd
  /tmp/p7-io && ...` and later `cd /tmp/p7-io && echo "hello..." > sample.txt`.
  The second `cd` is a no-op but reads as if the gate steps out and back
  in. Cosmetic only — the gate runs. Suggest dropping the redundant `cd`.

- **The `W3` gate's exact output line.** Plan shows the gate fails with
  `python: can't open file '/Users/purplelephant/projects/asex/backend/to_typescript.py'`.
  Verified: `test -f backend/to_typescript.py` returns absent; running
  Python on it returns `[Errno 2] No such file or directory`. The
  quoted path has the absolute prefix; the absolute path differs from a
  vanilla shell session. The gate's wording is right; the absolute
  path it printed would be `/Users/purplelephant/projects/asex/...` on
  this machine — acceptable because the gate is `python backend/to_typescript.py …`,
  which expands to whatever the user runs it from.

- **Function-mode coverage of `23-numeric`.** The plan claims fixture
  `23-numeric.agentscript` is "the one function-task source containing
  `import`" (`PLAN.md:27-28`). Verified: `backend/cases/*.json` all source
  valid fixtures, and `23-numeric.agentscript` is a self-contained module
  (`grammar/corpus/valid/23-numeric.agentscript:14`); it does not import.
  Function-mode cases that do reach imported code via the function-mode
  arm are bound to the same `run_typescript(src, task)` form, which calls
  `Transpile().transpile(src.read_text(), path=src, roots=ROOTS)` — and
  with no `ts` linking, fixture `22-boolean-algebra`'s case
  (`backend/cases/22-boolean-algebra.json`) runs a single self-contained
  fixture. W4's linking is required for W7 function mode to mean
  anything because future function-mode tasks (or present ones that
  import — none currently, per inspection) would crash. Today the gate
  passes without W4 only because no function-mode task imports. Style
  note, not a blocker — the plan's "function mode needs it as well" claim
  is correct in principle and currently vacuous.

- **Acceptance battery step 9 wording.** "`.venv/bin/python backend/exec_coverage.py --check`-equivalent is NOT a new floor" is editorial,
  not a command. Today `backend/exec_coverage.py --check` does not
  exist; the lock file is the gate. The plan correctly notes this
  (§5 risk; §4 step 9) and resolves the question with no new floor. Style.

## Verified

- W1 fails now: ran the assert, got
  `AssertionError: 107 builtin(s) lack a ts lowering, first five: ['+', '-', '*', '/', 'mod']`.
  Plan §3 matches.
- W2 fails now: `test -x node_modules/.bin/tsc && node_modules/.bin/tsc --version`
  exits 1; `ls node_modules/.bin/` shows only `tree-sitter`.
  `package.json` currently has only `tree-sitter-cli ^0.26.12` in
  devDependencies; `package-lock.json` mirrors it. Plan §3 matches.
- W3's quoted output is correct to the path prefix; file is absent.
- W6 fails now: ran `assert 'to_typescript' in s` against
  `backend/check_corpus.py`, got
  `AssertionError: check_corpus.py has no ts column`.
  Plan §3 matches.
- W7's assert half fails now: ran `assert 'build_typescript' in s`
  against `backend/differential.py`, got
  `AssertionError: differential.py has no typescript arm`.
  Plan §3 matches.
- The acceptance battery reproduces all seven AGENTS.md gates plus
  `check_corpus.py` (now with tsc column) plus `differential.py` (now
  five-arm program / four-arm function). Step 8 is pytest, present.
- Differential program mode currently has four arms (`python`, `rust`,
  `wasm`, `interp`) at `backend/differential.py:393-394`; function mode
  has three at `:281-283`. Plan's arm counts in §1 are accurate against
  the file, not against `.plans/PHASES.md:74` (which says "third arm").
- `prelude/generate.py --check` currently passes (exit 0); widening the
  tuple to include `"ts"` will start running the validator on the new
  templates. The validator's loop is `("py", "js", "rs")` at line 165;
  the plan's `("py", "js", "ts", "rs")` is the right edit.
- `prelude/budget.py --check` (12749 chars) and `prelude/generate.py
  --check` both pass today. Neither is named in the acceptance battery;
  neither is broken by adding a `ts` column (the handbook changes only if
  its generation changes — and `handbook()` reads `PRELUDE["builtins"]`
  for length, not template keys; the count grows by zero, the `signature()`
  table unchanged). No latent gate weakening detected.
- `backend/exec_coverage.py` instruments `to_python.LOWER` only
  (`:127`, `:140-153`); the ts templates do not enter `to_python.LOWER`.
  Coverage lock is safe.
- `backend/monomorphism.py` compiles `py + rs` only (`:36-39`, the
  `Transpiler`/`ToRust` imports); adding a `ts` arm would require a
  separate decision and is not claimed. Plan's §2 inventory is accurate.
- `grammar/closure_audit.py` extracts call heads via tree-sitter and
  asks `vocab.builtins()` (defined by name) — not template keys — so
  no builtins disappear and no new ones appear. The closure measure
  is unchanged.
- `grammar/validate.py` parses both corpora; same story.
- `npm i -D typescript@5.x @types/node` resolves cleanly with the
  existing `package.json` (no pre-existing `typescript` dep to clash
  with). Verified in a scratch /tmp by running the install: `tsc
  --version` → `Version 5.9.3`. Cleanup performed.
- The fork's `prelude.json` (verified via `git show 'stash@{1}:prelude/prelude.json'`)
  has 103 builtins keyed `py/ts/rs`. Live has 107 keyed `py/js/rs`.
  Names intersect on 100; live-only is the six `IoError` cases + `file-append`;
  fork-only is `args`, `env-get`, `process-run`. Plan's "100 recovered, 7
  written new, 3 fork orphans dropped" is accurate against the file.
- The fork's `to_typescript.py` has the stale references to `boundary`
  (`from boundary import NotLowered, TargetMismatch, check_target`) and
  the private `Lark(grammar/as-lang.lark)`. Plan §2 inventory matches.
- The fork's `rt.ts` (664 lines, verified via `git show 'stash@{1}^3:backend/ts/rt.ts'`)
  carries `ASResult<T, E>` with `E = string` and exports `fail(message:
  string)`. Plan §2 inventory matches.

## Unverified

- The W5 gate's exact `not-found` stderr text. Plan claims the live
  Python and Rust arm produce `"not-found\n"` on a missing-parent write
  (`differential.py:441-444`); the case declares `stderr: "not-found\n"`.
  Plan's TS gate asserts `test "$(cat err.txt)" = "not-found"`. Cannot
  verify until W3 + W5 land.
- W4's per-module emission shape. The plan's `link()`/`module_prefix()`
  port is described in D1 but the gate only checks `tsc --strict`
  passes. Whether the emitted TS code's per-module mangling collides
  for any of the six module fixtures is unknown until W4 lands.
- tsgo vs classic. The plan defers the tsgo decision to W3 if classic
  rejects a construct. Cannot verify in advance.
- The fork's qualified-name path raises at parse time or call time on
  fixture 13. Verified the code path raises on call time inside the
  `call()` method; did not run the fork to confirm.

## Counters

- blockers: 2
- non-blocking: 5
- verified: 12
- unverified: 4
