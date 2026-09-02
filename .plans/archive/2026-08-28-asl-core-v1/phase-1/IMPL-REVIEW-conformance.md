# Phase 1 implementation review — conformance and gate integrity

Lens: item-by-item conformance to `.plans/phase-1/PLAN.md` (v2), scope drift, gate integrity.
Read from the files and from commands run against them, not from the implementer's report.

## Verdict

**accept-with-fixes** — all 17 work items landed, no gate checks less than before, and every one
of the 12 new semantic fixtures was proved to fire for the reason it names; the fixes owed are
documentation accuracy (three deviations are described wrongly), one tautological unit test, and
the unfixtured imported-call arity hole that §6.5 sanctions but that now lets a wrong program
across the new boundary check clean.

---

## Work-item table

| item | verdict | evidence |
|---|---|---|
| W1 spec amendment | as-specified | `AGENT_SPEC_CORE.md:87` `qual-type ::= ident "/" type-name`; §4.0 gains all five paragraphs (transparent export, bare case, no re-export, contract = header + declarations, spelling-decides-kind); `:292-293` defschema/defenum exportable; `:332-333` case names qualified across a boundary; §8 gains two rows (`s/parse-html-url`, `s/Point`) + the module-path collision clause; rule 9 widened, **rule 13 added verbatim**, `:706` reads `Rules 2, 5, 6, 7-13`. `closure_audit.py` → `OK: spec and corpus are closed`. |
| W2 Rust codegen | **deviated** (dev 2) | Verified by emitting: `pub fn swap<A: Clone, B: Clone>(p: (A, B)) -> (B, A)`; `pub enum Tree<T>` with `::std::boxed::Box<crate::core_trees::Tree<T>>`; `#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord)]` on `Tree<T>`/`Cell<T>` and `#[derive(Debug, Clone, PartialEq)]` on `Shape` (Float64). `plan_derives()` runs over **every linked unit before emission**, closing §6.1's forward-reference hazard. Deviation: `NO_TOTAL_ORDER = {"Float64", "IoError"}` — plan said `Float64` alone. Strictly more conservative and correct (`rt::IoError` has no `Ord`); Phase 2's 8 blocked builtins are unblocked. |
| W3 Lark grammar | as-specified | All five edits present at `agents.lark:26,58-60,90,115,194`; `QUALIFIED_TYPE.2` at the same priority as `QUALIFIED`. |
| W4 tree-sitter | as-specified | All five edits at `grammar.js:38,103-104,181-182,218,238`; `src/grammar.json` contains `qualified_type` (4 occurrences) — regenerated. |
| W5 conformance gate | as-specified | `validate.py:142-145` adds `corpus/modules` (5 rows now in the table); `PROBES`/`token_identity()` at `:60-121`, 7 probes, all `ok`, span-compared against `tree-sitter parse` output, `(/ a b)` still `OPERATOR`. |
| W6 fixture matrix | **deviated** (dev 3, dev 4) | 21 new fixtures: 4 `modules/`, 5 `valid/`, 12 `semantic/` — every matrix row present. `06-module.agents:6` now `:export [shout area tally Shape]`. Deviations: `valid/13-module-program.agents` added (not in the matrix); `valid/12-transitive-use.agents` has **only** the first of the two functions the matrix specifies. |
| W7 `; expect-only:` | as-specified | `gate.py:28-41` + `:69-72`; `set(codes) == {want}`. Every phase-added fixture uses it (12/12); no pre-existing fixture's verdict changed. |
| W8 collect split | as-specified | `collect.py:54` `exported_types`; `:130-136` partitions on `t.type == "TYPE_NAME"`; `:70-79` adds `exported_cases` / `exported_fields` — the single "publicly reachable member" definition W8 asked for. Deviation 7 is a sequencing note, not a placement change: the `exported_types` validation is in `resolve.py::module_rules` where W9.1 put it. |
| W9 resolve.py | **deviated** (dev 1) | All nine sub-items present: `module_rules` (`:128-135`, `case_owner` allowance removed), `export_closure`/`public_type` (`:200-231`), `qualified_types` (`:184-198`), `qualified_names` + `exported_cases` (`:182`), `imported_schema`/`_ctor` (`:370-394`), `imported_fields` (`:104-112`), `case_source`/`exhaustive` keyed on `f"{target.name}/{enum.name}"` (`:466-479`, `:481-496`). Deviation: `public_type` reports **local** types only; see Finding 1. |
| W10 types_.py | as-specified | `Con.__init__(name, args=(), mod=None, shown=None)` — third positional as required; `unify:122` adds `a.mod != b.mod`; `declared`/`imported_con`/`case_type`/`module_of`/`qualified`/`_ctor`/`pattern_types` all carry `owner`. `show` uses `shown`. Two new `checker/t` assertions present. `Con("#"+name)` encoding untouched. |
| W11 backend module loading | as-specified | `grammar/modules.py` — one resolver, read by `checker/resolve.py:83` (`from modules import find`), `to_python.py:26`, `to_rust.py:28`. Signature is verbatim `transpile(self, src, *, path=None, roots=())`; `bench/harness/run.py` **unchanged** and still text-only. Both CLIs take repeatable `--root`. Emission order enums→schemas→funs, imports first. |
| W12 qualified lowering | **deviated** (dev 5, dev 6) | Python `qual()`/`atom`/`ctor`/`call`/`pattern`; Rust `tname`/`rtype`/`qual`/`qualified_case`/`ctor`/`call`/`pattern`. `rustc` accepts `06-module` (0 errors). Deviations: §6.7's W12 unknown resolved with nested `pub mod` + `use super::rt;` (`to_rust.py:196-201`), and the unplanned `sequence()` fix in both emitters. |
| W13 check_corpus | **deviated** (dev 8) | `SKIP_RUST`/`SKIP_PY` **deleted**; `--root grammar/corpus/modules` threaded; `run` column via `runpy` + `eval`. `06-module.agents` reads `ok ok ok ok ok`. Deviation: the `run` column is opt-in via `; run:`; 5 of 13 valid fixtures carry one. |
| W14 tests | as-specified | `backend/t/test_imports.py` transpiles a two-module program at test time into a tempdir; `test_smoke.py:46-55` drift assert; `smoke.agents:3` gains `Shape`. 47 → 59 (> 47+2). |
| W15 differential | as-specified | All four call sites take `path=src, roots=ROOTS` (`:30,:50,:76,:84`); one program case on `valid/13-module-program.agents` that matches an imported union, calls `s/area`, and uses **two aliases**; header now reads `5 program cases`. |
| W16 handbook | as-specified | `generate.py:66-70` export line gains `Point`; `:79-82` adds a `(defun area [(s o/Shape)] …)` block. `generate.py --check` exit 0. **Measured: 12,078 → 12,311 chars, +233 (+1.9%), ≈ +58 tokens** — larger than the plan's +85-char estimate, and the plan required the measured figure be reported. |
| W17 PCP | as-specified | All 8: `d-5837`, `d-c912`, `d-d06b`, `d-b47d`, `d-84a9`, `c-055e`, `c-c6a3`, `r-ea8c` → **Resolved** with the update line; plus an unplanned `c-4c51` for the sequence defect. `.pcp/INDEX.md` counts match (lang d 8→13, c 4→6; spec c 1→2). |

**Scope drift: none found.** `AGENTS.md`, `EXPERIMENT.md`, `ROADMAP.md`, `bench/harness/run.py`,
`backend/runtime.py`, `backend/rust/rt.rs`, `grammar/closure_audit.py`, `.pcp/lang/{checker,typing,
inference,io,lexical}.md` are all byte-identical to the pre-phase snapshot.

### The eight declared deviations, checked

| # | claim | verdict |
|---|---|---|
| 1 | rule 13 local-only; qualified reported as `rule-9` | **true**, and defensible — but stated incompletely. See Finding 1. |
| 2 | `Eq`/`Ord` taint seeds on `{Float64, IoError}` | **true**. Correct and strictly more conservative. |
| 3 | "`valid/12` imports only `text/report`, so the *no import needed* direction is not pinned there" | **true fixture change, inverted description.** `valid/12` is precisely what pins *no import needed*; the plan's missing second function was the *must import to name* half. See Finding 4. |
| 4 | `valid/13-module-program.agents` added as W15's source | **true**. Necessary — the matrix named no program fixture and W15 needs one. |
| 5 | §6.7's W12 unknown resolved via nested `pub mod` + `use super::rt;` | **true**, `to_rust.py:196-201`. |
| 6 | unplanned fix: non-final body expressions discarded; shared `sequence()` in both emitters | **true**, and it is gated. See Gate integrity note. |
| 7 | W8 carries W9.1's `exported_types` validation | **misstated** — it is a sequencing observation; the code is in `resolve.py::module_rules`, exactly where W9.1 put it. No file-level deviation. |
| 8 | `run` column driven by opt-in `; run:`; 5 fixtures carry one | **true**. Opt-in, so a fixture without a header asserts nothing in that column — an additive weakness, not a removed check. |

**Nothing else deviated silently.** Every plan sub-item was located in the code.

---

## Gate integrity

Every gate script and test file diffed against `snap-phase1/`. **No gate checks less. No corpus
glob narrowed, no assertion loosened, no skip or exclusion added, no `; expect:` weakened, no
fixture moved to a weaker directory.**

| gate file | what changed | more / less / same | evidence |
|---|---|---|---|
| `grammar/validate.py` | `+corpus/modules` scan; `+PROBES` / `token_identity()` (7 span-compared probes), appended to `failures` | **MORE** | 5 `modules/…` rows now in the table (0 before); probe table prints 7 `ok` rows. Purely additive — the `valid`/`invalid`/`semantic` case lists are untouched. |
| `grammar/closure_audit.py` | **no change** | SAME (reach grew implicitly) | `:57` globs `corpus/valid/*.agents`, which is now 13 files instead of 8. |
| `prelude/generate.py` | handbook example content only | SAME | No gate logic touched; `--check` semantics unchanged. |
| `checker/gate.py` | `expected()` returns `(code, exact)`; new `; expect-only:` branch asserting `set(codes) == {want}` | **MORE** | 12 fixtures now on the exact assertion; `; expect:` semantics byte-identical for the 17 pre-existing ones. |
| `backend/check_corpus.py` | `SKIP_RUST`/`SKIP_PY` **deleted**; `--root` threaded; new `run` column (`runpy` + `eval`, non-zero exit ⇒ FAIL) | **MORE** | `06-module.agents` went from `ok skipped ok skipped` to `ok ok ok ok ok`. Verified both ways: the constants appear nowhere in the file, and nothing else was removed — the `py_compile` and `rustc` blocks are the same code minus the skip guard. |
| `backend/differential.py` | `path=`/`roots=` threaded through all four transpile sites; 5th program case on `valid/13` | **MORE** | `4 program cases` → `5 program cases`; existing 4 I/O cases and 7 function cases unchanged. |
| `backend/t/test_smoke.py` | +1 drift assert | MORE (weak) | Compares the checked-in `smoke.py` to emitter output. Ties the file to its source, which nothing did before; it cannot judge whether the output is *right*. |
| `backend/t/test_imports.py`, `test_modules.py` | new, +9 tests | **MORE** | New machinery: transpiles at test time into a tempdir and executes. |
| `checker/t/test_types.py` | +2 assertions | MORE (one of them weak) | See Test quality. |
| `backend/t/smoke.agents`, `smoke.py` | `+Shape` on the export list; `smoke.py` regenerated (one trailing blank line) | MORE | Removes the tree's last known rule-13 violation. |
| `grammar/corpus/valid/06-module.agents` | `+Shape` on `:export`; `+; run:` header | MORE | The fixture that was the gap now exercises the rule and the `run` column. |

### Do the new assertions actually bite? (mutation-tested)

| mutation | caught by |
|---|---|
| drop `a.mod != b.mod` from `unify` | `checker/gate.py` → `imported-type-mismatch: expected only type, got nothing`, **1 failure**; `test_same_name_from_different_modules_does_not_unify` FAILED |
| key `imported_con` on the alias instead of the defining module | `checker/gate.py` → `valid/11-name-coexistence.agents … type,type,type FAIL`, **5 failures**. *Not* caught by either new unit test (see Finding 5) |
| key the Python emitted prefix on the alias | `pytest backend/t` → **4 failed**; `check_corpus` → `06-module.agents … run FAIL`, 3 failures |
| revert `sequence()` in `to_python.py` only | **nothing** — 16 passed, `check_corpus` 0 failures |
| revert `sequence()` in **both** emitters | `backend/differential.py` → `python 'rectangle\n6.0\n'` vs `rust '6.0\n'` — **1 disagreement**. `pytest` 59 passed and `check_corpus` 0 failures throughout |

The last two rows matter: the unplanned deviation-6 fix is gated by exactly one artifact —
`valid/13-module-program.agents`'s `(try (println …))` in non-final position, seen only by
`backend/differential.py`. That is a thin but real gate, and it is the one PCP `c-4c51` claims.

---

## Fixture perturbation results

Method: copy `grammar/corpus` to a tempdir, apply the minimal edit that removes the named
violation (editing `modules/core/private.agents`'s export list where the violation is the target
module's privacy), re-run `check_file` with the temp roots. A fixture that still reports after
the violation is removed was never testing what it claims.

| fixture | named rule | fires? | codes as shipped | clean after violation removed? |
|---|---|---|---|---|
| `export-bare-case` | rule-2 | yes | `rule-2` | **clean** (`:export [circle]` → `[Shape]`) |
| `export-undefined-type` | rule-2 | yes | `rule-2` | **clean** (drop `Missing`) |
| `import-unexported-case` | rule-9 | yes | `rule-9` | **clean** (`core/private` exports `Hidden`; `make -> p/Hidden`) |
| `import-unexported-type` | rule-9 | yes | `rule-9` | **clean** (`core/private` exports `Hidden`) |
| `imported-ctor-missing-field` | ctor | yes | `ctor` | **clean** (`(t/Cell)` → `(t/Cell :value 1)`) |
| `imported-type-mismatch` | type | yes | `type` | **clean** (`(x Shape)` → `(x s/Shape)`) |
| `mixed-module-match` | rule-4 | yes | `rule-4` | **clean** (both arms imported) |
| `non-exhaustive-imported-match` | rule-4 | yes | `rule-4` | **clean** (add the `s/rectangle` arm) |
| `private-type-in-exported-signature` | rule-13 | yes | `rule-13` | **clean** (`:export [area]` → `[Shape area]`) |
| `qualified-ctor-unexported` | rule-9 | yes | `rule-9,rule-9,rule-9` | **clean** (`core/private` exports `Vault`) |
| `unimported-alias-type` | rule-9 | yes | `rule-9` | **clean** (`(x q/Shape)` → `(x s/Shape)`) |
| `wrong-alias-type` | rule-9 | yes | `rule-9` | **clean** (`t/Shape` → `s/Shape`) |

**0 fixtures failed perturbation.** Every one names the reason it is rejected, and removing that
reason makes it check clean — none is passing on an unrelated earlier check. All 12 also parse
under both grammars (`validate.py`, `parse parse ok` on every row).

One observation: `qualified-ctor-unexported` reports `rule-9` **three times** for one defect
(`imported_schema` fires once, `qualified_types()` once for the return type and once for the ctor
head). `set(codes) == {want}` hides the duplication. Cosmetic, not a correctness issue.

---

## Test quality

47 → 59. All 12 new tests read. "Catches its bug?" was mutation-tested where the answer was not
obvious from the source.

| test | asserts spec or emitted output? | would it catch the bug it is about? |
|---|---|---|
| `test_types::test_same_name_from_different_modules_does_not_unify` | **spec** (§2.3 / PCP `d-c912`) | **yes** — mutation-verified: FAILS when the `mod` key is dropped from `unify` |
| `test_types::test_one_module_reached_through_two_aliases_is_one_type` | spec in intent, **tautology in fact** | **NO** — hand-builds two `Con`s that already carry the same `mod`, so it only proves `unify` ignores `shown`. Mutation-verified: still passes with `imported_con` keyed on the alias. See Finding 5 |
| `test_smoke::test_the_checked_in_lowering_matches_its_source` | **emitted output**, by construction | **no, by design** — it is a drift assert. It cannot say the lowering is correct, only that the committed `.py` still equals what the emitter prints. Correctly categorised in the plan as W14.2 |
| `test_modules::test_closure_is_dependencies_first_and_the_file_last` | spec (§2.8 / W11 fail condition, verbatim `["core/strings", "text/casing"]`) | yes |
| `test_modules::test_a_transitive_import_precedes_the_module_that_needs_it` | spec (§2.4 ordering) | yes |
| `test_modules::test_one_module_under_two_aliases_is_linked_once` | spec (§2.8, prefix from module path) | yes |
| `test_modules::test_a_root_is_searched_in_order` | spec (resolution rule) | **partly** — the name claims ordering but only one root is passed; it tests hit-and-miss, not precedence between two roots |
| `test_modules::test_an_unresolvable_import_is_reported_not_swallowed` | spec (`modules.py:62-63`) | yes |
| `test_imports::test_an_imported_constructor_builds_a_value_of_its_union` | **mixed** — `geo_shapes__circle` is `AGENT_SPEC_CORE.md` §8; `("circle", 2.0)` is the emitted representation (pinned by §2.8 and by the pre-existing `smoke.py`/`histogram_agents.py` convention) | yes — mutation-verified |
| `test_imports::test_a_match_over_an_imported_union_dispatches_on_the_case` | **spec** (§4.4 behaviour) | **yes** — mutation-verified: FAILS on alias-keyed prefixing |
| `test_imports::test_two_aliases_for_one_module_reach_one_definition` | **spec** (§8: prefix from defining module path) | **yes** — the strongest of the twelve; `emitted == ["geo_shapes__area"]` is exactly the discriminator |
| `test_imports::test_the_corpus_module_fixture_calls_across_the_boundary` | **spec** (`shout("hi") == "HI!"`, `area(circle(2.0)) == 3.14159*4.0` — read off the source, not the output) | **yes** — mutation-verified |

Tests that would still pass with the implementation wrong in the way they are nominally about:
**`test_one_module_reached_through_two_aliases_is_one_type`** (proved), and
**`test_a_root_is_searched_in_order`** for the ordering half of its name.

---

## Unverified-list dispositions

| # | item | disposition |
|---|---|---|
| 1 | module-path mangling collisions | **Better than recorded — acceptable.** Probed: `core/shapes` + a module declared `core-shapes` makes `to_python.py:103` raise `ValueError: module paths core/shapes and core-shapes mangle alike`, and `to_rust.py` has the same guard. The gap is that the *checker* reports nothing (`diags=0`) and the backend surfaces a raw traceback rather than a diagnostic. `AGENT_SPEC_CORE.md` §8 requires "the compiler errors"; it does. Fine to ship; file the diagnostic-quality half. |
| 2 | §6.5 arity of an imported call reports nothing | **Should not ship silently — the phase's own surface.** Probed: `(s/circle 1.0 2.0)` → **0 diagnostics**; `(s/area x x)` → **0 diagnostics**; the identical local call `(circle 1.0 2.0)` → `arity: circle takes 1 argument(s), given 2`. A wrong program crossing the new boundary checks clean, caught only by `rustc` on one target. §6.5 declined the fix and the plan is conformant, but there is no fixture and no `; expect:` row, so nothing will notice when it is fixed or further broken. Add a `semantic/imported-call-arity.agents` marked as a known gap, or fix it. **Major.** |
| 3 | §6.1 no bound inference beyond `Clone` | **Acceptable recorded gap.** Real (a generic `defun` using `=`/`<`/`list-sort` over a type variable will not compile) but out of `r-ea8c`'s scope, unreachable from any current fixture, and recorded in §6.1 and PCP `c-055e`. The related forward-reference hazard §6.1 flagged was *closed*, not deferred: `plan_derives()` computes taint over every linked unit before emission with a fixpoint loop, so emitter order cannot affect the answer. |
| 4 | shadowing hazard inside imported units (§6.4) | **Acceptable recorded gap.** `types_.py:157`'s rigid-before-declared test is pre-existing and unchanged; `valid/11`'s `(defun {Shape} identity-of …)` pins the *legal* half (a binder may reuse an imported type's spelling). The illegal half — a binder shadowing a **local** declared type — is untouched by this phase and correctly recorded. |
| 5 | `bench/algo/histogram_agents.py` checked in with no drift assert | **Acceptable but cheap to close.** Confirmed: `bench/algo/` is byte-identical to the snapshot and `test_histogram.py:13` still imports the committed file. W14.2 gave `smoke.py` the assert this file still lacks — a five-line copy of `test_the_checked_in_lowering_matches_its_source`. §5 records it; the phase changed the emitter, so the risk is live. **Minor.** |
| 6 | `ROADMAP.md` left unedited | **Should not ship.** Confirmed byte-identical to the snapshot. §2's table, §4's closing paragraph, §4's handbook figure and §6's second bullet now describe a state that does not exist, and §6 still lists `r-ea8c` as an open gap while PCP marks it Resolved — a direct contradiction between the two files a cold session is told to read together (`ROADMAP.md:3-4`). Replacement text below. **Major.** |

---

## Appendix: ROADMAP.md replacement text

Line numbers are against the current file. Replace exactly; do not renumber anything else.

**Line 6** —
```
**Last updated:** 2026-08-29 · **Head commit at writing:** `8679362` (+ phase 1, uncommitted)
```

**Line 44** —
```
| Conformance gate | **green** — 52 fixtures × 2 grammars, 0 failures, plus 7 token-identity probes span-compared across both parsers |
```

**Lines 46-47** —
```
| Python backend | **working** — corpus transpiles, tests execute, import closures link into one artifact |
| Rust backend | **working** — corpus transpiles and `rustc` accepts it; generics, recursive unions and import closures included |
```

**Line 49** —
```
| Semantic checker | **working** — all of §9 including rule 13, plus §4.1 construction, type checking, and type resolution across a module boundary |
```

**Line 50** —
```
| Semantic gate | **green** — 13 valid and 5 search-path fixtures clean, 29 semantic fixtures each rejected under the rule they declare, 12 of them asserted to report that rule and nothing else |
```

**Line 52** —
```
| Differential gate | **green** — 7 function cases and 5 whole-program cases, Python and Rust |
```

**Line 61** — `~2,600` is two revisions stale:
```
1b. `prelude/HANDBOOK.md` — generated agent-facing reference, ~3,080 tokens. This is the artifact
```

**Lines 121-122** — append after the existing sentence (do not replace the I/O figure, which is
still the correct history):
```
The handbook, which is resent on every model call, grew from ~2,642 to ~3,012 tokens (10,569 →
12,048 characters at the project's chars/4 approximation): **+14%** on the dominant per-call cost.
Types across the module boundary added a further 233 characters (12,048 → 12,311, ~3,078 tokens):
**+1.9%**, two example lines showing a type on an export list and an imported type in a signature.
```

**Lines 141-144** —
```
What the checker does **not** do, deliberately: it has no scrutinee-independent view of a `match`
in the resolve pass (the type layer supplies that), it does not check builtin call arity separately
from typing them, and it does not check the arity of a call reached through an alias at all — see
§6. It *does* now resolve types across a module boundary: an alias-qualified type resolves through
the defining module, identity is nominal and keyed by that module, and rule 13 requires an exported
signature to name only public types.
```

**Lines 208-211** — the gap is closed; replace the bullet with what remains open:
```
* **The module boundary is typed, with four holes left open.** `:export` admits type names, an
  importer writes `alias/TypeName` and `alias/case-name`, identity is nominal and keyed by the
  defining module, and rule 13 forbids an exported signature from naming a private type. PCP
  `r-ea8c` **Resolved** (`d-5837`, `d-c912`, `d-d06b`, `d-b47d`). Deliberately not closed: opaque
  export, separate compilation, the arity of a call reached through an alias — which is reported
  nowhere and has no fixture — and a cycle detector keyed on a module's declared name rather than
  on its path.
```

---

## Findings

**1 — minor — deviation 1 is defensible; the plan's own §2.7 already assigned that code, but the
`; expect-only:` net has no rule-13 strand across a boundary.**
`checker/resolve.py:220-231`:
```python
    def public_type(self, node: Tree, bound: set[str], where: str) -> None:
        """Only locally declared names are reported. Whether the DEFINING module
        publishes an alias-qualified type is the identical question rule 9 asks
        at the same token, and answering it twice would give one defect two
        codes."""
```
The reviewer's worry — that a private *imported* type in an exported signature falls through a
code no fixture pins — **does not hold**. `semantic/import-unexported-type.agents` is exactly that
program (`(defun tag [(h p/Hidden)] -> String …)`, `tag` exported, `Hidden` private to
`core/private`) and it carries `; expect-only: rule-9`, verified firing and verified clean once
`core/private` exports `Hidden`. The plan's own §2.7 table already assigns `rule-9` to
"`s/Shape` where `Shape` is not on `core/shapes`'s export list", so the implementation follows §2.7
and W9.2's wording is the half that is loose. The residual is narrow: `AGENT_SPEC_CORE.md:698-702`
states rule 13's third clause as "a type exported by the module that defines it", and no code path
ever reports `rule-13` for that clause — it is enforced only as `rule-9` by `qualified_types()`.
If that pass regressed, rule 13 would not backstop it.
*Fix:* one sentence in W9's record and in `d-b47d` stating that rule 13's cross-module clause is
discharged by rule 9 at the same token, so the two are not independent checks.

**2 — major — an imported call's arity is unchecked, so a wrong program across the new boundary
checks clean, with no fixture recording it.**
Reproduced:
```
(s/circle 1.0 2.0)   ->  0 diagnostics
(s/area x x)         ->  0 diagnostics
(circle 1.0 2.0)     ->  arity: circle takes 1 argument(s), given 2
```
`checker/resolve.py:235-237` returns before the arity check whenever the callee is not an `IDENT`.
Pre-existing and explicitly declined by §6.5, so the phase is conformant — but §6.5 made it
reachable, and there is no fixture, no `; expect:` row and no ROADMAP line, so nothing marks it.
*Fix:* add `grammar/corpus/semantic/imported-call-arity.agents` with `; expect-only: arity` as a
failing fixture for the next phase, or lift the `IDENT` guard so `qualified()`'s `Fun` arity is
compared. The ROADMAP replacement above names it.

**3 — major — `ROADMAP.md` contradicts `.pcp/lang/modules.md`.**
`ROADMAP.md:208-211` still reads "**Types cannot cross a module boundary.** `:export` admits only
lowercase identifiers … PCP `r-ea8c`" while `.pcp/lang/modules.md:41` now reads `- **Status**:
Resolved`. `ROADMAP.md:3-4` tells a cold session to read both. Four more stale sites: the §2 table
rows (11 fixtures / 8 valid + 17 semantic / 4 program cases — now 52 / 13+5+29 / 5),
`:141-144`'s "it cannot see across a module boundary for types, because the language has no way to
export one", `:61`'s `~2,600 tokens`, and the missing handbook-growth figure.
*Fix:* apply the appendix. The plan assigned no work item, which is the root cause.

**4 — minor — deviation 3 is stated backwards, and the fixture the plan asked for is half
present.**
`grammar/corpus/valid/12-transitive-use.agents` has one function, `show`, importing only
`text/report`. The matrix required "one function calls `(r/describe (r/unit-square))` **without**
importing `core/shapes`; **a second imports `core/shapes` and names `s/Shape`**". The second is
absent. The implementer's note says the *"no import needed" direction* is unpinned — that is the
direction the fixture **does** pin; the missing one is "must import to name". Coverage for the
missing half exists elsewhere (`valid/09` names `s/Shape` with the import;
`semantic/unimported-alias-type.agents` proves omitting it is `rule-9`), so §2.4 is covered in
both directions across the corpus.
*Fix:* correct the deviation note, or add the second function to `valid/12`.

**5 — minor — the second new `checker/t` assertion cannot catch the bug it is named for.**
`checker/t/test_types.py:105-113`:
```python
def test_one_module_reached_through_two_aliases_is_one_type():
    a = Con("Shape", (), "core/shapes", "s/Shape")
    b = Con("Shape", (), "core/shapes", "sh/Shape")
    unify(a, b)
```
Both `Con`s are hand-built already carrying the same `mod`, so the test only asserts that `unify`
ignores `shown`. Mutation-verified: replacing `Con(member, args, target.name …)` with
`Con(member, args, alias …)` in `types_.imported_con` leaves `pytest checker/t` at **26 passed**
while `checker/gate.py` reports **5 failures** on `valid/11-name-coexistence.agents`. W10.6 claims
this direction "is asserted nowhere else in the corpus" — the opposite is true: `valid/11` is the
only thing that catches it, and the unit test is the tautology.
*Fix:* build the two `Con`s through `Types.declared()` on a two-alias module, or drop the test and
record `valid/11` as the artifact that owns the direction.

**6 — minor — the sequence fix (deviation 6) has exactly one gate, and PCP `c-4c51` names the
wrong backend.**
Reverting `sequence()` in `to_python.py` alone is caught by nothing (16 passed, `check_corpus` 0
failures). Reverting it in **both** emitters is caught only by
`backend/differential.py`'s `valid/13-module-program.agents` case, via the single
`(try (println (describe sh)))` in non-final position. `c-4c51` describes the defect as "The Rust
lowering computed each of them and then threw the result away" — the pre-phase `to_python.py`
had the identical `for i, b in enumerate(body): … else: self.expr(b, stmts, indent)` and was fixed
by the same shared helper.
*Fix:* amend `c-4c51` to say both emitters; consider a `backend/t` case asserting a non-final
effectful expression is emitted, so the guard does not rest on one differential row.

**7 — minor — 15 of the 17 pre-existing `; expect:` fixtures could be `; expect-only:` today, for
free.**
Measured from `checker/gate.py`'s reported column: only `try-in-lambda` and `try-outside-result`
report two distinct codes (`rule-5,type`) — the plan's justification is **confirmed, and it is a
real constraint, not an accepted convenience**. But `numeric-mix` (`rule-6,rule-6`) and
`unbound-typevar` (`rule-10,rule-10`) report duplicates of one code, which `set(codes) == {want}`
accepts, and the other eleven report a single code. All 15 would pass unchanged on the exact
assertion.
*Fix:* flip the 15 in a follow-up; leave the two, and keep §5's honest statement that they retain
the weaker guarantee.

**8 — minor — `bench/algo/histogram_agents.py` is still a checked-in generated file with no drift
assert, in a phase that changed both emitters.**
`bench/algo/` is byte-identical to the snapshot; `test_histogram.py:13` imports the committed
`.py`. W14.2 gave `backend/t/smoke.py` exactly the assert this file lacks.
*Fix:* copy `test_the_checked_in_lowering_matches_its_source` into `bench/algo/test_histogram.py`.

**9 — minor — the `; run:` column and the module-mangling guard both fail in a shape that reads
like success or like a crash.**
`backend/check_corpus.py` prints `-` in the `run` column for the 8 fixtures without a `; run:`
header and exits 0 — the same "a column that is not `ok` still exits 0" shape the file's own
docstring warns about at `:14-15`. Separately, `to_python.py:103` / `to_rust.py:110` surface a
module-path collision as an uncaught `ValueError` traceback rather than as a diagnostic.
*Fix:* neither blocks the phase. Consider requiring a `; run:` header on every `valid/` fixture
that declares an exported function, so the `-` cannot hide a fixture nobody runs.
