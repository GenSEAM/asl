# REVIEW — coverage lens

**Lens:** coverage — what conformant-but-wrong implementations still pass this plan's gates?

**Verdict:** reject

**Blocker count:** 4 blockers, 3 majors, 2 minors.

---

## Findings (severity + evidence)

### B1 — The differential "six-arm agreement" claim permits a vacuous implementation that runs no Go-specific code

**Severity:** blocker.

**What is wrong:** The plan's acceptance sentence 3 says *"the differential gate agrees on six arms in program mode and five in function mode, against the unchanged declared `stdout`/`stderr`/`exit`/`want` values, exits 0, and its summary names all six arms."* The W7 gate (`PLAN.md:475-487`) is `assert 'build_go' in s, 'differential.py has no go arm'` plus a grep for the substring `python/rust/wasm/interp/ts/go` in the captured output. Two conformant-but-wrong implementations pass it:

1. A `build_go(src, d)` that returns `["python3", "/path/to/cand.py"]` after `go build` succeeds on a no-op stub. The arm "runs" python by accident, stdout/stderr/exit match the python arm exactly, and the agreement holds by passing the work to a sibling arm.
2. A `build_go` that writes a Go program which, at run time, shells to `python3` and forwards the python arm's output. The same trivial agreement holds.

Neither needs the Go arm to execute Go code, and neither is closed by the per-arm string presence assertion, the `go vet` column, or the summary substring — those assert that a string exists, not that distinct code ran.

**Evidence:**
- `PLAN.md:475-487`: W7's `assert 'build_go' in s` is the only structural assertion; no per-arm execution counter is added.
- `backend/differential.py:417-419`: `agree = (seen["python"] == seen["rust"] == seen["wasm"] == seen["interp"] == seen["ts"])` — adding `== seen["go"]` extends the chain, but no clause disambiguates "go actually executed distinct code" from "go forwarded".
- `backend/differential.py:472-507`: the runners dict and `seen[name] = (stdout, stderr, returncode)` are added in W7; nothing in W7's gate prevents a forwarded/identical column.
- The plan's "anti-stub measures" (PLAN.md:118-138) claim four protections. Two of them — summary string and non-empty-emission — are present in code shape, but neither is *asserted* in the gate: W7 only greps the string, and the per-fixture `go vet` column runs against an emission that might pass vet while emitting only `package main; func main() { os.Exit(0) }` (no program logic, no I/O surface call).
- `backend/differential.py:392-403` (the TS twin the plan names) raises on empty emission. The plan inherits this for Go, but a transpiler emitting the empty string plus `func main() { os.Exit(0) }` would still pass `go build` (the host has no observable program behaviour) and still match `seen["python"]` whenever python's `main_exit` returns 0 for a happy path — which all five program-mode happy paths are.

**What would make it right:** Either (a) assert a per-arm execution counter (e.g. `seen["go"]` was filled by `run_go`, not by a forwarded `run_python` proxy, by a sentinel value the runner stamps into stdout), or (b) require the gate to fail when `seen["go"]` is byte-identical to any other arm on every fixture (a degenerate forwarder), or (c) require the `IoError` failing-path stderr byte strings to come from `ErrnoToIoError` directly (already asserted by W2's unit probe, but W7 has no integration with it). The plan does none of these.

### B2 — The `try`-in-lambda case is unaddressed by the differential gate, and the plan leaves the TS arm's explicit rejection undocumented

**Severity:** blocker.

**What is wrong:** `14-sequenced-bodies.agentscript` declares `in-lambda` (a lambda body with a bare leading effect) and notes in its docstring *"a lambda cannot propagate out of its caller"* (file:30-39). The TS backend hard-rejects `try` inside `fn` with `NotImplementedError("try inside fn is not lowered to TypeScript: the throw would leave the closure at an unrelated frame")` at `backend/to_typescript.py:445-449`. The plan §D4 ("`try` lowering: panic/recover, mirroring the TS arm's shape") describes a *defun*-with-try path and is silent on try-in-lambda. There are three conformant-but-wrong implementations that pass every plan gate:

1. A Go transpiler that emits `try e` inside a lambda as a Go function that does NOT defer `recover()` — the lambda's panic escapes to the caller. This is silently wrong for the `in-lambda` case (a panic in the lambda's body is a real Go panic, not a `Result` failure), but `in-lambda` has no `try`, only a bare `(println "lambda-1")` effect. The differential program case `14-sequenced-bodies.agentscript` does not exercise `try`-in-`fn` (its `in-function`, `in-let`, `in-cond`, `in-match` cases use `try` inside defuns, not lambdas). The function-mode cases never touch `try`-in-`fn` either.
2. A Go transpiler that wraps every lambda with a deferred `recover()` — which then incorrectly traps arithmetic panics in the lambda and converts them to `(err <something>)` results. This is the silent double-error the TS plan explicitly avoided.
3. A Go transpiler that simply raises `NotImplementedError("try inside fn not lowered")`, matching TS — fine, but the plan does not commit to this.

**Evidence:**
- `backend/to_typescript.py:445-449`: explicit `raise NotImplementedError(...)` for `has_try` inside `fn_form`.
- `grammar/corpus/valid/14-sequenced-bodies.agentscript:30-39`: `in-lambda` is bare-effect only, no `try` inside the lambda body. The fixture declares `run: tally([1,2,3]) == 6` (no return of in-lambda), and the program mode case at `differential.py:454-461` asserts stdout `"function-1\nlet-1\n…15\n13\n30\n"`. `try`-in-`fn` is never written.
- `grammar/corpus/valid/08-io.agentscript:23-26` and `04-longest-run.agentscript` (whole-program) use `try` *only* at defun top level or inside `match`/`if` arms of a defun body, never inside a lambda.
- Plan §D4 (PLAN.md:80-90) describes the `try` shape and notes `has_try` is the guard from `to_typescript.py:298-315` — but does not state whether the Go port raises on `has_try(n)` inside a `fn_form` or whether it follows a different rule.
- Plan §5 risks (PLAN.md:454-486) lists `mangle` collisions, unused-variable, vet false positives, but does NOT list try-in-lambda as a known surface.

**What would make it right:** The plan must commit to one of (a) "the Go port mirrors the TS arm's `NotImplementedError` for `try` inside `fn`" (and name the gate that catches it, or admit none does), (b) "the Go port is permissive and emits a deferred `recover()` for any lambda containing `try`", with a new fixture or a `try`-inside-`fn` program-mode case that pins behaviour, or (c) "the language rules out `try` inside `fn`", and the Go transpiler surfaces a compile-time error. None is asserted.

### B3 — Type-assertion errors in the `defenum`/`match` lowering are runtime panics that no gate catches

**Severity:** blocker.

**What is wrong:** The plan §D2 says `match` lowers to `switch <subj>.Tag` with positional type assertions `Args[i].(<declared type>)` on bound names. A wrong assertion compiles clean (`go build`/`go vet` pass on the assertion's syntactic shape; Go's `args.(int64)` is well-typed Go) and panics only at runtime on the unexercised path. The differential runs the corpus, but only the corpus's exercised cases — which use very few `defenum` cases, and never `defenum` cases with parameters on the *binding* side of a match.

Enumerate what the corpus exercises:
- `grammar/corpus/valid/05-constructors.agentscript`: zero `defenum`s; only `defun`-level match on `Option`/`Result`/`IoError` patterns and `list`/`cons`/`pair`.
- `grammar/corpus/valid/06-module.agentscript`: `Shape` with `circle` (Float64), `rectangle` (Float64, Float64), `point` (no args). Matched by `area` at `(circle r)`, `(rectangle w h)`, `(point)`. Three cases, all bound positionally.
- `grammar/corpus/valid/13-module-program.agentscript`: imports `core/shapes` and matches `(g/circle r)` and `(g/rectangle w h)` — same two cases.
- `grammar/corpus/valid/16-recursive-schema.agentscript`: `Node` is a `defschema`, not a `defenum`; its `Option Node` field uses Option's nullary `none` and unary `some`.
- `grammar/corpus/valid/05-constructors.agentscript`'s `maybe-double` matches `Option Int64`: nullary `none`, unary `some n`. Two patterns.
- `grammar/corpus/valid/18-pattern-binders.agentscript`: matches `Result String IoError` and IoError's `not-found` (nullary). Two cases.

A `to_go.py` that lowers `match sh ((circle r) ...)` to `Args[0].(float64)` — when the source case is `circle r: Float64` — is correct. But a lowering that swaps the argument index, asserts the wrong type, or forgets a binding would compile clean and panic at runtime when the fixture's match is reached. The fixtures' corpus coverage of `defenum` patterns is: `Shape.circle r:Float64`, `Shape.rectangle w:Float64 h:Float64`, `Shape.point` (nullary), `Node.next: Option Node` (`some`/`none`), and `IoError.not-found` (nullary). The remaining 7 enum cases defined in fixtures (or anywhere: `Blob`, `Leaf`, `Node` of trees, `pair`, `list`, `cons`, all six IoError cases except `not-found`) are matched only as patterns, not bound positionally.

Concretely, a wrong `defenum` lowering:
- `pair (a b)` matched as `(a b)` with `Args[0].(int64)` and `Args[1].(int64)`. If the source passes a `Pair (Int64 String)`, the second assertion panics at runtime. The corpus has no function-mode entry that does `match p ((pair a b))` with `p: Pair Int64 String` AND exercises both arms — `backend/cases/24-list-pairs.json` constructs pairs but only reads them via JSON, never matches them. A bug there would go undetected.
- `Shape.point` matched positionally with `Args[0].(<anything>)` would compile fine and never panic on the corpus because the corpus's `area` is never called with a `point`.

**Evidence:**
- `grammar/corpus/valid/06-module.agentscript:15-20`: `Shape` has `point` nullary, but `area` is only called via `13-module-program`'s `(g/rectangle 2.0 3.0)` (one case, no `point`).
- `backend/cases/24-list-pairs.json` returns pairs, no match — `differential.py:452-454` reads the JSON-encoded list of pairs.
- No `defenum` fixture in `grammar/corpus/valid/` exercises both `rectangle` AND `point` AND `circle` together; only `area` covers all three, and `area` is only called via `s/area` from `13-module-program`, which only feeds it `rectangle`.
- Plan §D2 (PLAN.md:48-65) commits to `Args[i].(<declared type>)` but does not name a test fixture that pins it across multiple cases.
- The monomorphism sweep at `backend/monomorphism.py:120-180` only compiles rustc and py_compile — Go does not join (D7). `defenum` is not probed at the typed backends at all.

**What would make it right:** Either (a) add a `match` program-mode case that exercises a 3-case `defenum` end-to-end (e.g. extend `06-module.agentscript` so `area` is invoked at all three cases — already declared, but `13-module-program` only feeds it `rectangle`), or (b) commit to a unit-level probe in W2 (analogous to the `Add`/`Div`/`FmtF64`/`ErrnoToIoError` probe) that constructs each `defenum` case and asserts a `match` against a non-equal subject fails with the expected panic, or (c) add a function-mode task that runs `area` on all three cases. The plan does none.

### B4 — The four unmapped IoError cases (`already-exists`, `invalid-path`, `interrupted`, `other`) have no failing-path differential case after W7

**Severity:** blocker.

**What is wrong:** The plan inherits Phase 7's posture: program-mode differential cases cover `not-found` (08-io) and `permission-denied` (19-io-errors); the other four cases are pinned only at W2's unit level. The plan §5 acknowledges this as a Risk (PLAN.md:470-475). But the plan §D5 says the Go errno mapping is "the same Unix numbers Python's table shares" and "table identical to Python's" — implying the gate proves they agree. It does not. A `codeToIoError`-like mapping in Go that drops the `EEXIST → already-exists` arm and routes to `other` will pass every gate the plan proposes:

- `go vet`/`go build` accept the runtime (it's syntactically valid).
- The `08-io` failing write exercises only `ENOENT → not-found`.
- The `19-io-errors` failing write and failing read exercise `ENOENT → not-found` and `EACCES → permission-denied`.
- The `--labels` happy-path case prints all six case names from the source, not from the runtime.
- The unit-level probe (W2) checks `ENOENT → not-found` and `errors.New("x") → other`. It does NOT probe `EEXIST → already-exists`, `ENOTDIR/EISDIR → invalid-path`, or `EINTR → interrupted`.

**Evidence:**
- `backend/differential.py:436-446`: program-mode cases for `19-io-errors.agentscript` use `["nodir/out.txt"]` (not-found) and `["noperm.txt"]` (permission-denied) as the failing-path entries. `argv: ["--labels"]` is a happy path; `argv: ["--slurp"]` is a happy path; `argv: ["log.txt"]` with stdin `"B"` is a happy path; `argv: ["log.txt"]` without stdin is a happy path. No failing path reaches `EEXIST`, `ENOTDIR/EISDIR`, or `EINTR`.
- Plan W2 (PLAN.md:215-241) probe covers `ENOENT → not-found` and `errors.New("x") → other`. No `EEXIST` case. No `ENOTDIR/EISDIR` case. No `EINTR` case.
- `prelude/coverage.lock:279-289` records `already-exists`, `invalid-path`, `interrupted`, `other` as `unproven` from before Phase 7 — the plan does not propose to close this.
- Plan §D5 (PLAN.md:90-100): the table is given, and the rationale "the differential's byte-for-byte comparison plus W2's direct mapping probe pin that the Go arm runs its own runtime" claims both layers prove the mapping. They prove only 2/6 cases.

**What would make it right:** Either (a) add program-mode failing-path cases for `EEXIST` (e.g. a write to an existing file that the host returns `EEXIST` for — tricky on POSIX since `open(... O_CREAT | O_EXCL)` raises EEXIST, and Python's `open(path, "w")` does not), `ENOTDIR/EISDIR` (e.g. a write to `regular_file/dir/inner.txt` where `regular_file` is a non-directory), and `EINTR` (deterministic delivery is not portable, but the mapping can be unit-probed), or (b) extend W2's probe to assert `EEXIST → already-exists`, `ENOTDIR → invalid-path`, `EISDIR → invalid-path`, `EINTR → interrupted`, and rename the probe's claim from "behavioral probe" to "behavioral probe for the four errno mappings plus the two failing-path cases" — the current W2 probe covers only 2/6 mappings. The plan does neither.

---

## Majors

### M1 — The plan does not pin the FmtF64 exponent-threshold cases at the corpus level, and a buggy FmtF64 passes on every non-pinned case

**Severity:** major.

**What is wrong:** W2's probe (`PLAN.md:230-241`) tests `FmtF64` on `{1.0, 1e16, 1e15, 0.1, -0.0, nan, inf}`. The Go arm reaches `FmtF64` only through `string-from-float64` (`stringFromFloat64` in `rt.ts` port), which is exercised by function-mode cases (`23-numeric-float.json`, `28-string-transforms.json`, `29-literal-floats.json`, `29-literal-signs.json`).

What the corpus exercises concretely:
- `23-numeric-float.json` "the shortest round-trip rendering of a non-terminating quotient" — `9007199254740993 / 2 = 1.8014398509481984e+16` and `(neg 9007199254740992) = -9007199254740992.0` (no exponent). The threshold-spelling case `1.8014398509481984e+16` exercises a value with `exp10 == 16`, which is exactly the boundary the Python repr-vs-`'g'` divergence lives at.
- `29-literal-floats.json`: `floats(2.5)` returns `"1.0|-0.0|-2.5|-1.5"` — `-0.0` is in scope, but `nan` and `inf` are not.
- `28-string-transforms.json`: `string-from-float64 (option-or 0.0)` returns `0.0` for unparsable input — no nan, no inf, no exponent boundary.

A Go `FmtF64` that emits `1.0e+00` (uses exponent notation below the threshold) instead of `1.0` (the Python-repr rule) would pass W2's probe (the probe asserts `FmtF64(1.0) == "1.0"`), but a corpus entry that calls `string-from-float64 1.0` would diverge from python/rust/wasm/interp/ts. Looking at `23-numeric-edge.json` (no floats), `23-numeric-float.json` (covers exp10==16 at 1.8e16), and `29-literal-floats.json` (covers `-0.0`):

What is NOT pinned by any function-mode case:
- A `string-from-float64` of `nan` or `inf` or `-inf`. The corpus has no entry that takes a `nan`/`inf` literal through `string-from-float64`. `23-numeric-minmax.json` has `minmax("nan", "1.0")` returning `"1.0|nan|none"`, but the `"nan"` string here is parsed by `string-to-float64`, not the rendered output of `string-from-float64`.
- A `string-from-float64` of a value just below exp10==16 (e.g. `1e15`). The corpus's `fnum(9007199254740993, 2)` produces `1.8014398509481984e+16` — exp10==16 exactly — but never `1e15` (no explicit `1e15` literal in any case).
- A negative zero passed through `string-from-float64` that exercises a different code path. `29-literal-floats.json` asserts `-0.0` rendering.

**Evidence:**
- `backend/cases/23-numeric-float.json` last case: `"1.8014398509481984e+16"` is the only exponent-spelled value in any function-mode case.
- `backend/cases/28-string-transforms.json:[["0.1"]]`: `0.1` is `exp10 == -1`, far from the threshold.
- `backend/cases/29-literal-floats.json`: `-0.0` only.
- W2's `FmtF64` probe (PLAN.md:230-241) covers `1e16` and `0.1` and `-0.0` and `nan` and `inf` directly via the unit probe — but these are unit probes that run OUTSIDE any corpus execution. A Go `FmtF64` that emits `1e+16` for `1e16` but `1.0000000000000002e+00` for some other value would pass the unit probe and diverge at the corpus level.

**What would make it right:** Either (a) extend `23-numeric-float.json` or `29-literal-floats.json` with cases that exercise `1e15`, `1e17`, `nan`, `inf`, and `-inf` through `string-from-float64`; or (b) commit to the unit probe as the sole enforcement, and state in the plan that no function-mode case pins these specific values — recorded as honest scope. Plan §5 risks (PLAN.md:464-469) acknowledges `FmtF64` port fidelity but does not name which values are corpus-pinned.

### M2 — The plan's monomorphism deferral (D7) leaves entire builtin×instantiation classes unchecked for Go

**Severity:** major.

**What is wrong:** D7 commits to Go not joining `monomorphism.py`. This means every `(builtin, instantiation)` pair that the corpus + differential do not exercise can carry a Go lowering bug undetected. The plan §5 (PLAN.md:478-481) acknowledges this as a Risk and points to a "separate, unclaimed decision" — but the unenumerated class is the whole finding.

Enumerate which `monomorphism.py` probes (excluded-class deductions aside) reach the corpus + differential:
- `monomorphism.py:140-150` generates `len(vars) ^ 3` candidates across `Int32`, `Int64`, `Float64` × `Int64`, `Float64`, `String`, `Bool`. After `tier_a.narrowed` (40 map probes for `Float64` keys, which the checker rejects), the admissible set is `len(admissible) - 40` — `coverage.lock:9` records `"probes": 400` minus narrowed 40 = 360 admissible candidates. Each candidate compiles under rustc + py_compile.
- For Go, `monomorphism.py` does not compile. Acceptance therefore reduces to: `go build` accepts each fixture's emitted source (check_corpus's `go vet` column) AND each differential case's emitted source (differential's `build_go`).

What is NOT exercised:
- `checked-div`, `checked-mod`, `neg`, `abs`, `+`, `-`, `*`, `/`, `mod` at `Int32` alone. The corpus has `int64-to-int32` (which calls `to_i32`) and `int32-to-int64` (which is the `py` template `"{0}"` — no lowering on Go). `Int32` arithmetic lowering: only `29-literals.agentscript`'s `step` (Int32 ↦ Int32, takes an Int32, returns Int32, asserts `-1` / `-2147483648` / `2147483646`). A Go `Add` that takes `int64` and never compiles at `int32` (the generic `T Number` constraint is verified at compile time) would fail compilation only if the corpus uses Int32 arithmetic — which only `step` does. The function-mode task `29-literal-step.json` exercises `step` at Int32. So Int32 arithmetic IS exercised via the differential. But the `monomorphism.py` sweep at Int32 for ALL builtins (not just `+`) is NOT done — the corpus never calls e.g. `(- a b)` at Int32, so a Go lowering for `-` that fails to type-check at Int32 (because the generic constraint or the template substitution is wrong) is undetected.
- `string-to-int64` with the underscore literal `1_0` (`23-numeric-from-float.json` covers `1_0`) — covered.
- `string-to-float64` with non-ASCII decimal digits — not covered. `to_f64("١٢٣")` is NOT in any function-mode case. The corpus's `_parsable` Python check (`backend/runtime.py:154-158`) rejects non-ASCII inputs; the Rust `to_f64` accepts them. The TS `toF64` (rt.ts:280-300) accepts only `[+-]?([0-9]+\.?[0-9]*|…)([eE]…)?` plus non-finite names. A Go `to_f64` that accepts non-ASCII digits would diverge from both Python and Rust silently — the corpus does not exercise this. (`27-string-query.json` has non-ASCII `héllo`, but only as a string predicate input, never as a `string-to-float64` input.)
- All `(string-from-float64)` instantiations on `Int64` and `String` argument types — never called; signature says `Float64 -> String`, so only Float64 is reachable. Not a real gap.
- `option-map`, `result-map`, `result-map-err` with `String -> String` callback type — the corpus has `21-option-result-combinators.agentscript` (covered).

**Evidence:**
- `backend/monomorphism.py:140-180`: admissible set excludes effect/variadic/higher-order/monomorphic; admissible is 400-40 = 360 candidates per the lock.
- `prelude/coverage.lock:64-279`: `instantiations` lists what the Python lowering executed. E.g. `"/" : ["Float64", "Int64"]` — Int32 is NOT executed. Same for `+`, `-`, `*`, `mod`, `checked-div`, `checked-mod`, `neg`, `abs`, `<`, `<=`, `=`, `>`, `>=`. The differential's `23-numeric-int.json` calls `/` at `Int64` only. `23-numeric-float.json` at `Float64` only. The Int32 case for `/`, `mod`, `neg`, `abs` is never run.
- `29-literal-step.json` exercises `+` at `Int32` (one case, `+ n -1`). No Int32 case for `-`, `*`, `/`, `mod`, `min`, `max`, `abs`, `neg`, `checked-div`, `checked-mod`. A bug in any of these at Int32 is uncaught.
- `backend/cases/28-string-transforms.json:[["42"]]`: `string-from-float64 (string-to-float64 "42")` returns `"42.0"`. The TS `toF64` rejects the underscore (rt.ts:286). A Go `to_f64` that accepts `"1_0"` would NOT be caught here, but `23-numeric-from-float.json:[["1_0"]]` would catch it (asserts `some 0|none` — the float side returns `some 0` because `option-or` falls back, but the int side returns `none` because `to_i64("1_0")` rejects). Actually wait: the case asserts `"some 0|none"` where the first column is `float64-to-int64` (parsed 1.0 → 0 from option-or) and the second is `string-to-int64` ("1_0" rejected → none). So the corpus DOES check this, but only at Int64, not Float64.

**What would make it right:** Either (a) commit to `monomorphism.py` extending to Go as a precondition (D7 reversed), with the cost being one more `rustc`-equivalent sweep, or (b) enumerate in §5 Risks the specific (builtin, instantiation) pairs that are unenforced for Go, with a sentence per pair saying what would catch a bug, so reviewers can judge whether the unenforced class is bounded. The plan's current Risks entry is one sentence ("a `go` template whose lowering breaks at a type no corpus fixture or differential case instantiates passes every gate silently, exactly the residual the `ts`/`js` keys carry today") without naming the pairs.

### M3 — The plan's "raise on empty emission" anti-stub rule is preserved as a Python invariant, not as a gate-level assertion that catches every stub shape

**Severity:** major.

**What is wrong:** The plan §anti-stub measures (PLAN.md:120-137) cite "`build_typescript:387-403`" as the model for "raise on empty emission" and "raise on transpile failure". The Python invariant lives at `backend/differential.py:392-403`:

```
if not main_ts.strip():
    raise RuntimeError(f"ts transpile of {src.name} emitted no source")
```

The plan inherits this for `build_go` and `run_go`. But the gate at W7 does NOT assert that an empty emission raises — it asserts only that the gate runs to completion (no FAIL means the gate passed). A `to_go.py` that returns `package main; func main() {}` for every source — non-empty, passes `go build`, prints nothing, exits 0 — produces `seen["go"] = ("", "", 0)`. The python/rust/wasm/interp/ts arms each produce their own output for the same fixture. They will NOT agree on a fixture with non-empty expected stdout (e.g. `13-module-program`'s `"rectangle\n6.0\n"`). The plan's `agree = ...` chain would catch this — disagreement on the FIRST corpus fixture with non-empty expected output. But: the failing-path cases (08-io, 19-io-errors) have empty stdout AND a non-empty stderr. If Go's stub emits `("", "not-found\n", 1)` for `["sample.txt", "nodir/out.txt"]` (matching the failing-path declared stderr by hardcoding it), then `seen["go"] = ("", "not-found\n", 1)` would agree with python's `seen["python"] = ("", "not-found\n", 1)` on the failing-path case AND agree with python's `seen["python"] = ("rectangle\n6.0\n", "", 0)` on `13-module-program` ONLY IF the Go stub also emits `("rectangle\n6.0\n", "", 0)` for that case. A stub that hardcodes `("rectangle\n6.0\n", "", 0)` for that fixture AND `("", "not-found\n", 1)` for the failing case would agree with python on every program-mode case and pass every gate.

The fix would be: a structural assertion that the Go arm's emitted source is non-trivial (more than N lines, or includes `func main` referring to local symbols), or a sentinel in the Go arm's output (e.g. a preamble `// go-arm: stamp`) that the gate greps for. None is asserted.

**Evidence:**
- `backend/differential.py:392-403`: empty-emission raise. Non-empty stub is NOT detected.
- `PLAN.md:128-133`: anti-stub measure 3 says "Raise, never skip" — but the gate is the `agree` chain at `differential.py:417-419`, which only fires if the stub disagrees with python. A stub that hardcodes every fixture's expected output trivially agrees.
- `PLAN.md:475-487`: W7 gate is `assert 'build_go' in s` plus grep `python/rust/wasm/interp/ts/go` — neither prevents the hardcoded-output stub.

**What would make it right:** Either (a) add an assertion that `len(seen["go"]['stdout']) > N` for at least one corpus fixture with a non-trivial expected output, or (b) require the Go arm to emit a per-fixture sentinel (e.g. emit `fmt.Println("go:<fixture-name>")` as the first line, gate greps for it), or (c) cross-check that the Go arm's emitted Go source `len > 100` for at least one fixture. None is in the plan.

---

## Minors

### m1 — The plan claims 107 new `go` keys; the actual prelude builtins count must be verified at implementation time

**Severity:** minor.

**What is wrong:** The plan repeatedly says "107 builtins" and "the widened `validate_templates()` reports no broken `go` template" (PLAN.md:18-20, §3 W1, §3 W1 gate). The prelude has 107 builtins per `prelude/coverage.lock:5` (`"executed": 107`), and `prelude.json` is verified by the gate. The W1 gate is `missing = [b["name"] for b in bs if 'go' not in b]`. This is correct. The minor concern: a `go` template added but with the wrong lowering (e.g. `Add` that compiles but computes `a+b` for ints without overflow trap) passes `validate_templates()` (which only format-checks at declared arity) and passes `go vet` (no analyzer catches runtime overflow). The differential's `num(7, 2)` case exercises `+` at Int64 in the happy range (7+2=9, no overflow); a Go `Add` that silently wraps passes that. The trap is exercised only by `trap-add` / `trap-div` / etc. — and the plan §D3 honest-limit (PLAN.md:73-78) acknowledges "trap-path bytes are not byte-comparable across arms ... no program-mode differential case exercises an arithmetic trap today, and none is added". The differential therefore cannot pin the trap messages. W2's probe pins `Add(int64(1), int64(9223372036854775807))` panics with `"overflow in addition"` and `Div(int64(-9223372036854775808), int64(-1))` panics with `"overflow in division"`. So the two most-load-bearing traps ARE pinned at the unit level. `Sub`, `Mul`, `Neg`, `Abs` traps are NOT pinned — a Go `Sub` that does `a - b` (no trap) would compile clean, pass `go vet`, and not be caught by either gate. The plan §D3 lists these but no probe covers them.

**Evidence:**
- `PLAN.md:230-241`: W2's probe pins `Add`, `Div`, `FmtF64`, `ErrnoToIoError`. Does NOT pin `Sub`, `Mul`, `Neg`, `Abs`, `Rem` traps.
- `prelude.json:79-83`: `Sub`'s docstring is "Difference. Traps on integer overflow."

**What would make it right:** Extend W2's probe to include `Sub(int64(1), int64(-9223372036854775808))` panics with `"overflow in subtraction"`, `Mul(int64(9223372036854775807), 2)` panics with `"overflow in multiplication"`, `Neg(int64(-9223372036854775808))` panics with `"overflow in negation"`, `Abs(int64(-9223372036854775808))` panics with `"overflow in absolute value"`. This is the unit-level analog of what `23-numeric.agentscript`'s `trap-add` etc. are at the differential level, but `differential.py` does not run those (`differential.py:381-481` covers only program-mode corpus fixtures, and `23-numeric` is not in the program-mode list — it's only used by function-mode cases).

### m2 — The plan's `to_go.py` skeletal mapping for the Int32 type is unverified

**Severity:** minor.

**What is wrong:** Plan §D3 names `Int32 → int32`. The corpus's Int32 use is `29-literals.agentscript`'s `step` (Int32 → Int32) and `int64-to-int32` / `int32-to-int64` conversions. `29-literal-step.json` exercises `(Int32) -> Int32`. The transpiler's type mapping at `PRIM` would need `Int32 → int32`. A Go `int32` arithmetic helper that does NOT check overflow (e.g. emits `n1 + n2` directly for `(+ a b)` at Int32) compiles clean, vets clean, and only diverges from the trap-spec at runtime on values that exceed Int32 range — `step` only ever produces `-1` / `-2147483648` / `2147483646`, which are in range; no trap is reached. A Go `int64` arithmetic helper (a single non-generic implementation that always uses int64) would also fail to type-check at `Int32` because Go's strict type system rejects `int64 + int32`. The plan's `Number` constraint (`~int32 | ~int64 | ~float64`) requires a generic helper that type-switches inside. If `to_go.py` emits a non-generic `Add` that takes `int64` alone, the corpus's `step` would fail `go build` (cannot use `int64` for `Int32` parameters) — and that IS caught by `go vet`/`go build` in the corpus column. So this is closed at the build level, not the runtime level.

**Evidence:**
- `PLAN.md:67-77`: D3 names `Int32 → int32`, `Int64 → int64`, `Float64 → float64` and the generic `Number` constraint.
- `29-literal-step.json`: only `Int32` ↦ `Int32` case is `(0, -1)`, `(-2147483647, -2147483648)`, `(2147483647, 2147483646)` — all in range.

**What would make it right:** Plan §W3's gate runs `go vet` on `01-basics.agentscript` (no Int32) — the Int32 type appears only via `step` and the `int*-to-int*` conversions. The plan could add `go build` of a `step`-only fixture to W3's gate to confirm the generic helper compiles at Int32. Recorded as a non-blocking observation: the build path closes this, the runtime trap path is unclosed (caught by m1's probe extension).

---

## "Conformant-but-wrong" enumeration

The plan's central question. For each major work item, what wrong implementation passes every gate?

| # | Work item | Conformant-but-wrong that passes today | Caught by gate? |
|---|---|---|---|
| W1 | 107 `go` templates | A template that compiles but emits the wrong lowering (e.g. `Add({0},{1})` in a Go file that has no `Add`) — caught by `go build`/`go vet` in the corpus column when the fixture is exercised. | Partial — only on the subset of fixtures whose transpile succeeds AND exercise the broken builtin. A `go` template for `string-from-float64` that calls `fmt.Sprintf("%v", x)` instead of `FmtF64` compiles clean and passes vet, and is only caught by the differential's `fnum` cases — `23-numeric-float.json` covers the boundary, `nan`/`inf`/-exp thresholds NOT corpus-pinned (M1). |
| W2 | Complete `rt.go` | An `Add` that does `a+b` (no trap) — compiles clean, vets clean, passes every differential case in the happy range. | Caught ONLY by W2's unit probe for `Add(int64(1), int64(9223372036854775807))` → panic. `Sub`, `Mul`, `Neg`, `Abs`, `Rem` traps NOT pinned (m1). |
| W3 | `to_go.py` skeleton | A transpiler that emits `package main; func main() {}` for every source — non-empty, vets clean. | Caught by the differential agree-chain on every fixture with non-trivial expected output (B1). NOT caught on a fixture where every arm agrees trivially (e.g. 08-io happy path: stdout `""`, stderr `""`, exit 0). |
| W4 | Module linking | A `link()` that emits a single root file and discards imports — vets clean. | Caught by 13-module-program (program-mode differential requires the imported Shape's match arm to lower correctly) and by the corpus column's `go vet` on fixtures 06, 09, 10, 11, 12, 13, 15. |
| W5 | Failing I/O path | An `ErrnoToIoError` that maps every error to `not-found` — passes W5's gate (08-io failing write asserts `not-found`). | Caught only by the two failing-path cases (`not-found`, `permission-denied`); `already-exists`/`invalid-path`/`interrupted`/`other` are unmapped at the differential level (B4). |
| W6 | `go vet` corpus column | A transpile that returns an empty string for an unhandled form, so `go vet` sees nothing. | NOT caught — `check_corpus.py:88-91` only invokes `go vet` after `transpile` succeeds; an empty `transpile` result is the same as a transpile fail (both log "FAIL"). The plan does not propose to break this. |
| W7 | Six-arm differential | A `build_go` that hardcodes every fixture's expected stdout/stderr/exit — agrees with python trivially, exits 0. | NOT caught — no per-arm execution counter, no structural assertion that the Go arm ran distinct code (B1). |
| W7 (function mode) | Go function-mode arm | Same: a `run_go` that returns the rust arm's output. | NOT caught — same hole as B1. The plan §D1 commits to "Go becomes a sixth arm in both modes, fully participating" but does not name a per-arm-run gate for function mode. |

---

## Verified

- `PLAN.md:18-20`: acceptance 3 names the six-arm summary. Verbatim.
- `backend/differential.py:417-419`: agree expression is across the five named runners; adding `go` requires editing this line. Verified by reading.
- `backend/differential.py:436-446`: program-mode cases for `19-io-errors` — `argv: ["nodir/out.txt"]` (not-found) and `argv: ["noperm.txt"]` (permission-denied) are the only failing-path entries. Verified.
- `backend/differential.py:392-403`: TS twin's empty-emission raise. The plan inherits this shape for Go. Verified by reading.
- `backend/golang/rt/rt.go`: contains `Div`, `Rem`, `FmtF64` (line 100) but NOT `Add`, `Sub`, `Mul`, `Neg`, `Abs`, `ErrnoToIoError`, `IoError`, `MainExit`, `ReadLine`, `ReadAll`, `PrintOut`, `Println`, `Eprintln`, `FileRead`, `FileWrite`, `FileAppend`, `FileExists`, `Thrown`. The current `Div` (line 33-38) does NOT trap on `MinInt64 / -1` — verified by running the W2 probe verbatim, which fails on `undefined: Add`, `undefined: ErrnoToIoError`, and `undefined: syscall.PathError`.
- `prelude.json:1153`: `file-exists?` returns `RT.ok(RT.fileExists({0}))` — TS wraps a `boolean` into an `ASResult`. The plan's Go port must mirror this; the live `runtime.py:333` `file_exists` returns `Result<bool, IoError>`. The TS shape is the precedent the plan names (D1).
- `backend/to_typescript.py:445-449`: `try` inside `fn_form` raises `NotImplementedError`. The plan does not name whether `to_go.py` follows the same rule.
- `prelude/coverage.lock:64-279`: `instantiations` lists what Python executed; `Int32` is NOT in any arithmetic instantiation.
- `grammar/corpus/valid/14-sequenced-bodies.agentscript:30-39`: `in-lambda` is bare-effect only, no `try` inside the lambda body. Verified by reading.
- `backend/cases/23-numeric-float.json`: contains the `1.8014398509481984e+16` exponent-spelled value, the `2.3333333333333335` shortest-round-trip value, and the `9007199254740993` 2^53+1 boundary. Verified by reading.
- `backend/cases/29-literal-floats.json`: contains `-0.0` rendering. `nan`/`inf`/`-inf` rendering NOT covered. Verified by reading.

## Unverified

- Whether `to_go.py`'s `defenum` lowering with positional type assertions handles nested generic enums (e.g. `(Tree Int64)`'s `node v l r` with `l: Tree Int64`). The corpus has `10-imported-generic-types.agentscript` (matches `t/leaf`, `t/node v l r`) — function-mode task not present. No gate covers this.
- Whether the W2 probe's `mustPanic("overflow in addition", …)` actually receives `fmt.Sprint(r)` formatted exactly that way from a Go panic. The current `rt.go` has no `Add` to panic from. Verified empirically via W2 probe verbatim (just executed it): the current rt.go lacks `Add` entirely, the probe fails on `undefined: Add` long before reaching any panic check.
- Whether `go vet` accepts a Go source file that defines `package main` without `func main` when compiled alongside a file that defines `func main`. The plan §D1 (PLAN.md:27-32) claims `go vet` accepts this; the W3 gate uses `(cd "$d" && go vet main.go rt.go $( [ -f zzmain.go ] && echo zzmain.go ))` — when `zzmain.go` is present, `go vet` sees the main; when absent, `go vet` sees a package with no `main`. The plan §D1 claim that "go vet accepts a `package main` with no `func main` (exit 0)" is unverified in the plan itself but is the structural assumption.
- Whether `errors.As(&syscall.Errno)` successfully unwraps `*os.PathError` from `os.Open`/`os.ReadFile`/`os.WriteFile` on macOS and Linux. The plan §D5 commits to this. The unit probe (PLAN.md:230-241) tests `errors.As` against `&syscall.PathError{Err: syscall.ENOENT}` directly, which sidesteps the unwrapping-from-os question. The actual file ops produce `*os.PathError` wrapping `syscall.Errno`, and `errors.As` traverses the chain. The plan's probe does NOT exercise that chain — only direct injection.
- Whether the differential `programs()` accepts the Go arm's output format from a corpus fixture whose program returns `(Result Unit IoError)` and writes to stdout via `(try (println …))`. The plan §W7 commits to `MainExit(Main_(os.Args[1:]))` (PLAN.md:265) but the differential harness invokes the binary with `argv` and captures stdout/stderr — the wrapping through `MainExit` produces exit 1 + stderr `not-found\n` for failing cases, which is the byte-for-byte check. The wrapping is unverified by W7's gate (only `assert 'build_go' in s`).

## Risks (carry-forward to the implementation phase)

- **Differential six-arm enforcement.** No per-arm execution counter or non-trivial-output assertion. A `build_go` that hardcodes every fixture's expected output passes every gate (B1).
- **try-in-lambda behavior.** Plan D4 is silent. TS raises; the plan does not commit to the same. A go-side lambda with `try` that uses deferred `recover()` would silently mis-convert arithmetic panics to Result failures (B2).
- **defenum positional type assertions.** Wrong assertions compile clean, vet clean, and panic at runtime only on unexercised patterns. The corpus's `defenum` match coverage is small (B3).
- **Four IoError cases unmapped at the differential level.** `already-exists`, `invalid-path`, `interrupted`, `other` are pinned only by W2's unit probe, which covers `ENOENT → not-found` and `errors.New → other` only (B4).
- **FmtF64 exponent thresholds.** `1e15`, `1e17`, `nan`, `inf`, `-inf` are not pinned by any function-mode case (M1).
- **Int32 arithmetic across all builtins.** Only `+` is exercised at Int32 in the differential (`step`). `Sub`, `Mul`, `Div`, `Mod`, `Neg`, `Abs`, `min`, `max`, `checked-div`, `checked-mod` at Int32 are unexercised (M2).
- **Stub detection.** A non-empty stub (e.g. `package main; func main() { fmt.Println("rectangle\n6.0") }` for every source) passes `go vet` and agrees with python trivially if the stub hardcodes the expected output (M3).
- **Trap messages for `Sub`, `Mul`, `Neg`, `Abs`.** W2's probe covers `Add`, `Div`. The other four traps are pinned only at the unit-level shape (the probe asserts the trap exists, not the message). Actually verified: the probe asserts `mustPanic("overflow in addition", …)`. A `Sub` whose trap message is `"overflow in subtraction"` would also compile and run; the probe does NOT verify `Sub` panics at all (m1).
- **`errors.As` chain on `*os.PathError`.** The unit probe injects `*syscall.PathError` directly, not via `os.Open`. Real file-op failures are not unit-tested for the unwrap path. Recorded as a Plan §5 risk; the implementation must verify on a real file op.

## Highest-value finding

**A `build_go` that hardcodes every fixture's expected stdout/stderr/exit (or runs the python arm's binary) agrees with python trivially, exits 0, and passes every gate the plan proposes — there is no per-arm execution counter, no structural assertion that the Go arm ran distinct code, and the summary string grep and the `assert 'build_go' in s` check both pass on a forwarding/stub arm (B1).**
