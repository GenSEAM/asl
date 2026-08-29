# Phase 1 plan review — executability and gates lens

## Verdict

**approve-with-amendments** — the design is executable and the two grammar edits provably work
(I built and ran both), but three items are wrong as written: W7 misses `defun` generics, W5 misses
two `resolve.py` call sites that will make a planned *valid* fixture fail, and the work order leaves
W4–W6 with no way to fail; additionally the Python half of W10's "observable proof" proves nothing,
because `py_compile` already accepts today's broken output.

---

## Findings

### F1 — blocker — W7 does not cover `defun`; W10 cannot go green without it

**Claim under review:** §1.5 / W7 — the Rust breakage is `defenum` (`backend/to_rust.py:134-147`)
and `defschema` (`:124-132`).

**Evidence.** `defun` drops `type_params` by exactly the same filter, at
`backend/to_rust.py:150-151`:

```
150:        k = [x for x in self.kids(n)
151:             if not (isinstance(x, Tree) and x.data in ("type_params", "doc_opt"))]
```

Transpiling `06-module` and running the gate's own rustc invocation gives **13 errors**, not the two
the plan quotes:

```
$ rustup run stable rustc --edition 2021 --crate-type=lib lib.rs 2>&1 | grep -E '^error' | sort | uniq -c
   1 error: aborting due to 13 previous errors
   1 error[E0072]: recursive type `Tree` has infinite size
   1 error[E0391]: cycle detected when computing when `Tree` needs drop
   2 error[E0412]: cannot find type `A` in this scope
   2 error[E0412]: cannot find type `B` in this scope
   3 error[E0412]: cannot find type `T` in this scope
   1 error[E0423]: expected function, found macro `concat`
   1 error[E0425]: cannot find function `upper` in this scope
   2 error[E0425]: cannot find value `s` in this scope
```

`A`/`B` come from `pub fn swap(p: (A, B)) -> (B, A)` — `06-module.agents:20`, `(defun {A B} swap …)`.
W7's scope (`defenum` + `defschema`) leaves 4 of the 13 errors standing, so **W10 fails on its own
stated acceptance** ("the gate must print `ok` in the … `rustc` column").

Note also `E0423 expected function, found macro concat`: `s/concat(...)` is *parsed* by rustc as
`s / concat(...)`, and `concat!` is a std macro — the failure mode the qualified lowering must beat
is not a syntax error.

**Amendment.** W7 covers `defun` (`backend/to_rust.py:149-157`) as well: emit `pub fn swap<A, B>(…)`
from the `type_params` child it currently filters. State the acceptance for W7 independently of W9:
after W7 alone, `06-module` rustc errors drop from 13 to the 4 `s/…` ones. That is the milestone that
localises W7's failure; the plan currently has none.

**Confirming the rest of the plan's W7:** the recursive case *does* need indirection — `E0072
recursive type Tree has infinite size` fires, and the plan says so (`::std::boxed::Box<…>`, fully
qualified against the corpus's own `Box` schema at `06-module.agents:8`). That part is sound.
§6.1's open question about `#[derive]` bounds over a type variable is real and correctly flagged.

### F2 — blocker — W5 omits `resolve.py::_ctor` and `_field_access`; a planned *valid* fixture will fail

**Claim under review:** W5 lists six changes to `checker/resolve.py`: `module_rules`,
`qualified_types()`, `qualified_names`, `check_type`, `known_types`, exhaustiveness/`pattern`.

**Evidence.** `checker/resolve.py:300-305`:

```
300:    def _ctor(self, node: Tree, scope: set[str]) -> None:
301:        type_token = node.children[0]
302:        name = str(type_token)
303:        schema = self.mod.schemas.get(name)
304:        if schema is None:
305:            self.report("rule-2", f"{name} is not a record type in this module", type_token)
```

With a `QUALIFIED_TYPE` head, `name` is `"t/Cell"` and `self.mod.schemas` holds only local schemas,
so `valid/10-imported-generic-types.agents` — which the matrix says constructs `(t/Cell :value 1)` —
gets `rule-2` and **fails `checker/gate.py:39-47`'s clean requirement**. The plan assigns `_ctor` only
to `checker/types_.py:369-382` (W6.4) and never to `resolve.py`.

Same for `checker/resolve.py:322-327`: `self.field_names` (`:102`) is built from local schemas plus
`PAIR_FIELDS`, so `(.-value c)` on an imported record reports `rule-2: no record in this module has a
field value`. §2.1 decision 3 explicitly promises "exporting a `defschema` exports its fields for
construction **and `.-field` access**", so this is in scope by the plan's own design.

Because `resolve.py:410` runs the type layer only `if not self.diags`, either omission also blanks
W6 entirely on those fixtures — the type layer never executes, so `imported-type-mismatch` reports
nothing and *that* fixture fails too.

**Amendment.** Add to W5: `_ctor` (`:300-320`) resolves a `QUALIFIED_TYPE` head through the `Loader`
to the target module's schema and validates keys/missing fields against *that* schema;
`_field_access` (`:322-327`) admits fields of imported exported schemas.

### F3 — blocker — the work order gives W4–W6 nothing that can fail

**Claim under review:** §3 order W1 → W2/W3 → W4-W6 → W7-W10 → **W11 fixtures** → … → W14 tests.

**Evidence.** The only harness that exercises `checker/resolve.py` and `checker/types_.py` is
`checker/gate.py`, and it drives corpus fixtures (`:39`, `:49`). `checker/t` is W14 — after W11.
So under the stated order W4, W5 and W6 are written, and W11 is then written to match them. That is
the failure mode `AGENTS.md:55-58` was written about: the fixture ends up shaped by the
implementation rather than the other way round, and a rule that never fired looks defended.
W11's own "Depends on: W5, W6" makes the loop explicit.

Confirmed independently: `pytest backend/t bench/algo checker/t -q` → `47 passed`, and none of those
47 touch the checker's module boundary.

**Amendment — corrected order.** Split W11 and move the unifier unit test up:

```
W1  spec
W7  Rust defun/defenum/defschema generics + Box indirection   (independently reproducible today)
W2 + W3  grammars (one commit)
W11a modules/core/{shapes,trees,private}.agents  +  valid/09  +  one semantic fixture per rule code
       -> at this point checker/gate.py FAILS, with a named failure per rule
W4  collect.py
W5  resolve.py            -> semantic fixtures turn green one rule at a time
W6  types_.py  + the checker/t Con-identity unit test (moved out of W14)
W8  backend module loading
W9  qualified lowering
W10 un-skip 06-module
W11b remaining fixtures (valid/10, valid/11)
W12 manual tree check
W13 handbook
W15 differential case
W14 backend/t execution test
W16 PCP
```

The `Con`-identity unit test belongs with W6, not in a trailing test item: it is the *only* assertion
that a same-named type from two modules does not unify that does not go through a verdict
(`AGENTS.md:78-79`), and W6 has no other way to fail loudly.

### F4 — major — `py_compile` already accepts the "invalid Python", so W10's Python column proves nothing

**Claim under review:** §1.4 — the Python output for `06-module` "is not valid Python"; W10 — un-skipping
is "the observable proof the gap is closed".

**Evidence.** It is valid Python. `s/concat(s/upper(x), "!")` is a division expression:

```
$ .venv/bin/python backend/to_python.py grammar/corpus/valid/06-module.agents > cand.py
$ .venv/bin/python -m py_compile cand.py ; echo $?
0
```

`backend/check_corpus.py:44-46` runs exactly `py_compile`, nothing more. So deleting `06-module` from
`SKIP_PY` **today**, with no other change, already prints `ok` in the `compile` column. The Python
half of W10's acceptance is satisfiable by any syntactically-well-formed wrong lowering — including
one that emits `core_shapes__area` when it should emit `core_shapes__describe`, or that keeps a stale
tuple tag.

The Rust half is genuinely load-bearing (F1 shows rustc rejects it); the Python half is not.

**Amendment.** W10's acceptance for the Python column must be an *execution*, not a compile: either
`check_corpus.py` imports the emitted module (a `runpy`/`import` step alongside `py_compile`), or W10
is declared to depend on W14's execution test covering `06-module`'s `shout` — an imported *function*
call, which W15's planned case (an imported *union*) does not cover. Pick one and name it in §5.

### F5 — major — nothing in `pytest` runs a transpiler; W14 must not be another snapshot

**Evidence.** `backend/t` contains only `smoke.agents`, `smoke.py`, `test_smoke.py`, and
`backend/t/test_smoke.py:10` is `import smoke as s` — a **checked-in, pre-generated** Python file.
`bench/algo/test_histogram.py:13` likewise imports the checked-in `bench/algo/histogram_agents.py`.
No gate regenerates or diffs either against its `.agents` source. (I checked: `smoke.py` happens to
be in sync with the transpiler right now — `diff` clean — but that is luck, not enforcement.)

This means `AGENTS.md:75-76` ("`backend/t` runs AgentS source through the transpiler and executes the
result") is not true of the mainline tree, and W14's backend case is **new machinery**, not an
addition to an existing pattern. It is also the only proposed check that would catch F4's class.

**Amendment.** State in W14 that the backend case transpiles at test time from a `.agents` source in
a tempdir and executes the result; forbid committing a generated `.py` as the expectation. Consider
(cheap, one assert) adding a test that the checked-in `smoke.py` still equals
`Transpiler().transpile(smoke.agents)`, since the phase is about to change the emitter.

### F6 — major — `grammar/validate.py` never parses `corpus/modules`, and W11 puts new syntax only there

**Claim under review:** W11 — "Discovery is already right for multi-file cases and needs no change."

**Evidence.** `grammar/validate.py:63-74`:

```
63:    cases = [(p, True) for p in sorted((ROOT / "corpus" / "valid").glob("*.agents"))]
64:    cases += [(p, False) for p in sorted((ROOT / "corpus" / "invalid").glob("*.agents"))]
73:    semantic = sorted((ROOT / "corpus" / "semantic").rglob("*.agents"))
74:    cases += [(p, True) for p in semantic]
```

`corpus/modules` appears nowhere. The claim is true for `corpus/semantic` (the `rglob` at `:73`
handles the multi-file `import-cycle/` case — both `a.agents` and `b.agents` carry
`; expect: rule-11`, which is the convention new multi-file cases must follow), and true for
`checker/gate.py:39` (`(CORPUS / "modules").rglob`). It is **false for `grammar/validate.py`**.

Consequence: `modules/core/shapes.agents` (`:export [Shape area]` — the new export form) and
`modules/core/trees.agents` (`defenum {T} Tree` exported, the new recursive/parameterised shape) are
never parsed by tree-sitter by any gate. `semantic/export-undefined-type.agents` rescues the
`:export [TypeName]` form by accident; nothing rescues the rest.

**Amendment.** Add a work item: `grammar/validate.py` gains
`cases += [(p, True) for p in sorted((ROOT/"corpus"/"modules").rglob("*.agents"))]`. One line, and it
is the difference between "both grammars agree on the module fixtures" being enforced and asserted.

### F7 — major — `transpile()` takes text, not a path; W8/W15 are under-specified and `bench/harness` is off the gate list

**Claim under review:** W8 — "the file's own directory is always searched"; W15 — "thread the search
root through `build_python` (`:69-73`) and `build_rust` (`:76-84`)".

**Evidence.** Every call site passes a *string*:

```
backend/differential.py:30   (Path(d) / "cand.py").write_text(Transpiler().transpile(src.read_text()))
backend/differential.py:46   body = ToRust().transpile(src.read_text())
backend/differential.py:72   (d / "cand.py").write_text(Transpiler().transpile(src.read_text()))
backend/differential.py:79   (d / "main.rs").write_text(ToRust().transpile(src.read_text()))
bench/harness/run.py:133     py = Transpiler().transpile(code)
```

`transpile(self, src: str)` (`backend/to_python.py:66`, `backend/to_rust.py:95`) has no path, so
"the file's own directory" is not available to it and threading a `--root` alone does not fix
`differential.py`. W15 names only `build_python`/`build_rust` and misses `:30`/`:46` (the function
mode).

`bench/harness/run.py:133` transpiles **model-generated text that has no file at all**, and the
harness is not on §5's acceptance list — so a signature change that requires a path breaks the
measurement harness silently, mid-phase, in a repo whose EXPERIMENT.md is pre-registered.

**Amendment.** W8 states the signature explicitly: `transpile(src: str, *, path: Path | None = None,
roots: list[Path] = ())`, text-only calls keep working and resolve no imports. W8 names
`bench/harness/run.py:133` and `backend/differential.py:30,46` as call sites to leave working; W15
extends to all four differential call sites, not two.

### F8 — major — missing negative case: a `match` mixing cases from different modules

**Claim under review:** §4's matrix is complete for the negative space.

**Evidence.** `checker/resolve.py:380-386`:

```
380:        owner = self.mod.case_owner
381:        if all(h in owner for h in heads):
382:            enums = {owner[h] for h in heads}
383:            if len(enums) > 1:
384:                self.report("rule-4", f"arms mix unions: {', '.join(sorted(enums))}", node)
```

`enums` is a set of **bare** enum names. A local `Shape` and `core/shapes`'s `Shape` collapse to the
single string `"Shape"`, so `len(enums) > 1` is false and the arms-mix check does not fire — the
`resolve` layer's exact analogue of the identity hole §2.2 exists to close in `types_.py`. The matrix
has `non-exhaustive-imported-match` and `imported-type-mismatch`, but nothing that mixes
`(circle r)` with `(s/circle r)` in one `match`.

Of the four cases the brief asks about, three are covered: importing an unexported type
(`import-unexported-type`), an unbound alias in type position (`unimported-alias-type`), and a
qualified type whose member the target does not export (`wrong-alias-type` — the "module exists but
has no such type" and "has it but does not export it" cases share one code path, `rule-9`, so one
fixture is enough). **The fourth — a qualified case in a pattern whose scrutinee comes from another
module — is missing.**

**Amendment.** Add `semantic/mixed-module-match.agents` (`; expect: rule-4`), and require W5.6 to key
the `enums` set on (defining module, enum name), not the bare name. Also consider
`semantic/qualified-ctor-unexported.agents` (`(p/Hidden :x 1)`) — that runs through `_ctor`
(see F2), a different code path from `qualified_types()`, so `rule-9` there is a separate assertion.

### F9 — minor — `checker/gate.py` asserts the expected code is *among* the reported ones, not the only one

`checker/gate.py:58` is `ok = want in codes`. A new semantic fixture that reports its declared rule
**plus** spurious unrelated diagnostics passes. §5's "every semantic fixture matches its `; expect:`"
is therefore weaker than the phase's own reasoning implies (`AGENTS.md:55-58`). Not a defect this
phase introduces; state it in §5 so W11 does not lean on it. Cheap hardening if wanted:
`assert codes.count(want) and len(set(codes)) == 1` for the new fixtures only.

### F10 — minor — W5.4 is a no-op under W2.1

W5.4 says `check_type` "must skip type names that are the tail of a `QUALIFIED_TYPE` token". W2.1
makes `QUALIFIED_TYPE` a **single terminal**, so there is no `TYPE_NAME` token inside it, and
`check_type`'s `scan_values(… t.type == "TYPE_NAME")` (`checker/resolve.py:187`) finds nothing to
skip. Verified on a scratch build (see "Claims checked"): the Lark tree renders `type  s/Shape` as one
token. Drop the item or restate it as "check_type needs no change".

### F11 — minor — W13's citation points at the wrong block

`prelude/generate.py:66-69` is the **module header** block
(`"(module my/mod …", ":export [f] …", ":import [(other/mod :as o)] …"`); the `Shape` block is
`:74-75`. W13 says "the hard-coded 'Shape' block at `prelude/generate.py:66-69`". Both blocks need
editing (the export line at `:68` to show a type, and one signature line showing `o/Type`). Say which.

Baseline for W13's cost line verified: `wc -c prelude/HANDBOOK.md` → `12078`. ✓

### F12 — minor — imported call arity is unchecked, and re-export is undecided

`checker/resolve.py:235-237` returns before the arity check whenever the callee is not an `IDENT`, so
a qualified call `(s/circle)` with the wrong argument count gets no `arity` diagnostic from `resolve`
— only whatever `types_.py` happens to catch. Worth one line in §6 as a known gap the new fixtures
will make reachable.

Separately: whether module B may re-export a type it imported from A is not decided anywhere in §2.
W5.1 as written (`an entry in exported_types must be in mod.schemas or mod.enums`) makes it `rule-2`.
State that as the decision, or a plan reader will implement it either way.

---

## Risk verification

| plan's risk | reproduced? | command run | result |
|---|---|---|---|
| **R1** Rust `defenum` lowering broken; `E0412 cannot find type T` at `Node(T, Tree, Tree)`; `06-module` skipped in `check_corpus.py:22-23` hides it | **yes — and understated** | `.venv/bin/python backend/to_rust.py grammar/corpus/valid/06-module.agents > lib.rs; rustup run stable rustc --edition 2021 --crate-type=lib lib.rs` | 13 errors, not 2. `E0412 T` ×3 (enum + schema, as claimed), **`E0412 A`/`B` ×4 from `defun swap` — not in the plan (F1)**, `E0072 recursive type Tree has infinite size` (confirms Box indirection is required, plan says so), `E0391` (fallout), `E0423`/`E0425` for `s/concat`/`s/upper` (W9's scope). Fix as scoped is **insufficient**. |
| **R2** `grammar/validate.py` compares verdicts, not trees | **yes** | read `grammar/validate.py:81-90` | `lark_ok`/`ts_ok` are booleans; the only cross-grammar assertion is `if lark_ok != ts_ok: "GRAMMARS DISAGREE"` (`:89-90`). No tree is compared. Claim exact. |
| **R3** one source file → one artifact in both backends and the differential gate | **yes, and worse than stated** | read `backend/check_corpus.py:26-29`, `backend/differential.py:69-84`; grepped every `transpile(` call site | `check_corpus.transpile` shells out with a single path (`:27`); `build_python`/`build_rust` write one `cand.py`/`main.rs` from `src.read_text()` (`:72`, `:79`). Beyond the plan: `transpile()` takes **text, not a path** at all five call sites, and `bench/harness/run.py:133` has no file — see F7. Whole-closure linking is the right answer and does hold for Python (flat prefixed names) as well as Rust (nested `pub mod`); it changes **no existing fixture's output**, because every current fixture except `06-module` has no `:import` and the tuple tag stays bare (§2.4) — confirmed against `backend/t/smoke.py` and `bench/algo/histogram_agents.py`, both of which pin bare tags and would break if tags were qualified. |

---

## Claims checked

| plan's claim | cited location | verified? | note |
|---|---|---|---|
| `EXPORT_KW "[" IDENT* "]"` | `grammar/agents.lark:26` | ✔ exact | |
| `type: TYPE_NAME \| "(" TYPE_NAME type+ ")"` | `agents.lark:58-59` | ✔ exact | |
| `pattern: "(" IDENT pattern* ")" -> enum_pattern` | `agents.lark:89` | ✔ exact | |
| `ctor: "(" TYPE_NAME ctor_arg* ")"` | `agents.lark:114` | ✔ exact | |
| `TYPE_NAME` / `IDENT` regexes | `agents.lark:183`, `:184` | ✔ exact | |
| `QUALIFIED.2` lowercase-only; `MOD_PATH` beside it; `OPERATOR` has `/` | `agents.lark:192`, `:193`, `:174` | ✔ exact | the `.2` priority comment at `:189-191` confirms the `(s/concat x)` incident |
| tree-sitter `:export` takes `$.ident` only | `grammar.js:38` | ✔ exact | |
| `_type: choice($.type_name, $.type_app)`; `type_app` head | `grammar.js:103-104` | ✔ exact | |
| `ctor` type field is `$.type_name`; `enum_pattern` case is `$.ident` | `grammar.js:181`, `:216-218` | ✔ exact | |
| `qualified` regex lowercase-only | `grammar.js:236` | ✔ exact | |
| `mod.exports += [str(t) for t in opt.children[1:]]`, flat, no kind | `collect.py:113-114` | ✔ exact | |
| `known_types` is prelude + local only | `resolve.py:98` | ✔ exact | |
| `qualified_names` tests `member not in target.exports` | `resolve.py:157-168` | ✔ exact | |
| `check_type` scans `TYPE_NAME`, unknown ⇒ `rule-10` | `resolve.py:186-192` | ✔ exact | but W5.4's "skip the tail of a QUALIFIED_TYPE" is a no-op — F10 |
| `case_owner`/`case_params` are local-only | `collect.py:61-69` | ✔ exact | |
| `Con` carries a bare string; `unify` compares `a.name != b.name` | `types_.py:53-57`, `:113-115` | ✔ exact | note `types_.py:159` encodes a rigid variable as `Con("#"+name)` and `show:77` strips the `#` — W6.1 must not collide with that encoding; the plan does not mention it |
| `qualified()` resolves only `target.funs` | `types_.py:186-191` | ✔ exact | |
| `Loader` over ordered roots; `ROOTS = [corpus/modules]` | `resolve.py:73-88`, `gate.py:22,39` | ✔ exact | |
| `to_python.transpile` handles only defenum/defschema/defun; drops `module_decl` | `to_python.py:66-81` | ✔ exact | plan cites `:70-79`; the block is `:66-81` |
| unrecognised atom falls to `mangle(s)`; slash survives | `to_python.py:375`, `:30-37` | ✔ exact | |
| Python output for `06-module` is `return s/concat(s/upper(x), "!")` | run | ✔ | |
| …"which is not valid Python" | §1.4 | **✘ refuted as a gate claim** | `py_compile` exits **0** on it. See F4. |
| Rust output is `s/concat(s/upper(x.clone()), "!".to_string())` | `to_rust.py:286-295` | ✔ | |
| `SKIP_RUST`/`SKIP_PY` = `{"06-module.agents"}` | `check_corpus.py:22-23` | ✔ exact | **the only skips in the file**; `check_corpus.py` prints `06-module.agents ok skipped ok skipped` and `0 failure(s)`. No other fixture is skipped, so nothing else needs un-skipping this phase. |
| `validate.py:73` rglobs semantic; `gate.py:39` covers valid + modules | `validate.py:73`, `gate.py:39` | ✔ exact | but `validate.py` never covers `corpus/modules` — F6 |
| `closure_audit` buckets a qualified head separately and defers it | `closure_audit.py:32-37`, `:73-75` | ✔ exact | a `ctor` head is not queried at all, so `(t/Cell :value 1)` is invisible to it either way |
| baseline `checker/gate.py` → 0 failures; `pytest` → 47 passed; `HANDBOOK.md` = 12,078 chars | §1.6 | ✔ all three reproduced | |
| `ROADMAP.md:143-144` "cannot see across a module boundary for types"; `:208-211` `r-ea8c` | ROADMAP | ✔ exact | |
| §6.5 "`word: $ => $.ident` may interact badly with a PascalCase-tailed qualified token" | unverified in plan | **✔ refuted — it is fine** | I applied W2 and W3's exact five edits to scratch copies of both grammars, ran `tree-sitter generate` (exit 0) and Lark, and parsed a file using `s/Shape` in a param type, inside `(List s/Shape)`, as a return type, as a `ctor` head, as two pattern heads, and `(/ a b)` alongside. **Both grammars accept; `s/Shape` is one `qualified_type` token in tree-sitter and one token in Lark; `(/ a b)` still lexes as division; `(s/Cell :value 1)` lands on `ctor` in both.** W12 is still the right manual step, but the grammar work is de-risked. |
| §6.5 "contents of `checker/t/test_types.py` were not read" | — | read | 16 tests, none construct a `Con` with a module key; `Con(name, args)` is called positionally at `:44`, `:50`, `:55`. Adding a third positional field breaks nothing; adding it as the **second** positional would break every one. Say which in W6.1. |

---

## What would slip through the gate

A plan-conformant implementation that is wrong passes all seven commands in §5 in at least these
four ways. Ranked.

**1. Any syntactically-valid but semantically wrong Python lowering of a qualified name.**
`backend/check_corpus.py:44-46` runs `py_compile`, which accepts `s/concat(...)` today (exit 0,
demonstrated in F4). After W9, an emitter that produces `core_shapes__area` where it should produce
`core_shapes__describe`, or that prefixes with the *alias* instead of the module path (making two
aliases for one module emit two different names), compiles cleanly. `pytest` will not catch it —
`backend/t` and `bench/algo` never invoke a transpiler (F5). The only gate that *runs* the Python
output is `backend/differential.py`'s program mode, and W15 adds exactly **one** case: an imported
`defenum` matched and printed. It does not exercise an imported *function* call — which is what
`06-module`'s `shout` is, and the exact form the skip list was hiding.
**Additional check:** W15's case must call an imported function **and** match an imported union, and
reach the imported module through **two different aliases** in the same program. Two aliases is the
cheap discriminator: it fails immediately if the lowering keys on the alias rather than the module
path, and no other planned artifact tests it.

**2. Nominal identity implemented only where a fixture happens to look.**
W6.1 keys `Con` on the defining module. `semantic/imported-type-mismatch` catches the direction
"different modules must not unify". Nothing in the corpus catches the other direction — "two aliases
for one module **must** unify" — because a program that gets that wrong reports a spurious `type`
error on a *valid* fixture only if a valid fixture uses two aliases for one module, and none does.
W11's `valid/11-name-coexistence` uses a local `Shape` plus one alias.
**Additional check:** the W14 `checker/t` assertion for the two-alias direction is not optional and
must land with W6 (F3), and `valid/11-name-coexistence` should import `core/shapes` under two aliases
and pass a value between the two spellings.

**3. `resolve.py`'s cross-module blindness surviving inside a check that looks like it fired.**
`checker/gate.py:58` is `want in codes`, not equality (F9). So `non-exhaustive-imported-match` passes
if the checker reports `rule-4` **and** a spurious `rule-2: s/circle is not a case of any union` from
`resolve.py:358` — which is exactly what a half-done W5.6 produces: `pattern()` fixed to not crash,
`exhaustive()` left keyed on bare enum names. The fixture is green and the arms-mix bug of F8 ships.
**Additional check:** for the new semantic fixtures only, assert the reported code set is exactly
`{want}`, and add `semantic/mixed-module-match.agents` (F8).

**4. Grammar drift the conformance gate structurally cannot see.**
`grammar/validate.py:85-90` compares verdicts. Both grammars can accept every fixture while
disagreeing about what `s/Shape` *is* — and `corpus/modules`, where two of the three new grammar
forms live, is not parsed by that gate at all (F6). Fixing F6 closes the second half; W12 (manual)
is the only cover for the first, and the plan is right to report it as manual. My scratch build
shows the two trees agree for every planned form, so the residual risk here is low — but it is
residual, not gated.

Not slipping through, for the record: the **Rust** column of `check_corpus.py` is a genuine check —
rustc rejects today's output with 13 errors, and no cosmetic fix makes those go away.
