# Phase 8 — Porting the Closure Audit's Call-Head Extractor to the Native AST (asl-selfhosted-runtime-v1)

*v2 — reconciliation. Folded from REVIEW-scope.md and REVIEW-architect.md (both
approve-with-amendments): rule 9 now decides qualified-ctor vs qualified-callee
lexically by head spelling (B1), rule 11 is conditioned on the head's lexical
category so literal heads are never bucketed (B2), the Item 2 test 1 probe pins
the expr-position `cons` rule and the new qualified/literal cases against both
extractors (B3), the Item 3 source-collection citation is corrected to `:82-94`
(N1), and Item 4's gate is described as a post-merge regression sweep rather
than a red-now gate (N2).*

## Acceptance criterion

```
.venv/bin/python grammar/closure_audit.py && .venv/bin/python -m pytest tools/tests/test_closure_native_equivalence.py -q && ! grep -qE 'tree.sitter|tree_sitter|QUERY|run_query|subprocess' grammar/closure_audit.py
```

`grammar/closure_audit.py` audits all 107 builtins using the native self-hosted AST
(`packages/asl-parser`), prints the same head counts it prints today, `exec_coverage.check()`
stays green at 107/107 matching `prelude/coverage.lock`, and the file no longer imports or
invokes tree-sitter in any form.

## Context & Motivation

`grammar/closure_audit.py` extracts call heads with a single tree-sitter query
(`grammar/closure_audit.py:39-45`) executed by the CLI (`run_query`,
`grammar/closure_audit.py:47-78`). The rest of the gate — the `undefined` verdict and
`exec_coverage.check()` (`grammar/closure_audit.py:107`) — is independent of the extractor.
This phase replaces **only** the extraction half; `exec_coverage` and the verdict semantics
are untouched, so "matches `coverage.lock`" is unaffected by construction.

**The equivalence contract (orchestrator decision 1).** The native walker must reproduce
tree-sitter's exact `calls` / `defs` / `qualified` sets over the same inputs
(`grammar/corpus/valid/*.agentscript` + the spec's ```lisp``` blocks containing `defun` or
`defschema`, `grammar/closure_audit.py:82-94`). Baseline, measured this session by running
the current gate:

```
qualified heads (checker owns)  : 10
builtins defined in section 6 : 107
definitions found in sources  : 137
distinct call heads           : 156
executed builtins             : 107/107  (100%)

OK: spec and corpus are closed, and every builtin is executed
```

Exit code 0. A set-equality test against a live tree-sitter baseline (kept **inside the test
file**, not in the gate) is the migration gate: without it, a port could change the printed
counts silently — the exact failure mode decision 1 forbids.

**Why classification is the hard part.** The native AST (`packages/asl-parser/src/ast.asl`)
keeps defun bodies as generic `rd/SExpr` (`sexpr-atom | sexpr-list | sexpr-vect`) with no
`call` tag, no pattern/expression distinction, and no spans. Tree-sitter's query captures a
head only where its grammar gives that position a `call` node, so the walker must recover
position from structure. The rules below were derived from
`grammar/tree-sitter-agentscript/grammar.js` and verified against the measured baseline
buckets:

- **Typed top forms, not raw S-expressions.** Work from `TopForm`: skip `top-module` and
  `top-schema` entirely (the query captures nothing from them — a module header's import spec
  `(core/strings :a s)` would otherwise pollute the qualified bucket); `top-defun` adds
  `.-name` to `defs`; `top-enum` adds every `EnumCase` `.-name` to `defs`. **Defschema names
  and enum names are not definitions** — the query has no rule for them
  (`grammar/closure_audit.py:43-44`); only `defun` and `enum_case` names are captured.
- **Expr-mode list classification by head text.** Heads are already verbose: the reader's
  `normalize-form` resolves `mt`→`match`, `df`→`defun` etc. at read time for every list.
  1. `match` → walk the subject (`items[1]`); each arm list → walk `items[1:]` only. Arm
     patterns are `_pattern` productions (grammar.js:224-248) and are never captured — the
     corpus proves both dangerous shapes: the enum pattern `((t/leaf) 0)`
     (`grammar/corpus/valid/10-imported-generic-types.agentscript:12`) and
     `((cons h t) (+ h (sum-list t)))` (`grammar/corpus/valid/02-match.agentscript`).
  2. `cond` → each clause list → walk **all** its elements (the condition is an `_expr`,
     grammar.js:167-170); a `:else` head is a keyword atom, a no-op.
  3. `let` → `items[1]` is the bindings vector; each binding list → walk elements `[1:]`
     (the name is a binder, grammar.js:155-158); `items[2:]` walked as exprs.
  4. `fn` → skip the optional `!`, the params vector, and `->` + the return-type node; walk
     the remaining body (grammar.js:186-192). Same for the typed `DefunNode` — params and
     ret-type are already strings.
  5. `try`, `if` → their own productions; walk their argument exprs, never bucket the head.
  6. `ok err some none pair list` → `constructor_call` (grammar.js:200-207); walk args,
     never bucket. **`cons` is NOT in this set**: `_expr` (grammar.js:138-152) has no cons
     production — only `cons_pattern` (grammar.js:243) — so an expr-position `(cons a b)`
     *is* a call for tree-sitter. (The scout's exclusion list is wrong on `cons`; today's
     input set contains no expr-position cons — measured, `cons ∉ calls` — so both rules
     pass today, but the walker must follow the grammar to stay exact for future sources.
     The probe in Item 2 test 1 pins the corrected rule with an expr-position `(cons h t)`,
     since no corpus input exercises it.)
  7. Head starts with `.` → `field_access` (e.g. `(.-x p)`, corpus 01/10); walk the target
     and args, never bucket.
  8. Head starts with `:` → keyword-headed list (ctor args, `:else` clauses); skip.
  9. Head contains `/`: classify **lexically by the head's spelling** — the head is a
     **qualified ctor** iff its final `/`-separated segment starts with an uppercase letter
     (the `qualified_type` shape, grammar.js:269:
     `/[a-z][a-z0-9]*(-[a-z0-9]+)*\/[A-Z][A-Za-z0-9]*/`); bucket nothing and walk
     `items[1:]` (keyword atoms are no-ops). Otherwise — lowercase tail, the `qualified`
     shape (grammar.js:266) — it is a **qualified callee** → `qualified` bucket, walk args
     as exprs. The two regexes are disjoint and exhaustive for `/`-heads, so this test is
     total by construction, and unlike a positional heuristic it covers the zero-argument
     qualified ctor `(t/Cell)` (legal: `repeat($.ctor_arg)` at grammar.js:211 admits zero),
     which has no second element to inspect.
  10. Head is PascalCase → record ctor (`ctor`, grammar.js:209-215) → bucket nothing, walk
      ctor-arg values.
  11. Otherwise → **calls** bucket, but **only if the head lexically is an `ident`** (kebab,
      grammar.js:271 — full-text equality, never prefix: the ident regex is greedy, so
      `ok-box` is not a prefix match for `ok`) **or an `operator`** (`= + < / …` including
      `-`, grammar.js:261), plus `cons` per rule 6 — walk args as exprs. A **literal head**
      (`int` / `float` / `string` / `bool` / `unit`) is a no-op: `call.callee` is `_expr`
      (grammar.js:218-219), so `(-1 2)` parses as a valid `call` whose callee is an `int`
      node — but the query captures only `ident`/`operator`/`qualified` callees
      (`grammar/closure_audit.py:40-42`), so tree-sitter buckets nothing for it, and
      neither may the walker. (The six IoError ctors `already-exists interrupted
      invalid-path not-found other permission-denied` are kebab idents, each measured **IN**
      the baseline calls set.)
  12. A list headed by another list (e.g. `((f x) y)`) → walk the head and the args as
      exprs, classify nothing at that level. Atoms are no-ops; the empty list (unit) is a
      no-op.

**Exposure path.** `packages/asl-parser/tests/harness.py` `run_asl` transpiles a driver and
returns exported `df`s as Python callables; `tools/native_parser.py:43` already caches
`run_asl(HARNESS_DIR / "reader_test.asl")` and unwraps the `(Result … ParseError)` tagged
tuple (`("ok", payload)` / `("err", {msg, line, col})`; exported hyphens surface as
underscores: `render-all` → `render_all`). Adding a `df closure-heads` + its name to `:x`
in `reader_test.asl` needs **no parser change**.

**Deep walking.** Bodies nest; the transpiled runtime recurses per ASL call, so the walker
must be iterative — mirror the doubling-budget work list of `r-run`
(`packages/asl-parser/src/reader.asl:109-122`). `a/parse` itself is verified iterative to
3000-deep nesting (measured this session via `proj-parse`).

**Output protocol.** The walker is written in ASL; `closure_audit.py` consumes it through
`run_asl` and stops importing tree-sitter entirely (decision 2). Input scope and the
`undefined = calls − (builtins ∪ defs ∪ special_forms)` verdict are preserved exactly
(decision 3).

---

## Work Items

### Item 1 — Add the native closure walker `closure-heads` to the parser driver

**What.** Edit `packages/asl-parser/tests/reader_test.asl`. Add a `dfs ClosureHeads` record
with three `(List String)` fields — `:calls`, `:defs`, `:qualified` — and a
`df closure-heads [(src String)] -> (Result ClosureHeads a/ParseError)` that parses with
`a/parse`, extracts `defs` from `top-defun` names and `top-enum` case names, walks every
`DefunNode` `.-body` S-expr with the expr-mode classification of the Context section, and
returns the three buckets (order within a list is irrelevant; the Python side set()s them).
Add `closure-heads` (and `ClosureHeads` if the export list wants the type) to the module's
`:x`. Implement the walk **iteratively** with a doubling-budget work list mirroring
`reader.asl`'s `r-run`; encode mode (expr vs ctor-args) in the work item so patterns are
never enqueued. Keep nesting ≤ 4 levels (`@pcp:c-adc8`): split the head-classification into
small early-return helper `df`s rather than one deep `cond`. Local predicates it needs
(PascalCase head test, keyword test, qualified-ctor tail test) are driver-local —
`ast.asl`'s `pascal-name?` is not exported and the parser module's surface stays untouched.

**Why.** This is the only place the classification rules exist; the driver surface is what
lets Python consume them without a second parser. Implementing before the equivalence test
exists would mean grading the walker with itself.

**Gate.** Fails now with `KeyError: 'closure_heads'`; passes when done.

```
.venv/bin/python -c "
import sys; from pathlib import Path
sys.path.insert(0, 'packages/asl-parser/tests')
from harness import run_asl
d = run_asl(Path('packages/asl-parser/tests/reader_test.asl'))
r = d['closure_heads'](Path('grammar/corpus/valid/02-match.agentscript').read_text())
assert r[0] == 'ok', r
b = r[1]
assert {'sum-list', 'list-head', '+', '=', '<', '/'} <= set(b['calls']), b
assert {'sum-list', 'first-or', 'safe-div', 'describe', 'classify'} <= set(b['defs']), b
for h in ('cons', 'list', 'ok', 'err', 'some', 'none', 'pair'):
    assert h not in b['calls'], (h, b)
assert set(b['qualified']) == set(), b
r2 = d['closure_heads'](Path('grammar/corpus/valid/10-imported-generic-types.agentscript').read_text())
assert r2[0] == 'ok', r2
b2 = r2[1]
for h in ('t/leaf', 't/Cell', 't/Tree'):
    assert h not in b2['calls'] and h not in b2['qualified'], (h, b2)
print('probe ok')
"
```

The asserted expectations are the tree-sitter semantics measured this session: 02-match's
`cons`/`list`/`ok`/`err` heads sit in patterns and `constructor_call`, so none reach
`calls`; 10-imported-generic-types' `(t/leaf)` pattern and `(t/Cell :value 1)` ctor reach
neither bucket.

---

### Item 2 — Add the set-equality migration gate `tools/tests/test_closure_native_equivalence.py`

**What.** Create `tools/tests/test_closure_native_equivalence.py` (import pattern: follow
`tools/tests/test_native_parity.py` — path insertion + `run_asl`). Three tests:

1. `test_probe_buckets_match_the_grammar` — a crafted probe source, asserted against
   **hand-declared** buckets derived from grammar.js, for both extractors independently:
   native AND the tree-sitter baseline must each equal the hand sets. This is the guard
   against two implementations sharing one misreading.

   Probe source (verbose spellings; never checked by the checker — it lives in the test):

   ```
   (module probe/t
     :d "probe"
     :x [f])

   (dfe Opt :d "an enum" (:case some-ish [(v Int64)] "s") (:case none-ish "n"))

   (df f [(p Pt) (xs (List Int64))] -> Int64
     (match xs
       ((cons h t) (g/area (.-x p) (f t) (cons h t) (- 1) (t/Cell) (-1 2)))
       ((list)     (let [(y 1) (z (ok-box (h? xs)))]
                     (cond
                       ((< y z) (some-ish (t/Cell :value (inner 2))))
                       (:else   (if (= y z) (try (err-width (pair y z))) 0)))))))
   ```

   Hand-declared expectations — `calls = {f, ok-box, h?, <, some-ish, inner, =, err-width,
   -, cons}`, `qualified = {g/area}`, `defs = {f, some-ish, none-ish}`. In detail: `f` is
   the arm-body callee; `ok-box` and `h?` sit in a `let` binding body; `<` and `=` are
   cond/if conditions; `some-ish` and `inner` are a ctor call and its arg; `err-width` is
   the try body; `-` is an operator head (`(- 1)` — the operator token, not the `-1`
   literal); `cons` appears in **expr position** in the first arm body
   (`_expr` has no cons production, so it is a call there — rule 6) while the `((cons h t)
   …)` match-arm pattern contributes nothing; `g/area` is a qualified callee (lowercase
   tail, rule 9); `t/Cell` appears **both** as a zero-arg qualified ctor `(t/Cell)` and as
   `(t/Cell :value …)` — uppercase tail, qualified ctor, neither bucketed (rule 9);
   `-1` is a literal head (`(-1 2)` is a `call` node with an `int` callee that the query
   captures nothing from — rule 11); `(.-x p)` is a field access (rule 7); `(pair y z)` is
   `constructor_call` (rule 6); `Opt` and `Pt` are not definitions; `some-ish` is a call
   *and* a definition. Both extractors must produce these sets independently.

2. `test_native_buckets_equal_tree_sitter_over_inputs` — build the input set exactly as
   `grammar/closure_audit.py:82-94` does (corpus/valid glob + spec ```lisp``` blocks with
   `defun`/`defschema` written to temp files; **independent reconstruction**, deliberately
   not imported from the gate, so the test pins the input scope rather than trusting it),
   run the tree-sitter baseline (a verbatim copy of the pre-port `QUERY` and capture parsing
   of `grammar/closure_audit.py:39-76`, kept only in this test), run `closure-heads` per
   file and union, then assert `calls`, `defs` and `qualified` are pairwise equal — printing
   the symmetric difference on failure. Hard-fail on zero files or an empty native bucket
   union, mirroring the old guard at `grammar/closure_audit.py:74`.

3. `test_walker_is_iterative_on_deep_sources` — `"(defun deep [] -> Int64 " + "(+ 1 " * 2000
   + "1" + ")" * 2000 + ")"`; assert the native result is `ok` and `calls == {"+"}`. A
   recursive walker dies with `RecursionError` here; `a/parse` is already proven iterative.

**Why.** Decision 1's migration gate. It must exist **before** the gate is ported: a port
without it can move the printed counts silently, and the pytest battery then keeps grading
the drifted numbers. The probe's hand-declared sets are also the only place the three
rules that today's corpus cannot exercise are pinned: expr-position `cons`, the
zero-argument qualified ctor, and the literal-headed call.

**Gate.** Fails now (file absent); passes when Item 1's walker is exact.

```
.venv/bin/python -m pytest tools/tests/test_closure_native_equivalence.py -q
```

---

### Item 3 — Port `grammar/closure_audit.py` to the native driver and delete the tree-sitter surface

**What.** Edit `grammar/closure_audit.py`:

- Delete `TS_DIR`, `TS_BIN` (`:27-28`), `QUERY` and its comment block (`:33-45`),
  `run_query` (`:47-78`), and `import subprocess` (`:16`). Delete nothing else.
- Add `HARNESS_DIR = ROOT.parent / "packages" / "asl-parser" / "tests"`, a sys.path insert
  of it, `from harness import run_asl`, and a module-level cached driver (the
  `tools/native_parser.py:40-44` pattern: load once, reuse). A `_native_buckets(src)`
  helper calls `closure_heads`, unwraps the Result — `("err", e)` raises `RuntimeError`
  carrying `f"{line}:{col}: {msg}"`, preserving the old "fail loudly, never silently close"
  property of `run_query` — and returns the three sets.
- Factor the source collection of `main()` (`:82-94` — the corpus/valid glob, the
  `tempfile.mkdtemp()`, the `re.findall` loop, and the `sources.append`) into
  `collect_sources()` (same corpus/valid glob + spec-block filter, same temp-file shapes)
  so the input set has one definition inside the gate; `collect_sources()` returns the
  list and the `run_query(sources)` call site (`:95`) keeps its replacement at the call
  site; the equivalence test keeps its independent copy by design.
- Replace the `run_query` call with a per-source union of `_native_buckets`; keep the
  empty-bucket `RuntimeError` guard with its non-empty-paths precondition.
- Keep `main()`'s print lines, the `undefined` verdict, and `exec_coverage.check()`
  (`:107`) **byte-identical** in behaviour. Update only the module docstring's extraction
  sentence (tree-sitter → native AST) and the deleted comment block.

**Why.** Decision 2: the gate stops importing/using tree-sitter entirely, while decisions 1
and 3 pin counts, input scope, verdict semantics and the coverage lock.

**Gate.** The grep fails now (tree-sitter identifiers still present); the audit run must
then reproduce the baseline output verbatim and exit 0.

```
! grep -qE 'tree.sitter|tree_sitter|QUERY|run_query|subprocess' grammar/closure_audit.py && .venv/bin/python grammar/closure_audit.py
```

Expected stdout (measured baseline, this session):

```
qualified heads (checker owns)  : 10
builtins defined in section 6 : 107
definitions found in sources  : 137
distinct call heads           : 156
executed builtins             : 107/107  (100%)

OK: spec and corpus are closed, and every builtin is executed
```

Any other head count is a defect in Items 1-2 that the equivalence test failed to catch —
stop and diagnose, do not adjust the expected numbers.

---

### Item 4 — Full gate battery over the ported toolchain

**What.** Run the complete AGENTS.md battery. The new walker lives in `packages/`, so
`checker/gate.py` (semantic checks over every `packages/**/*.asl`), `check_corpus.py`
(transpiles it), `monomorphism.py` (instantiates every builtin it uses) and
`backend/differential.py` now grade code they have never seen; the pytest leg includes the
new equivalence suite. Fix nothing by weakening a gate — a failure here is a finding, not a
tuning input.

**Why.** The walker is the first non-test, non-parser consumer of the native AST at this
depth; only the whole battery proves the port added no regression outside the two files it
edited.

**Gate.** This is **not** a red-now gate: the battery is green on `main` today, so it
passes before any Phase 8 work exists. It is the **post-merge regression sweep** — it
passes only if Items 1-3 introduce no regression outside the two files they edit, and a
failure after merge is a finding against Items 1-3, never a tuning input.

```
.venv/bin/python grammar/validate.py && .venv/bin/python grammar/closure_audit.py && .venv/bin/python prelude/generate.py --check && .venv/bin/python checker/gate.py && .venv/bin/python bench/token_frames.py --check && .venv/bin/python bench/token_projection.py --check && .venv/bin/python tools/doc_examples.py --quiet && .venv/bin/python backend/check_corpus.py && .venv/bin/python backend/monomorphism.py && .venv/bin/python backend/differential.py && .venv/bin/python -m pytest backend/tests bench/algo checker/tests tools/tests -q
```

---

## Risks

- **`ClosureHeads` record lowering is unverified.** Expected Python shape is
  `("ok", {"calls": [...], "defs": [...], "qualified": [...]})` by analogy with `ParseError`
  → dict and `render-all`'s Result tuple; no list-of-strings record has been unwrapped
  through this FFI before. Item 1's gate pins the shape; if list lowering differs, the
  sanctioned fallback is returning one joined String (heads never contain `,`, `|` or
  newline) — the equivalence test remains the arbiter either way.
- **The `cons` correction contradicts the scout's brief.** The scout's exclusion list
  included `cons`; grammar.js has no expr-position cons production (verified: `_expr`
  grammar.js:138-152, only `cons_pattern` at :243). The plan follows the grammar. Both rules
  pass today's corpus (measured: `cons ∉ calls`), so the equivalence gate cannot
  distinguish them — the probe's expr-position `(cons h t)` with `cons ∈ calls`, asserted
  against **both** extractors, is what encodes the corrected rule: a walker implementing
  the scout's exclusion fails the probe even though every other gate would stay green.
- **Qualified-ctor vs qualified-callee is lexical and total (v2).** The `qualified`
  (grammar.js:266) and `qualified_type` (grammar.js:269) regexes are disjoint and
  exhaustive for `/`-heads, decided by whether the final segment starts uppercase — no
  second-element heuristic remains to be wrong, and the zero-arg ctor `(t/Cell)` is covered
  by construction. The probe pins both arities plus a qualified callee (`g/area`). The
  equivalence gate pins current behaviour beyond the probe.
- **Gate runtime.** `closure_audit.py` now transpiles the parser driver once per run
  (cached module-level). The parity suite already pays this cost; if the battery leg shows
  an unacceptable regression, that is a decision for the orchestrator, not a reason to
  cache across processes.
- **Spec-example coverage depends on Phase 7's migrations holding**: every ```lisp``` block
  the audit reads must parse natively. The equivalence test's zero-file and empty-bucket
  guards turn a silent acceptance gap into a loud failure.

## Out of scope

- **`exec_coverage.py` and `prelude/coverage.lock`** — the coverage half of the gate is
  untouched by design; the 107/107 figure rides through unchanged.
- **Tree-sitter itself** — it remains the reference grammar for `validate.py`, the parity
  suite and editor tooling; only the closure audit's *use* of it is deleted. The baseline
  QUERY survives only inside the equivalence test.
- **`checker/gate.py`, `backend/*`, `tools/transcoder.py`, `grammar/agentscript.lark`** —
  their native migrations are later phases of the same roadmap.
- **`reader_test.asl`'s existing exports** (`proj-parse`, `proj-heads`, `render-all`) —
  untouched; the phase only adds to the driver.
- **Any change to `prelude/vocab.py`'s `special_forms()`** — its inclusion of the six
  IoError ctors is what keeps them `known` despite being call heads; the baseline verdict
  depends on it exactly as it stands.
