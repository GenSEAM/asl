# Phase 5 Plan Review — Design / Spec Consistency

## Lens

Review the plan's treatment of language semantics: that §2.5's bullets are faithful to `AGENT_SPEC_CORE.md` and to the two existing runtimes (`backend/runtime.py`, `backend/rust/rt.rs`), and that §2.3's dispatch list is complete against `grammar/tree-sitter-agentscript/grammar.js`.

## Verdict

`approve-with-amendments`

The plan is technically faithful to the specification and the two existing runtimes on every clause I verified; the deferrals in §1 are sound given the corpus and the gate's design. The defects below are loose citations and one real semantic narrowness (numeric literal width) that the corpus happens not to exercise.

## Blockers

None. The plan does not assert anything that is wrong in a way the acceptance gate would let pass.

## Majors

### 1. Plan does not name the corpus's `Int32` narrowness, and the I2 heredoc does not exercise it

The plan's §2.5 "Numeric widths & traps" bullet says "unsuffixed int is Int64 unless the called function's declared signature says Int32, and an out-of-width literal is an error (§3: 'static error')." It treats Int32 as a degenerate case of the same rule and pins Int64 traps in I2. But `AGENT_SPEC_CORE.md` §3.1 treats Int32 and Int64 as siblings — the trap is at the operand type, not at Int64 specifically. The corpus has one Int32 entry point: `29-literals.agentscript`'s `step` (`Int32` arithmetic at the boundary) is asserted by a `; run:` header that runs against the **Python lowering**, where `Int32` arithmetic is unbounded Python integer arithmetic (`backend/to_python.py:351-359` emits a `LOWER`-templated op with no width check). The interpreter gets this right by accident only because `step`'s expected output (`-1` from `0`) does not cross the Int32 boundary.

The plan does not flag this. If the interpreter matches the Python oracle (`-1` after `step(0)`) it can do so while emitting unbounded arithmetic at `Int32`, and still pass the gate on this fixture. The Int64-trap-pinning heredoc in I2 does not catch that case because the heredoc is Int64 throughout.

Fix: add an `Int32`-typed heredoc to I2 (e.g. `(+ n 1)` at `2147483647` with `Int32` n, declared in a heredoc only), so the interpreter has to trap. Or accept the gap and record it in §5 Risks.

Evidence: `AGENT_SPEC_CORE.md` §3.1; `backend/to_python.py` `LOWER` table emission (single template per builtin, type-agnostic); `grammar/corpus/valid/29-literals.agentscript:78-81` (`step` returns `-1` from `0`, never crosses the boundary); `ROADMAP.md` §6 "`l-4d92`" gap ("`Int32` ignores the width").

### 2. The I8 gate re-greps a string the plan may change

Section 4 has:

```
.venv/bin/python backend/differential.py 2>&1 | grep -q 'interp'
```

But the existing summary line in `differential.py:455-456` is `f"\n{bad} disagreement(s) across {cases} function cases + {program_total} program cases (python/rust/wasm)"`. The plan claims (in §2.2 and the I8 invariant table) the summary line "names four arms" after the change. The plan's gate `grep -q 'interp'` will pass if **any** string in the output contains `interp` — including the `interp` substrings inside `diff -u` of `(empty?)`, `builtin`, `differs`, etc. The gate does not actually verify the summary names four arms. If the implementation forgets to update the summary line, the acceptance gate stays green.

Fix: tighten the grep. Either `grep -q 'python/rust/wasm/interp'` (the four-arm literal) or `grep -Eq 'cases \(python/rust/wasm/interp\)'` so the specific summary format must be present. (Note: the plan's gate as written would not catch a missing summary-line update; this is the gate the plan will actually run.)

Evidence: `backend/differential.py:455-456` (summary line text); the `interp` substring is present in many Python stdlib identifiers at lower-case positions and inside `diff -u`-style error output.

## Minors

### M1. Citation `differential.py:327-330` for the table header is off by 8 lines

Plan §2.2 says "the table header and per-case row (`differential.py:327-330,366-371`)". The actual table header is at line 336 (`print(f"\n{'argv':<20} {'python':<20} {'rust':<20} {'wasm':<20} {'stderr':<18} exit")`). Lines 327-330 are the `stderr is compared unconditionally` docstring lines. The per-case row at 366-369 is correct. The header position is purely cosmetic, not load-bearing for I8 — the table header is currently four-arms and would become five-arms (`interp`), so the plan will edit the right line, but the citation points at prose rather than the line itself.

Fix: change to `differential.py:336,366-369`.

### M2. Citation `differential.py:282-318` for the `build_*` insertion area is shorter than the actual range

The `build_python`, `build_rust`, and `build_rust_wasm` functions in `differential.py` span lines 282-322, not 282-318. The plan asks for a `build_interpreter(src, d)` to be added "beside" them; the spot is right; the upper bound is off by 4 lines. Cosmetic.

### M3. Plan does not specify how `args` is passed for the program mode test driver

Plan §2.4 says `agentscript-interp SOURCE [args...]` and that argv reaches `main` as `(List String)` like `to_rust.py` `host_entry`'s `std::env::args().skip(1).collect()`. The plan does not state what happens when `args` contains characters that would be split by a shell — fine in a heredoc, less fine in `I2`'s heredoc that passes a path. Not a correctness issue; will work for the heredoc inputs the plan writes.

### M4. Plan's `target/` and `grammar/tree-sitter-agentscript/src/` gitignore citations are correct

Verified: `.gitignore:4` is `target/`, `.gitignore:5` is `grammar/tree-sitter-agentscript/src/`. ✓ No fix needed.

### M5. Plan's `parser.c:9` LANGUAGE_VERSION 14 citation is correct

Verified: `grammar/tree-sitter-agentscript/src/parser.c:9` is `#define LANGUAGE_VERSION 14`. ✓ No fix needed.

## Verified (positive findings — these need no rework)

1. **§2.5 Numeric widths & traps**: faithful to `runtime.py` and `rt.rs`. `INT64_MIN/MAX`, `_int`, `_trunc_div`, `MIN mod -1 = 0`, `checked_div`/`checked_mod` all match the spec and both runtimes. Evidence: `backend/runtime.py:46-100`, `backend/rust/rt.rs:31-62`, `AGENT_SPEC_CORE.md` §3.1.

2. **§2.5 NaN total order**: `runtime.py order_key` (line 113), `rt.rs nan_last` (line 91), `sorts_before` selection — both runtimes implement the spec's "NaN-holding values last, tie with each other, stable". Plan faithful. Evidence: `AGENT_SPEC_CORE.md` §3.2; `runtime.py:113-126`; `rt.rs:85-103`.

3. **§2.5 Equality (NaN ≠ NaN inside containers)**: `runtime.py eq` (lines 102-111) spells out the float/composite cases; `rt.rs` uses `BTreeMap` which holds `NaN`-bearing values but `Eq`/`Ord` traits are not derived for `Float64`-keyed maps (gap pinned by `map-key-order`). Plan's claim that this lives in the spec §3.2 is correct. Evidence: `runtime.py:102-111`; `AGENT_SPEC_CORE.md` §3.2.

4. **§2.5 Formatting**: `rt.rs fmt_f64` ports the three corrections (NaN case, signed exponent, ≥2 exponent digits) to make Rust's `{:?}` agree with Python's `repr`. Plan faithful. Evidence: `rt.rs:126-140`; `29-literals.agentscript` `floats` case is what pins `0.0`, `-0.0`, `-2.5`, `-1.5`.

5. **§2.5 Conversions**: `runtime.py _parsable` (line 215) checks `isascii()` and no `_`; `rt.rs to_i64`/`to_f64` use bare `parse()`, which does NOT match — the Rust runtime in fact accepts what Python rejects. **The plan's claim that the Rust `parse` accepts more than the language is correct, but the Rust side does not currently enforce `_parsable` — this is a known gap in `rt.rs` (not the plan's invention).** The interpreter must enforce `_parsable` to agree with the Python side, which the plan explicitly says. Evidence: `runtime.py:215-216`, `rt.rs:147-148`, `AGENT_SPEC_CORE.md` §6.4.

6. **§2.5 Maps**: BTreeMap in Rust and `sorted(m)` in Python — both sorted iteration. Plan's "Float64 not a legal key (checker `map-key-order` owns it)" claim verified: `checker/types_.py:map_key_rules` enforces it (per `ROADMAP.md` §6 bullet on map-key-order). Evidence: `rt.rs:5` (BTreeMap doc comment); `runtime.py:258`.

7. **§2.5 Strings**: indices in characters — `rt.rs str_len` uses `chars().count()`, `str_slice` uses `chars().skip/take`. Plan faithful. Evidence: `rt.rs:106-122`.

8. **§2.5 I/O + IoError**: `rt.rs io_err` maps `NotADirectory | IsADirectory` → `InvalidPath` (line 244-246), `runtime.py _ERRNO` maps errno 20/21 → `invalid-path` (line 264). Both runtimes agree. Evidence: `rt.rs:240-249`; `runtime.py:263-265`.

9. **§2.5 Exit glue**: `rt.rs main_exit` (line 286-291) returns 0/1 with case name on stderr; `runtime.py main_exit` (line 339-356) returns 0/1 with case name on stderr; both reject non-Result shapes (Rust at type level, Python by explicit check). Plan faithful. Evidence: `rt.rs:286-291`; `runtime.py:339-356`.

10. **§2.5 Modules**: `modules.py:44-71` `closure` walks imports depth-first, dedupes via `seen`, emits dependencies first. Cycle handling: not diagnosed, broken. Plan faithful. Evidence: `grammar/modules.py:44-71`; `AGENT_SPEC_CORE.md` §9 rule 11.

11. **§2.5 Module identity**: keying globals by defining module path — `to_python.py:46-50` `module_prefix` docstring and `to_rust.py:70-76` `rust_mod` docstring both state "Derived from the module path that DEFINES a member, never from the alias". Plan faithful. Evidence: `to_python.py:46-50`; `to_rust.py:70-76`.

12. **§2.5 Enum/runtime tags as bare case names**: `to_python.py:103-117` `decl_name` records cases as `prefix + mangle(case)`; `to_rust.py:303-309` emits `pascal(case)` variant names. The plan's claim "stays bare case name across boundaries" is correct for tag identification, though Rust emitted name is `PascalCase`. The interpreter should preserve bare case names because both backends compare them as strings (Python tag literal, Rust enum variant `case()` method). Evidence: `to_python.py:201-209`; `to_rust.py:369-376`.

13. **§2.5 Scope & sequencing**: lexical frames, shadowing, `let*` sequential — `to_python.py:96-99` `push`/`pop`/`bound`, `to_rust.py` mirrors. `try` returns from enclosing defun — `AGENT_SPEC_CORE.md` §5.5 says "not inside an `fn`". Plan faithful. Evidence: `to_python.py:96-99`; `AGENT_SPEC_CORE.md` §5.5.

14. **§2.5 `and`/`or` short-circuit**: spec §5.6 says so; both backends emit Python `and`/`or` and Rust `&&`/`||`, which are short-circuit. Plan faithful. Evidence: `AGENT_SPEC_CORE.md` §5.6; `prelude/prelude.json` `LOWER` templates for `and`/`or`.

15. **§1 Out-of-scope: field `:default` application**: both backends ignore `:default`. `to_python.py:188-193` `defschema` method emits a constructor that requires every field; `to_rust.py:351-365` emits a struct with every field as `pub`, no `Default` impl. Plan's deferral is consistent with both. No program-mode corpus fixture omits a defaulted field: `01-basics.agentscript:11` (Config with `:default 3`) and `29-literals.agentscript:21` (Cursor with `:default -1`) both always supply the field. Evidence: `to_python.py:188-193`; `to_rust.py:351-365`; `grammar/corpus/valid/01-basics.agentscript`; `grammar/corpus/valid/29-literals.agentscript`.

16. **§2.3 Dispatch list completeness against `grammar.js`**:
   - `_expr` alternatives in `grammar.js:120-135`: `_literal, ident, qualified, operator, let_form, if_form, cond_form, match_form, try_form, fn_form, constructor_call, ctor, field_access, call` (14 total).
   - Plan §2.3 names: `_literal` (terminals), `ident`, `qualified`, `operator`, `let_form`, `if_form`, `cond_form`, `match_form`, `try_form`, `fn_form`, `constructor_call`, `ctor`, `field_access`, `call`. All 14 covered.
   - `_pattern` alternatives in `grammar.js:201-211`: `ok_pattern, err_pattern, some_pattern, none_pattern, list_pattern, cons_pattern, pair_pattern, enum_pattern, _literal, ident, wildcard`. Plan names: `ok_pattern err_pattern some_pattern none_pattern list_pattern cons_pattern pair_pattern enum_pattern, plus literal/ident/wildcard`. All 11 covered.
   - `_type` alternatives in `grammar.js:118-120`: `type_name, qualified_type, type_app`. Plan names: `type_name, qualified_type`. `type_app` is unmentioned. **Minor gap**: `type_app` appears in type positions only; the interpreter does not evaluate types — but if a `defun`'s `return_type` is a `type_app` like `(List Int64)`, the interpreter needs to recognize the node and treat it as a non-value. Currently the plan's dispatch list does not name `type_app`. Evidence: `grammar.js:118-120`; `grammar.js:108` (`type_app` referenced in `_type` rule).

17. **§2.5 `string-from-int64` plain decimal**: both `runtime.py add`/`sub`/etc. and `rt.rs fmt_i64` use `n.to_string()`. Plan faithful. Evidence: `rt.rs:143`.

18. **§2.5 Conversions `string-to-int64`/`string-to-float64` reject non-ASCII and `_`**: `runtime.py _parsable` (line 215) enforces this; `rt.rs` does NOT — already noted above. Plan's claim that "Rust's bare `parse()` accepts unicode digits Python's gate rejects" is accurate and the plan says the interpreter must enforce it. Evidence: `runtime.py:215-216`; `rt.rs:147-148`.

19. **§2.5 I/O + IoError**: `read-line` returns `(some line)` without trailing `\n`, `(none)` at EOF — both `runtime.py read_line` (line 283) and `rt.rs read_line` (line 252) match. Writes flush — both runtimes call `.flush()` / `write_to` flush. Plan faithful. Evidence: `runtime.py:283-289`; `rt.rs:251-263`.

20. **§2.5 Exit glue "reject any other shape"**: `runtime.py main_exit` raises `TypeError` (line 339-356); `rt.rs main_exit` is type-system-level (Result<(), IoError> only). Plan faithful. Evidence: `runtime.py:339-356`; `rt.rs:286-291`.

## Conformant-but-wrong — what could pass the acceptance gate while still being wrong

The acceptance compares stdout, stderr, and exit status across four arms (python/rust/wasm/interp) AND against the declared `want` value. The plan correctly observes that agreement alone can miss a defect two implementations share, and uses the Python oracle to provide a third witness. The concrete shapes that could pass the gate while still being wrong, on the semantics I reviewed:

1. **Integer width at Int32**. The interpreter could implement `Int32` arithmetic using unbounded `i64` or even `i32::wrapping_*` and still agree with the Python oracle on `step(0) == -1`. The gate compares stdout (`-1`) and exit; a wrapping `Int32` would produce the same `-1` from `0`. Pinned only by the absence of an Int32 boundary case in the corpus. (See Major 1.)

2. **NaN sort stability with multiple NaNs**. `25-list-aggregation.agentscript` likely has the canonical NaN-key case. If the interpreter sorts by `partial_cmp` alone (rather than implementing `nan_last`), a list with one NaN still ends up last (Rust's `sort_by` will panic on incomparable pairs unless the comparator handles them), but a list with two NaNs could end up on opposite sides or in arbitrary order. If the corpus does not exercise two-NaN lists with a non-trivial comparator, the gate will not catch this. The plan's Risk 5 names the stability requirement but does not pin a test with two NaN values.

3. **`_parsable` not enforced on the interpreter**. The interpreter could use Rust's `parse()` directly and still match Python on the corpus (because `string-to-int64` corpus inputs are clean ASCII). Pinned only by corpus coverage; would fail on a hostile input like `"١٢٣"` or `"1_000"`. The plan's Risk 4 names this but no fixture pins it.

4. **Trap propagation through `try`**. The interpreter could swallow a trap and return a default `none` from `try` rather than unwinding, and still match the Python oracle on every fixture that does not exercise the failing path. The corpus's `08-io.agentscript` exercises the failing `try` path (file-write to `nodir/out.txt`), but the I/O error mapping is what makes that fixture pass — a `try` that swallowed traps would still surface the I/O error through the surrounding `match`. The gate does not have a fixture where a trap happens inside `try` and unwinds to a defun.

5. **Map key order on the interpreter**. If the interpreter iterates a `BTreeMap<_, _>` whose keys are `String`, that iterates codepoint order (correct), but if it uses `HashMap<String, _>`, iteration order is hash-bucket order. The corpus probably does not pin a multi-entry map's iteration output with a non-trivially-ordered key set. (The plan's I5 gate loops over `26-map-lifecycle` — would need to verify this fixture has an order-sensitive assertion.)

## Risks (unverified)

1. **`checker/gate.py` passes right now, but the corpus is checker-clean by ROADMAP §2.** Confirmed by running `.venv/bin/python checker/gate.py` (exit 0, "0 failure(s)") and `.venv/bin/python backend/check_corpus.py` (exit 0). However, my run was at the current working tree, not at the I0 baseline the plan will record. If a later commit breaks a fixture, I0 will surface it.

2. **`backend/differential.py` line numbers shift.** The plan cites line numbers that match the file as currently checked in. If I8 is implemented before any other line-shifting change, citations hold.

3. **`type_app` in type positions**. I noted the plan's dispatch list does not name `type_app`, but I did not verify that any program-mode fixture uses a non-trivial type-app in a position the interpreter must traverse (e.g. `(List Int64)` as a parameter type). If the interpreter only walks `type_name` and `qualified_type` and stops at the first error, that may be acceptable since types are erased at runtime — but the plan should state this rather than leave it implicit.

4. **Float64 keys in containers (e.g. `Map<Float64, V>`)**. The plan defers to `map-key-order` but does not name what the interpreter does when it encounters such a map at runtime. `BTreeMap<f64, _>` does not compile in Rust, so the Rust backend rejects it; the Python backend lowers it to `dict[float, _]`, which silently accepts `NaN` keys (which then become unfindable). The interpreter's choice here is unconstrained by the gate because the corpus does not exercise it (per `map-key-order` rule).

5. **The plan's I8 gate `grep -q 'interp'`** (already filed as Major 2) is loose enough to pass on a non-update.
