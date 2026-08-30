# Implementation Review — Phase 7 (TypeScript backend)

**Lens:** correctness (semantic fidelity of emitted TS; divergence hazards a gate could miss)

**Verdict:** approve-with-amendments

## Gates run (verbatim)

| Gate | Result |
|---|---|
| `backend/check_corpus.py` | exit 0, "0 failure(s)" across all 31 fixtures, every row shows `ts ok / tsc ok` |
| `backend/differential.py` | exit 0, "0 disagreement(s) across 120 function cases + 15 program cases (python/rust/wasm/interp/ts)" |

Manual spot-checks (against compiled output, not just gate exit code):

| Spot-check | Output |
|---|---|
| `25-list-aggregation.agentscript` `agg-empty` | `T|0|0.0|none|none|[]` (matches Python expected) |
| `25-list-aggregation.agentscript` `agg "3,1,3,2"` | `F\|4\|9.0\|1.0\|3.0\|[1.0,2.0,3.0,3.0]` (matches) |
| `23-numeric.agentscript` `edge` at -1, 1, 0, 2, 3 | `none\|some 0`, `some -9223372036854775808\|some 0`, `none\|none`, `some -4611686018427387904\|some 0`, `some -3074457345618258602\|some -2` (matches Python expected) |
| `23-numeric.agentscript` `trap-*` | All seven traps (`trap-div/neg/abs/add/sub/mul/sum`) raise "integer overflow" — identical to Python's `Trap` |
| `14-sequenced-bodies.agentscript` main | `function-1\nlet-1\ncond-1\nelse-1\nmatch-ok-1\nmatch-err-1\nlambda-1\nlambda-1\ncond-bare\nelse-bare\n15\n13\n30\n` (matches declared expected) |
| `15-shadowed-binders.agentscript` main | `7 6 101 102` (matches declared expected) |
| `18-pattern-binders.agentscript` (not a function case, no transpile test directly — verified the emit by reading) | see Findings |
| `19-io-errors.agentscript` `--labels` | `not-found,permission-denied,already-exists,invalid-path,interrupted,other` (matches) |
| `19-io-errors.agentscript` `nodir/out.txt` | stdout `not-found`, stderr `not-found`, exit 1 (matches all five arms) |
| `19-io-errors.agentscript` `noperm.txt` (0o000) | stdout `permission-denied`, stderr `permission-denied`, exit 1 (matches all five arms) |
| `20-option-result-ctors.agentscript` `classify` | pair outputs match expected |
| `21-option-result-combinators.agentscript` `resolve` | both cases match expected |

The cross-arm differential is clean — Python, Rust, WASM, interp and TS agree on every one of the 120 function cases and 15 program cases.

## Blockers

### None

No reachable case produces a wrong result on the TS arm. The 5-arm differential exits 0 with 0 disagreements; every corpus fixture compiles under `tsc --strict` and executes correctly; the IoError mapping, pattern-matcher seeding, and module linking all hold under inspection.

## Major

### M1 — `sum` of an empty `(List Int64)` returns a JS `number` typed as `bigint` (residual risk (b), confirmed)

**File:** `backend/ts/rt.ts:500-503`

```ts
export function sum<T extends ASNum>(xs: readonly T[]): T {
  if (xs.length === 0) return 0 as unknown as T;
  return xs.reduce((a, b) => add(a, b));
}
```

`T extends ASNum = bigint | number`. When T is inferred as `bigint` (the empty `(List Int64)` case), the function returns the **JS number literal `0`** cast to `T`. TypeScript's type system trusts the cast; at runtime the value is a number, not a bigint.

The downstream `(RT.add (sum empty) 1n)` call would route through the float branch of `add` (`typeof a === "bigint"` is false) and crash with `TypeError: Cannot mix BigInt and other types`. The differential's empty-list case (`25-list-aggregation.agentscript` `agg-empty`) only exercises `sum` on `(List Float64)`, where T=number and the cast is harmless.

**Class enumeration:** every place the corpus lowers `(+ (sum empty-int-list) x)`, `(* (sum empty-int-list) x)`, etc. — zero sites today, so this is unexercised but real. No gate currently catches it; adding one would mean either a new corpus fixture that exercises the empty-Int64-sum-in-arithmetic path, or a runtime-side fix (return `0n as unknown as T` and `0 as unknown as T` based on T's runtime tag — though TS erases T at runtime, so this is not straightforward).

**Severity:** Major because it is a real correctness defect on a path the corpus doesn't reach today; not a blocker because no gate fails.

### M2 — Implementer's residual risk (a) about `if_form` ternary is unfounded; no defect there

**File:** `backend/to_typescript.py:402-404`

The implementer's own residual-risk list flagged `if_form` lowered to a ternary as dropping leading effects in multi-expression arms. The grammar (`grammar/tree-sitter-agentscript/grammar.js:132-137`) declares `if_form` with exactly one `consequence` and one `alternative` expression; multi-expression bodies are only legal in `cond` clauses, `match` arms, `let` bodies, function bodies and lambda bodies. The TS backend's `cond`, `match`, `let`, `defun` and `fn` lowerings all use IIFEs over `block(...)` statements; only `if_form` is a ternary, and that ternary is correct because its arms are always single expressions.

No defect — filed as Major only because the implementer's note suggested one exists; worth recording the verification in case future readers inherit the concern.

## Non-blocking

### N1 — `result-or` and `option-or` return paths match Python exactly

**File:** `backend/ts/rt.ts:569-571`, `574-576`; `backend/runtime.py:147-152`

Both lower to tag-string checks against the canonical `"ok"`/`"some"` literals. The Python backend's `opt_or` reads `o[1] if o[0] == "some" else d`; the TS backend's `optOr` reads `o.tag === "some" ? o.value : d`. Same semantics. No drift.

### N2 — `pair` constructor and `ASPair` serialisation produce `["pair", a, b]`

**File:** `backend/ts/rt.ts:57-63`; `_SER` in `backend/differential.py:438-454`

The function-mode harness's `ser` function emits `["pair", ser(v.first), ser(v.second)]` for any `ASPair`. Python's `pair(a, b)` returns `("pair", a, b)` which JSON-serialises to `["pair", a, b]`. They agree.

### N3 — Pattern matcher correctly seeds `IoError` cases (residual risk M3 from design review)

**File:** `backend/to_typescript.py:91-95`

```python
self.enums: dict[str, tuple[str, int]] = {}
for ename, cases in unions().items():
    for case in cases:
        self.enums[case] = (ename, 0)
```

Verified the seed runs by reading `pattern()` at `to_typescript.py:573-580`:
- `(err (not-found))`: outer `enum_pattern(err, enum_pattern(not-found))` recurses with `subj.value`; inner check matches `self.enums["not-found"] = ("IoError", 0)` → emits `subj.tag === "not-found"`; outer wraps with `subj.tag === "err" && subj.value.tag === "not-found"`. Matches `18-pattern-binders.agentscript` and `08-io.agentscript` semantics.

The live corpus exercises `(err (not-found))` in 08-io and `18-pattern-binders`, and `(err e)` in 08-io and 19-io-errors; both lower correctly. Verified by transpile-and-run on 18 (transpiles; the function-mode harness does not call `outcome` directly, but the lowering is exercised when `err (not-found)` is used elsewhere — see 08-io's `((err (not-found)) "missing")` arm).

### N4 — `IoError` constructor lowering

**File:** `prelude/prelude.json:1005-1063`

All six constructors lower to bare calls: `not-found` → `RT.notFound()`, etc. The runtime functions each return a frozen-tag object `{ tag: "..." }` with zero slots. The function-mode `_SER` emits `["not-found"]` etc., matching Python's tuple representation `("not-found",)`.

### N5 — `_SER` correctly serializes a tagged value with zero slots as `["tag"]`

**File:** `backend/differential.py:454-465` (`_SER` `ser` function)

For `RT.notFound()` returning `{ tag: "not-found" }`, the function emits `["not-found"]`. Python `("not-found",)` serialises to the same JSON. The differential gate ran 120 function cases through both arms without disagreement.

### N6 — The `errFor` helper handles errors without a `code` field

**File:** `backend/ts/rt.ts:659-664`

```ts
function errFor(e: unknown): IoError {
  if (typeof e === "object" && e !== null && "code" in e) {
    return codeToIoError((e as { code?: unknown }).code as string | undefined);
  }
  return { tag: "other" };
}
```

Any non-Node-stdlib error (e.g., a thrown string or a custom `Error` subclass without `code`) falls through to `other`. Matches the Python `_io_err` which uses `getattr(exc, "errno", None)` and falls through to `"other"` on a missing errno.

### N7 — `check_corpus.py` raises on empty TS emission

**File:** `backend/check_corpus.py:108-117`

Empty emission is recorded as `tsc FAIL` with `fails.append(...)`; the transpiler's `NotImplementedError` for an unsupported form (`backend/to_typescript.py:444`) propagates through `subprocess.run(...).returncode != 0` → `ts_ok = False` → failure recorded. The forward-stub arm guard is real.

### N8 — Differential function-mode length guard covers `ts`

**File:** `backend/differential.py:265-274`

```python
if not (len(py) == len(rs) == len(ip) == len(ts) == len(task["cases"])):
    raise RuntimeError(...)
```

A truncated or empty TS result raises rather than silently shortens the comparison. The 120-case run did not trip this — TS returned a result for every case.

## Unverified

### U1 — Four `IoError` cases have no failing-path differential case

`already-exists`, `invalid-path`, `interrupted`, `other` are pinned at the unit level only (the code-mapping gate in W5 part 2). The differential `08-io` and `19-io-errors` fixtures only cover `not-found` and `permission-denied` in failing-path bytes. A disagreement on `EEXIST`/`ENOTDIR`/`EISDIR`/`EINTR`/EINVAL would not be caught by the differential today. The PLAN §5 and `prelude/coverage.lock:512-515` already record this gap.

### U2 — `sum` of empty `(List Int64)` in arithmetic (M1 above) — unexercised

No fixture calls `(+ (list-sum empty-int-list) x)`. Adding such a fixture would exercise the divergence in M1; absent that, the gate passes while the runtime is wrong on the path.

### U3 — `process-run` `ProcessResult` serialisation

**File:** `backend/ts/rt.ts:673-680`; `_SER` in `backend/differential.py`

A `ProcessResult` has `{exitCode: bigint, stdout: string, stderr: string}`. The `_SER` `ser` function has no branch for objects with `exitCode`/`stdout`/`stderr` fields; it falls through to `JSON.stringify(v)` which throws on `bigint`. No function-mode case calls `process-run`, so the bug is unexercised. The program-mode `19-io-errors` `--slurp` uses `read-all`, not `process-run`.

### U4 — `fn` form with `try` inside is rejected

**File:** `backend/to_typescript.py:438-441`

```python
if has_try(n):
    raise NotImplementedError("`try` inside `fn` is not lowered to TypeScript: the "
                              "throw would leave the closure at an unrelated frame")
```

This is intentional and matches the Python `to_python.py` behavior (the Python backend has the same limitation). No corpus fixture uses `try` inside a lambda; the gate does not exercise this path.

### U5 — The `if_form` ternary emits `cond ? a : b` directly

**File:** `backend/to_typescript.py:402-404`

Per grammar, both arms are single expressions — `expr(a, ind)` and `expr(b, ind)` are sufficient. But because the arms are always expressions (not IIFEs), a nested `match` or `cond` inside an arm would be its own expression — handled correctly. No defect here.

## Notes for the fix agent (if any)

If M1 is to be closed: the cleanest runtime-side fix is to make `sum` return the typed zero explicitly based on which arithmetic the elements use. The simplest: change the empty branch to `return 0n as unknown as T` and rely on TS overloading — but this breaks Float64 cases where `0n` is not assignable to `number`. A more robust fix: add an overload signature `sum(xs: readonly bigint[]): bigint` and `sum(xs: readonly number[]): number`, with the body specialised per overload, so the empty case can return `0n` for the bigint branch and `0` for the number branch. This is one fix that closes the path without a new corpus fixture. Not required for the gate to pass.
