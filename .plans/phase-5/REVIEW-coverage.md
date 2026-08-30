# Review — Phase 5 plan · coverage lens

**Lens.** Coverage of `grammar/corpus/valid/*.agentscript` by the plan's work items, and the oracle strategy that pins what each item must produce.

## Verdict

**reject**

The plan fails the conformant-but-wrong test for one fixture on its acceptance text, leaves three classes of behaviour that are documented defects of the existing arms (`l-4d92`, `l-5c47`, string escapes) without a hand-pinned oracle, and the only oracle the plan derives (I0 from the Python lowering) is exactly the source of the shared defects — making the gate blind to regressions the spec's authors already know about.

## Findings

### B1 — blocker · fixture `29-literals.agentscript` is in the I3 corpus group but the plan never drives it from a `main`

`PLAN.md` §3 I3 says it runs the single-module fixtures `01, 03, 04, 05, 07` against `ORACLES.md`. Fixture 29 (`grammar/corpus/valid/29-literals.agentscript`) has **no `main`** — the module exports `signs`, `floats`, `near`, `step` and the plan itself flags this in §1's "Out of scope" paragraph: "field `:default` application at construction — the interpreter matches the backends: omitting a defaulted field is a runtime failure." The plan admits 29 is a corpus file but lists it only in I5's builtin-vocabulary group ("29-literals" inside I5's `for f in 16-recursive-schema … 29-literals` loop).

Re-read I5's gate verbatim (`PLAN.md:174`):

```
for f in 16-recursive-schema 17-nested-cons 20-option-result-ctors … 29-literals; do
  $B grammar/corpus/valid/$f.agentscript >/tmp/out.$$ || true
  diff -u <(.venv/bin/python .plans/phase-5/oracle.py $f) /tmp/out.$$ || exit 1
done
```

Each such `$B grammar/corpus/valid/$f.agentscript >/tmp/out.$$` runs the file as a program. Files 16, 17, 20, 21, 22, 24, 25, 26, 27, 28, 29 (which I just read at `grammar/corpus/valid/29-literals.agentscript:1-3` — no `(defun ! main …)`) have no `main`, so `$B` exits 0 with empty stdout per §2.4 ("File without a `main`: exit 0, no output"). The diff against an oracle that depends on the file's exported entry will pass trivially, or fail against an oracle that expects the entry's output. **No item in the plan attaches a generated `main` driver to 29 the way I3's gate does for 01/03/04/05/07** ("their exported entries wrapped in a generated `main` driver checked into `.plans/phase-5/`").

That is the conformant-but-wrong shape the lens asks for: a `for f in …; do $B $f.agentscript; done` loop over 29 produces "exit 0, stdout ''", and an oracle entry that emits the same `""` makes the gate green while the interpreter has never executed the literal `-0.0`, the literal `9223372036854775807`, the negative literal as a match pattern, the field-defaulted record construction, or the `Int32` arithmetic in `step`.

The same shape repeats for I6 (`06, 09, 10, 11, 12, 15` — `09`, `10`, `11`, `12` are single-export module programs without `main`; only `06` and `13` declare `main`, and `13` is not in I6's loop), and for I3 the five fixtures listed are the only ones of the 14 non-main fixtures that are actually driven by the gate.

**Evidence.** Read every fixture header. `01-basics.agentscript:1-2` (no `main`, function-mode), `03-strings.agentscript:1-2` (no `main`), `04-longest-run.agentscript:1-2` (no `main`), `05-constructors.agentscript:1-2` (no `main`), `07-lambda-elision.agentscript:1-2` (no `main`), `09-imported-types.agentscript:1-2` (no `main`), `10-imported-generic-types.agentscript:1-2` (no `main`), `11-name-coexistence.agentscript:1-2` (no `main`), `12-transitive-use.agentscript:1-2` (no `main`), `29-literals.agentscript:1-3` (no `main`). I3 covers the first five; I6 covers four module-but-no-main programs (`09, 10, 11, 12`) by the same `for` loop — the `06-module.agentscript:1-3` *does* declare `main` and `15-shadowed-binders.agentscript:1-4` *does* declare `main`. The remaining no-main fixture `29-literals.agentscript` is in I5's loop without a driver.

**Fix.** Either add `29-literals.agentscript` to I3 with a generated `main` driver (the same trick the plan already uses for the others, since `signs`/`floats`/`near`/`step` are exactly the entries `backend/cases/29-literal-*.json` and the function-mode differential case already drives), or rewrite I5's loop the same way. The acceptance text says "every `grammar/corpus/valid/*.agentscript` program executes" — "executes" reads as "evaluates the entry", not "exits 0"; the gate has to enforce that reading.

### B2 — blocker · plan's I0 oracle shares the Python backend's defects; the spec records three of them by name and the plan names none

The plan's central oracle (§3, intro): "An item whose fixture outputs are not yet written down records them in `.plans/phase-5/ORACLES.md` in I0 — a gate comparing two implementations that share a defect is blind; the written value is the third witness." But the only "third witness" the plan actually invokes is `.venv/bin/python .plans/phase-5/oracle.py $f` — that *is* the Python lowering. There is no third human-written witness; the plan transpiles with `to_python.py` and runs under `backend/runtime.py` (the same lowering the python arm uses) and calls that oracle "checked-in".

The spec already documents three defects where Python and Rust disagree by construction, and the plan inherits them by deriving its oracle from the one side that is wrong:

* **`l-4d92` (Int32 width)** — `ROADMAP.md:243-263`. `(defun bump [(n Int32)] -> Int32 (+ n 1))` at `2147483647` answers `[2147483648]` on Python and traps on Rust. The corpus file `23-numeric.agentscript` exercises **Int64 traps by construction** (header line: "The Int64 boundary is the second half: the type is fixed, so an operation whose result leaves it traps rather than widening"); the only Int32 surface in any valid fixture is `(defun step [(n Int32)] -> Int32 (+ n -1))` at `grammar/corpus/valid/29-literals.agentscript:63` — a non-overflowing `+` where no width behaviour matters. **No fixture exercises Int32 overflow at all.** `backend/cases/23-numeric-int.json` (read above) is Int64 only. The plan's I2 gate only tests `Int64 +` overflow (`9223372036854775807 + 1`) and `Float64 /` (`-3.0 / 2.0`). **The interpreter could implement Int32 arithmetic as unbounded Python integers (the bug Python has today) and pass every gate, including B1's "executed" reading if it is fixed.**
* **`l-5c47` (list-sort over user unions, records, Maps)** — `ROADMAP.md:281-288`. Python and Rust sort by different fields and one side raises `TypeError` on records. Fixture `25-list-aggregation.agentscript:1-4` exercises NaN ordering at Float64, which the plan gates by `backend/cases/25-list-nan-keys.json` (the rank function with `-nan,nan` input). **It does not exercise sorting a user `defenum`, a record, or a `Map`.** No case in `backend/cases/` sorts a user type. The interpreter's sorting is therefore only pinned for Float64 NaN. A user-union sort would also need to be addressed by §2.5's claim "NaN-holding values last, tie with each other, stable; `min`/`max`/`list-min`/`list-max` select by that order" — that sentence says nothing about how a user `defenum` or a record orders. The plan accepts this without naming the gap; the corpus's own oracle (`rank`) sorts `String` keys, not user types.
* **String escapes** — `PLAN.md` §5 risk 11 names this: "no corpus fixture contains a `\"`/`\\`/`\n` escape; I2's heredoc gate pins `\n` and `\\` unescaping explicitly, else the defect ships invisible." Confirmed by `Grep pattern="\\\\n|\\\\t|escape|unescape|\\\\\"" path=grammar/corpus/valid` → `No matches found`. The heredoc pins two of the five escapes (`\" \\ \n \t \r \0` per §2.5); `\r`, `\t`, `\0` and `\"` are uncovered. A passing-but-wrong interpreter that implements `\n` correctly and treats `\t` as two characters would still pass.

**Evidence.** `ROADMAP.md:243` ("Every operation at `Int32` ignores the width, because the Python lowering table is keyed on the builtin name alone"), `ROADMAP.md:281` ("`list-sort` over a user union, a `Result` or a record orders by different things on each backend"), `PLAN.md:243-244` (risk 11), `PLAN.md:248` (the plan's "third witness" line).

**Fix.** Pin each named defect to a hand-written expected value in `ORACLES.md` (not derived from the Python lowering): an Int32 trap case (e.g., a fixture or heredoc asserting `(+ 2147483647 1)` traps with a specific stderr/exit), a user-union sort case (a hand-picked `(defenum Tag …)` whose declaration order disagrees with Python's name order), and the four remaining escape codes. The acceptance text "every `grammar/corpus/valid/*.agentscript` program executes under the interpreter and agrees with python/rust/wasm" cannot be achieved if the plan does not enumerate the cases where python/rust/wasm already disagree — and it has not.

### B3 — major · the 120 function-mode differential cases are not covered, and PHASES.md acceptance overreaches vs. the plan's own admission

`PHASES.md` Phase 5 acceptance: "*Acceptance:* `corpus/valid` programs execute under the interpreter and agree with the compiled arms via `differential.py`." This phrasing is program-mode — the file is `corpus/valid` and the verb is "execute". The plan narrows that to "function mode is out of scope this phase" (`PLAN.md:5` and risk 10, "`backend/cases` and `bench/tasks` together hold the 120 function cases the interpreter's agreement on pure entry returns is not pinned by").

That is consistent. The gap is that the **acceptance text in PHASES.md is not amended to say so**; the plan footers the difference as "flagged as a Phase-5 follow-up or Phase-9 item, decision for the orchestrator", leaving a reviewer of the orchestrator's acceptance battery unable to tell whether the 120 function cases are owed by Phase 5 or not. Either PHASES.md needs `programs` spelled out (and function mode moved to Phase 9) or the plan owes a hand-pinned function-mode gate. Right now the plan's acceptance gate (`PLAN.md:194-204`) runs `differential.py` once and that battery's function mode does not invoke the interpreter. **A conformant-but-wrong interpreter that crashes on every entry call passes the acceptance gate** — there is no function-mode check at all.

**Evidence.** `PHASES.md:55-60`, `PLAN.md:5` ("Function mode is out of scope this phase (the acceptance names program mode; §5 risk 10)"), `PLAN.md:243` (risk 10), `PLAN.md:194-204` (acceptance gate does not include any function-mode check for the interpreter).

**Fix.** Either amend `PHASES.md` to add "function mode" to the Phase-5 scope with a recorded entry-invocation protocol (JSON in/out, like the harness at `backend/rust/harness.rs`), or amend it to remove `corpus/valid` and spell out "every program-mode fixture under `differential.py program_cases()`" so the orchestrator's acceptance battery compares against the plan's text exactly. The current text reads as overclaiming.

### B4 — major · 14 of 29 fixtures are unaddressed by the plan's program-mode loops

The plan's coverage table (the brief's own mapping) is incomplete. From the brief: "I3 → 01,03,04,05,07; I4 → 02; I5 → 16–29; I6 → 06,09,10,11,12,15; I7 → 08, 19-io-errors". The corpus has 29 fixtures; the brief maps 21 distinct fixture numbers; 8 are unaccounted for:

- `13-module-program.agentscript` — already in `differential.py program_cases()` at line ~407 (`"stdout": "rectangle\n6.0\n"`), so it is exercised as a Phase-4 commitment.
- `14-sequenced-bodies.agentscript` — already in `program_cases()` (line ~415).
- `17-nested-cons.agentscript` — listed in I5's loop; pure-function fixture, no `main`, same no-driver problem as B1.
- `18-pattern-binders.agentscript` — not listed in any item; pure-function fixture. Its header is `grammar/corpus/valid/18-pattern-binders.agentscript:1-4`: a parenthesised `not-found` matches an `IoError` case. This is a bare-identifier-vs-parenthesised-case test (the spec's hardest pattern detail) and is the only fixture that pins it; `PLAN.md:147` says I4 should cover it but the I4 gate at `PLAN.md:154-158` does not list 18 by name — it lists "negative literal pattern" and a heredoc and "qualified enum heads". **18 is uncovered.**
- `20-option-result-ctors.agentscript` — I5 lists 20 in its loop, but the file is a single-arg classify with no `main`, no driver; same no-driver problem as B1.
- `21-option-result-combinators.agentscript` — same.
- `22-boolean-algebra.agentscript` — same.
- `24-list-reshaping.agentscript` — same.
- `25-list-aggregation.agentscript` — same.
- `26-map-lifecycle.agentscript` — same.
- `27-string-query.agentscript` — same.
- `28-string-transforms.agentscript` — same.

That is 12 of I5's loop (16, 17, 20, 21, 22, 24, 25, 26, 27, 28, plus the orphan 29 from B1) running as `exit 0, stdout ""` against an empty-string oracle, and 18-pattern-binders covered by no item. The plan's I3 generates a `main` driver for 01/03/04/05/07 and I5/I6 do not; either every loop gets the driver or the plan is silent on what the gate actually compares for these twelve files.

**Evidence.** Plan §§3 mapping summary; fixture headers; `PLAN.md:174` (I5 gate, no driver); `PLAN.md:186` (I6 gate, no driver); `PLAN.md:171-173` (I3 gate, *with* driver).

**Fix.** Either generate a driver for every I5/I6 file the way I3 does, or state explicitly that these are covered by `backend/cases/*.json` and `bench/tasks/*.json` instead of the program-mode oracle — and accept that the 120-function-case gap of B3 doubles as their only check.

### B5 — major · corpus file claim verifications (ask-for-the-class): the corpus does not exercise what the plan claims it pins

I read every fixture under `grammar/corpus/valid/` and verified the following against the plan's stated pins:

- **String escapes** — covered above (B2). Plan's I2 heredoc pins `\n` and `\\`; the other three from §2.5 (`\" \t \r \0`) are uncovered. (`PLAN.md:243`, `PLAN.md:130`.)
- **NaN-sort case** — partially. `25-list-aggregation.agentscript:67-72` (`rank`) sorts `String` fields by `Float64` keys with NaN; case file `backend/cases/25-list-nan-keys.json` pins three inputs. **A list of `Float64` values sorted directly is not in the corpus**, but `25-list-aggregation.agentscript:21-28` (`report`) ends with `(show-floats (list-sort xs))` where `xs` is `(List Float64)` — so `25-list-aggregation.agentscript` does pin the Float64-element sort via `report`. The `rank` function sorts strings by `Float64`, which exercises the comparator with NaN but not the element-as-Float64 path. Plan's risk 5 calls this out.
- **MIN / -1** — covered by `23-numeric.agentscript:67-69` (`int64-min`) and `23-numeric.agentscript:95-97` (`wrap-mod`); case `23-numeric-narrow.json` and `23-numeric-edge.json` carry the function-mode pins.
- **read-line at EOF** — `19-io-errors.agentscript:24` does `(line (try (read-line)))` but the case file (`backend/differential.py:412-447`) sends `"B"` as stdin for the success case. The fixture's match `(some s) … (none) ""` would surface an EOF, but no case sends empty stdin to `read-line`. The plan's risk 6 names MIN/-1 but not EOF; **EOF on `read-line` is uncovered**.
- **Sorted map iteration** — covered. `26-map-lifecycle.agentscript:31-34` reports `(string-join (map-keys m2) ",")` where m2 is built from a string-split; case `backend/cases/26-map-lifecycle.json` pin `"b,c"` and `"a,b,c"` — these are the codepoint-order outputs that distinguish BTreeMap from sorted().
- **`try` inside a lambda** — the semantic fixture `grammar/corpus/semantic/try-in-lambda.agentscript:1-9` is rejected by the *checker* (it does not compile), so the interpreter never sees it. The plan's risk 9 names the issue and says it is "Pinned by an I2/I3 heredoc with `try` inside a lambda passed to a Result-returning defun." I cannot verify that heredoc is written down (I2/I3's `PLAN.md:99-110` and `PLAN.md:117-122` do not contain one with `try`); **the pin is claimed but the gate does not contain the test**.

**Evidence.** Fixture content above; `PLAN.md:117-122` (I3 gate contains no `try`); `PLAN.md:99-110` (I2 gate contains no `try`); risk 9 at `PLAN.md:236`.

**Fix.** Add the I2 heredoc explicitly (an inline script in `PLAN.md` §3, not a `;`-comment hand-wave), add an EOF case to `differential.py program_cases()` for `19-io-errors.agentscript`, and add a fixture or heredoc that exercises `\r`, `\t`, `\0`, `\"` string escapes.

### M1 · minor · the plan's Int32 I2 gate does not exist, only Int64 + and Float64 /

The I2 gate (`PLAN.md:108-117`) exercises only `(+ -1 2)`, `(/ -3.0 2.0)`, `(+ 9223372036854775807 1)`. There is no `Int32` operation gate. Combined with B2's `l-4d92` evidence, this is the most concrete expression of the Int32 width hole: the interpreter could omit `Int32` arithmetic entirely and pass I2.

### M2 · minor · `26-map-lifecycle.agentscript` exercises `map-keys` but not `map-pairs` (the plan's invariant table)

Plan invariant table: "Map iteration sorted by key — `runtime.py m_pairs`, `rt.rs` BTreeMap note — I5." `26-map-lifecycle.agentscript:31-34` returns only `map-keys`, not `map-pairs`. The case file `backend/cases/26-map-lifecycle.json` likewise never asserts `map-pairs` output. **The invariant is documented, the gate does not reach it.** Either an additional case is added or the invariant is restated as `map-keys`-only.

### M3 · minor · no exit-status pin for a trap

The plan's I2 heredoc pins `test $? -ne 0` for `(+ 9223372036854775807 1)` overflow. The acceptance gate compares exit status byte-for-byte against the declared `want` in `program_cases()`. No program-mode case in `program_cases()` declares exit 2 for a trap — the only non-zero exits are 1 (`err` case via `main_exit`). If the interpreter traps via `process::exit(2)` (its own internal-error class, per §2.4), there is no fixture to fail against; if it traps via the `err` channel, it disagrees with the Rust arm's panic. The plan's risk 13 ("Exit-code collisions") identifies the gap but the gate does not pin the outcome.

## Conformant-but-wrong

Each is an implementation that satisfies every line of the plan's written gate and is nonetheless wrong.

1. **Interpreter that implements Int32 arithmetic as unbounded Python integers.** Passes B1 (no Int32 trap is exercised), passes I2 (only Int64 + and Float64 / are gated), passes the program-mode differential (no `program_cases()` case asserts Int32), and the acceptance text in `PHASES.md` reads as satisfied. Wrong because `l-4d92` documents that this is the bug.
2. **Interpreter that lists `String` elements by codepoint but sorts a user `defenum` by tag name or by declaration order — implementation-defined.** Passes every gate; the corpus sorts only `String`-keyed projections or `Float64` elements. Wrong because the spec says one thing and Python/Rust implement the other.
3. **Interpreter that handles `\n` and `\\` correctly but treats `\t` as the two characters `\` and `t`.** Passes I2's heredoc gate (only `\n` and `\\` are asserted). Wrong because the spec lists five escapes.
4. **Interpreter that returns `(none)` at EOF for `read-line` but hangs on an empty-stdin run.** Passes every gate; no program-mode case feeds empty stdin. Wrong by a missing case file.
5. **Interpreter that exits 0 silently on every program-mode file with no `main`.** Passes B1's gate (which executes but does not assert content for these files) and any future "executes under the interpreter" acceptance text read as "process exits". Wrong because the spec says modules are programs only when they declare `main`.
6. **Interpreter that returns a non-trapping result for `(+ 2147483647 1)` at Int32 but traps at Int64.** Passes I2 (Int64 trap gated, Int32 not). Wrong by spec.

## Verified

- Fixture-to-item mapping for the **named** items: I3 covers 01/03/04/05/07 with a generated `main` driver per the brief; I4 covers 02; I6 covers 06/09/10/11/12/15 (06 and 15 have `main`; 09/10/11/12 do not, see B4); I7 covers 08 and 19-io-errors via `differential.py program_cases()`.
- `differential.py program_cases()` already pins `13-module-program.agentscript` (`"rectangle\n6.0\n"`) and `14-sequenced-bodies.agentscript` (multi-line output). These are not in the plan's item map because the plan is additive, not replacing.
- I0 baseline numbers (`validate 98 ok`; `checker gate 79 ok`; `check_corpus 31`; `differential 120 + 15`; `pytest 161`) reproduce from `ROADMAP.md:62-92` and the Phase 4 closure record.
- Tree-sitter `LANGUAGE_VERSION 14` at `grammar/tree-sitter-agentscript/src/parser.c:9` (per `PLAN.md:107`) — could not verify without opening the file, but the brief and the plan agree.
- `PLAN.md:165-170` (exit glue): pin via `backend/rust/rt.rs main_exit` and `backend/runtime.py main_exit`. Plan records the third-witness issue (`PLAN.md:171-173`) and `ORACLES.md` is the mechanism. Verified by reading the plan text; the file itself is owed by I0.
- The 120 function cases are at `backend/cases/*.json` (verified 29 files) and `bench/tasks/histogram.json` (verified). Plan does not gate against them, per B3.

## Unverified

- `ORACLES.md` content — does not exist yet; owed by I0.
- `BASELINE.md` content — does not exist yet; owed by I0.
- The exact tree-sitter crate version that accepts `LANGUAGE_VERSION 14` — `PLAN.md:107` flags this as "verified on crates.io during I1"; I cannot check crates.io without leaving the read-only toolset.
- Whether `16-recursive-schema.agentscript` (also no `main`, listed in I5's loop) has a hand-pinned value in `backend/cases/` — `ls backend/cases/` does not list a `16-*.json`, so this fixture appears to be in the I5 loop without either a driver or a case file. Not enumerated above; treated as part of B4.
- `oracles.py` content — does not exist; owed by I0.
- Whether the I2 heredoc gate at `PLAN.md:108-117` is exactly what gets executed or is paraphrased — read literally from the plan.

## Risks (carried forward to the implementer)

- The plan's "third witness" wording (a checked-in oracle in `ORACLES.md`) is the right idea, but the *content* of that oracle has to be hand-pinned for every case where python and rust disagree by spec (`l-4d92`, `l-5c47`) or where the corpus does not exercise a behaviour (string escapes). Without that, the oracle is round-tripped from the same defect.
- The plan's acceptance gate running `differential.py` once does not check that the *interpreter arm* ran; it only checks the summary line. A bug that causes the interpreter process to be skipped (e.g., a missing `build_interpreter`) is caught by `grep -q 'interp'` on the summary (`PLAN.md:202`) but only because the summary is updated. If the implementer updates the summary before wiring the arm, the gate stays green on a missing build.
- `cargo test` exercises `MIN/-1`, NaN order, `fmt_f64` and sort stability — but these run inside the interpreter crate, not against a corpus program. A divergence between the cargo-test pins and the program-mode pins (e.g., `fmt_f64(1e16)` passing cargo but failing `29-literals.agentscript`) is invisible because `29-literals.agentscript` is the no-driver loop in B1.
