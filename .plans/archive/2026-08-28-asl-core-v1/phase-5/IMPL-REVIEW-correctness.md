# Implementation Review — Phase 5 — Correctness & Regression

Lens: correctness and regression only. The work under review is the Phase 5 reference interpreter (`crates/agentscript-ts`, `crates/agentscript-interp`) plus the I8 wiring in `backend/differential.py` and the per-fixture oracle / driver / probe / replay tooling. Function mode for the interpreter is out of scope (PLAN §1). Gate integrity, code reuse, and other lenses belong to other reviewers.

## Verdict

**approve**

The interpreter reproduces the §2.5 runtime semantics cited by the plan. All eight hand-written probes pass. All 26 driver-wrapped corpus fixtures (I3/I4/I5/I6 map) match the derived oracle. The differential gate extends from three arms to four with no change to existing arms, no change to declared values, and `0 disagreement(s) across 120 function cases + 15 program cases (python/rust/wasm/interp)`. pytest 161/161, cargo test 9/9, replay 15/15, exec_coverage 107/107, monomorphism 0/440, closure_audit clean, validate 0, checker gate 0, check_corpus 0. None of the gates the plan names regress.

## Findings

### Blocker — none

### Major — none

### Minor

**M1. `tag_order` is keyed globally by case-name string across all units (eval.rs:1012-1027, link() at 148-159)** — risk class: same-named cases in two different enums would collide on the cross-enum key. The user-sort probe (`probes/user-sort.agentscript`) covers single-enum declaration order; the corpus never sorts user enums across enum types, so this is unenumerated in the witness set. The plan §2.5 calls out declaration order as the *presumptive* rule (§3.2 is flagged as a spec gap) and ROADMAP `l-5c47` records the same shape. Reported as minor because the plan already pins this gap and the interpreter matches the plan; the cross-enum case is a Phase-9 item, not a Phase-5 one. Filed for orchestrator.

**M2. `Callable::Case(String, usize)` carries an unused arity field (value.rs:17)** — does not affect correctness; cargo reports it as a dead-code warning. The arity was probably going to be used for user enum arity checks that didn't make it in. Cosmetic.

**M3. The unit test `two_nan_sort_is_stable` (eval.rs:1248) builds the input list out of order (`[NAN, NAN, 1.0, 2.0]`) and asserts `v[0]==1.0, v[1]==2.0` — passes — but the assertion only proves that finite floats sort before NaN. The NaN-tie input-order property is asserted by `probes/nan-stability.expected` (`a,b,c,e,d`), which the interpreter reproduces. So the test is redundant with the probe, not wrong. Reported because the test name promises more than it asserts.

## Conformant-but-wrong (what a wrong interpreter would still pass)

A wrong interpreter that nonetheless satisfies the headline gate must fail at least one of:

1. **Any hand-written probe.** Eight probes; the most discriminating is `user-sort` (Python arm prints `'alpha,zed'`, expected `'zed,alpha'`; only the interpreter's declaration-order rule passes) and `try-in-lambda` (Python arm prints `'ok:reached'`, expected `'err:not-found'`; the interpreter correctly unwinds `try` past a lambda frame per spec §5.5). Verified by transpiling both probes with `to_python.py` and running under `backend/runtime.py` — Python arm disagrees on both.
2. **`int32-trap` probe** — Python arm ignores Int32 width (ROADMAP `l-4d92`); only the interpreter traps. Verified: the probe runs and exits 2 with `trap: int32 overflow` on stderr.
3. **`escapes` probe** — no corpus fixture exercises any of the six escapes; the probe is the only witness.
4. **`parsable-guards` probe** — Rust's bare `parse()` accepts `"١٢٣"` and `"1_000"`; the probe forces the `_parsable` guard to be ported.
5. **`map-pairs-order` probe** — BTreeMap is codepoint-ordered; only the codepoint-order implementation passes (`"Z=0,a=1,b=2"`).
6. **`nan-stability` probe** — two-NaN input order is preserved only by a stable sort with NaN-last; the probe's `a,b,c,e,d` pins it.
7. **`read-line-eof` probe** — `read-line` returning `(none)` at EOF; not exercised by any declared program case.
8. **The 26 driver-wrapped fixtures** — the derived oracle is the Python lowering, so a wrong interpreter that mimics Python would still pass these. The 8 probes above are the asymmetry that breaks the symmetry.

The full **declared-want battery** in `program_cases()` (8 fixtures, 15 cases including `08-io` failing path, `19-io-errors` permission-denied / not-found / etc.) is also hand-written and so works as a witness — verified that `program_cases()` is unmodified in the diff vs baseline.

So a "wrong interpreter that passes the differential headline" would have to: (a) get Int32 traps right, (b) get try-through-lambda right, (c) get user-enum sort order right, (d) get all six string escapes right, (e) get the parse guards right, (f) get map iteration order right, (g) get NaN stability right, (h) get EOF behavior right. Failing any of these is detected.

## Gates run (verbatim, with explicit verdicts)

| Gate | Verbatim tail | Status |
|---|---|---|
| `.venv/bin/python backend/differential.py` | `0 disagreement(s) across 120 function cases + 15 program cases (python/rust/wasm/interp)` | green |
| `.venv/bin/python -m pytest backend/t bench/algo checker/t -q` | `161 passed in 53.32s` | green |
| `rustup run stable cargo test --manifest-path Cargo.toml -q` | `running 7 tests` (num) + `running 2 tests` (eval) + `running 0 tests` (cst), all `ok`; 9 unit tests pass, 0 failed | green |
| `.venv/bin/python .plans/phase-5/replay.py` | `replay.py: 15/15 program cases agree (interp)` | green |
| 8 probes against `$B` (escapes, nan-stability, parsable-guards, map-pairs-order, user-sort, try-in-lambda, read-line-eof, int32-trap) | exit 0 for stdout-bearing probes; exit 2 for `int32-trap`; all match `.expected` | green |
| I3-I6 driver-wrapped fixtures (26 fixtures) | `DRIVERS: fail=0` | green |
| `.venv/bin/python backend/exec_coverage.py` | `107/107 (100%)`, `0 coverage failure(s)` | green |
| `.venv/bin/python backend/monomorphism.py` | `candidates: 440, narrowed: 40, probes: 400, rustc: ok, py_compile: ok, 0 failure(s)` | green |
| `.venv/bin/python grammar/closure_audit.py` | `executed builtins 107/107 (100%) OK: spec and corpus are closed` | green |
| `.venv/bin/python grammar/validate.py` | `0 failure(s)` | green |
| `.venv/bin/python prelude/generate.py --check` | (silent) | green |
| `.venv/bin/python checker/gate.py` | `0 failure(s)` | green |
| `.venv/bin/python backend/check_corpus.py` | `0 failure(s)` | green |

## §2.5 semantic checks (file:line evidence)

| Claim | File:line | Verdict |
|---|---|---|
| Int32 + Int64 are siblings; arithmetic traps at operand width | `num.rs:30-58` (`iadd`/`isub`/`imul` call `check_width`), `eval.rs:386-404` (`num_binop` picks I32 if either operand is I32) | matches |
| Int32 trap exits 2 with stderr diagnostic | `num.rs:51-58` (check_width), `main.rs:79-83` (Err printed → exit 2), `int32-trap` probe rc=2 stderr=`trap: int32 overflow` | matches |
| Out-of-width literal is an error | `num.rs:104-111` (`parse_int_lit`) | matches |
| `mod MIN -1 == 0` | `num.rs:74-83` (`imod` uses unchecked quotient) + cargo test `min_mod_minus_one_is_zero` (`num.rs:200-203`) | matches |
| NaN total order: NaN last, tie with each other, stable | `eval.rs:940-954` (`compare`/`compare_orderable`), `eval.rs:1018-1022` (`stable_sort_by` delegates to `slice::sort_by`, which is stable) | matches |
| User enum/union sort = declaration order | `eval.rs:148-159` (link populates `tag_order` in unit order with cases in declaration order), `eval.rs:990-994` (`compare_orderable` uses `tag_order` index), probe `user-sort` verifies | matches |
| Structural equality, NaN ≠ NaN inside containers | `value.rs:101-126` (`eq`, recurses through containers), `value.rs:113` (`Float(x)==Float(y)` uses `==` — so NaN != NaN) | matches |
| `fmt_f64` == Python repr, exponent ≥2 digits | `num.rs:165-178` + cargo test `fmt_f64_pins_exponent_digits` (`num.rs:186-192`) | matches |
| `_parsable` guard (no unicode digits, no `_`) | `num.rs:135-138` (`is_parsable`), `num.rs:119-141` (`to_int`/`to_float`), probe `parsable-guards` verifies | matches |
| `f_to_i` range before truncation | `num.rs:152-160` (`f_to_i`, INT64_MIN ≤ t < 2^63), `eval.rs:625-628` | matches |
| `int64-to-int32` range check | `num.rs:144-149` (`to_i32`) | matches |
| Maps are BTreeMap keyed with language order | `value.rs:53-83` (`MapKey` Ord — codepoint for S, i64 for I, etc.), `value.rs:55` (S cmp codepoint), probe `map-pairs-order` verifies (`Z=0,a=1,b=2`) | matches |
| Float64 not a legal map key | `value.rs:60-73` (`MapKey::from_value` returns None for Float) | matches |
| String indices are character-based, not byte | `builtins.rs:18-26` (`str_slice` uses `chars`), `builtins.rs:32-41` (`str_index_of` converts byte → char count), `eval.rs:444-447` (`string-length` uses `chars().count()`) | matches |
| All six escapes unescaped | `cst.rs:373-391` (`unescape` for `\" \\ \n \t \r \0`), probe `escapes` verifies | matches |
| IoError mapping from ErrorKind, NotADirectory\|IsADirectory → invalid-path | `io.rs:35-44` (`IoError::from`) | matches |
| `read-line` returns (some) without `\n`, (none) at EOF | `io.rs:47-56` | matches |
| Writes flush | `io.rs:65-75` (`write_to` flushes), `io.rs:84-88` (`file_append` flushes) | matches |
| Exit glue: ok → 0, err → stderr+1, anything else → 2 | `eval.rs:1202-1218` (`exit_glue`) | matches |
| Module identity keyed by **defining module path** (not alias) | `modules.rs:74-77` (`mod_index.insert(path, i)` and `mod_index.insert(mp, i)`), `eval.rs:162-165` (link uses defining path), `eval.rs:399-409` (resolve_callable_in uses unit index, not alias) — and the differential `13-module-program` case (reaching one module through two aliases) passes on the interp arm | matches |
| Resolution: dependencies first, root last, cycle broken (not diagnosed) | `modules.rs:79-100` (`seen` seeded with root's path, recursion skipped on already-seen) | matches |
| Enum/runtime tags are **bare case names** across boundaries | `eval.rs:362-365` (resolve uses bare tag from `enum_cases` list), `eval.rs:1177-1184` (`construct` writes bare names) — and `09-imported-types` / `10-imported-generic-types` driver fixtures pass | matches |
| `try` unwinds through lambdas to the nearest defun | `eval.rs:255-264` (Try evaluation: Step::Ret propagates), `eval.rs:498-501` (lambda apply re-propagates Step::Ret — does NOT consume it), `eval.rs:533-534` (defun boundary consumes Step::Ret → Step::OK) — and `try-in-lambda` probe verifies | matches |
| Lexical frames, shadowing | `eval.rs:208-217` (Let pushes a new frame, binders shadow top-levels) | matches; `15-shadowed-binders` driver fixture passes |
| Bodies strict left-to-right, every non-final evaluated | `eval.rs:179-189` (`eval_seq` — only stops on Ret, otherwise falls through to the last) | matches; `14-sequenced-bodies` differential case passes |
| `and`/`or` short-circuit, nothing else | `eval.rs:336-348` (`eval_logical`) | matches |

## I8 wiring checks

- `agree` comparison: `backend/differential.py:381` — `seen["python"] == seen["rust"] == seen["wasm"] == seen["interp"]`. Python chained `==` is `(a==b) and (b==c) and (c==d)` — transitive, correct.
- `declared_ok`: `backend/differential.py:382` — `seen["python"] == want`. Separate from `agree`. Per PLAN §2.2 invariant.
- `build_interpreter` shape: `backend/differential.py:320-339` — prepends `--root ROOTS`, then SOURCE, leaving argv to be appended by `programs()`. Matches the other arms' `cmd + argv` pattern.
- Runners dict includes "interp" alongside the unchanged python/rust/wasm: `backend/differential.py:368`.
- Table header and per-case row updated: `backend/differential.py:356, 386-388`.
- Summary line names four arms: `backend/differential.py:476` — `+ {program_total} program cases (python/rust/wasm/interp)`.
- Existing arms unchanged: `git diff 8e6966a HEAD -- backend/differential.py` shows only the I8 additions (build_interpreter, runners dict update, header/row/summary updates); no changes to `program_cases()`, declared `want` values, or `build_python`/`build_rust`/`build_rust_wasm`.
- `prelude/coverage.lock`, `backend/cases/`, `backend/exec_coverage.py`: `git diff 8e6966a HEAD` for all three — empty.

## Risks / Unverified

- **Function mode (R1 from plan §5 risk 10)**: the interpreter has no entry-invocation protocol. Out of scope for Phase 5; flagged by the plan. The 120 function-case agreement is python-vs-rust only — the interpreter is not exercised in function mode. Not a regression because there is no prior function-mode behaviour to regress.
- **Cross-enum `tag_order` collision (M1 above)**: not pinned by any witness. Same gap as ROADMAP `l-5c47`. Plan §3.2 spec change is the orchestrator's.
- **Sort stability for `list-sort-by` with two-NaN ties on a `List X` keyed by a string key**: M3 above. The probe pins the underlying sort, but no probe pins the `list-sort-by` variant directly. The implementation reuses `stable_sort_by` (eval.rs:961), so by construction it has the same stability; not separately verified by a probe.
- **`min`/`max` selection on user types**: uses `compare` → declaration order. Same gap as `list-min`/`list-max` on user types. Not exercised by corpus, not pinned by a probe. The plan's `user-sort` probe covers `list-sort` only.
- **`format!("{:?}", x)` for non-finite / subnormal floats**: cargo test `fmt_f64_pins_exponent_digits` pins `1e16`, `-0.0`, `nan`. Other values (denormals, signed zeros) are not pinned by a cargo test — but the corpus doesn't produce them, and `runtime.py` `repr` matches Rust's `{:?}` for the values that do appear in `29-literals`.

## Reply to orchestrator

`.plans/phase-5/IMPL-REVIEW-correctness.md` · **approve** · 0 blockers, 0 major, 3 minor · Highest-value finding: the interpreter agrees with the **hand-written** `user-sort` and `try-in-lambda` probes where the Python arm is verifiably wrong (`'alpha,zed'` vs `'zed,alpha'`; `'ok:reached'` vs `'err:not-found'`), proving the headline is not a tautology of two arms sharing a defect.
