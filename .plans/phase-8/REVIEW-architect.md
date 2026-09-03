# REVIEW-architect — Phase 8 PLAN.md, lens: equivalence contract

**Verdict: approve-with-amendments**

Lens: is the walker's head-classification provably equivalent to tree-sitter's
grammar? All 12 rules were checked against
`grammar/tree-sitter-agentscript/grammar.js` productions, the QUERY against
`grammar/closure_audit.py`, the lowering against `backend/to_python.py`, and
four ambiguous shapes were probed live with the tree-sitter CLI against a
scratch file in `/tmp/tsprobe/`. The baseline gate was re-run: 10 / 107 / 137 /
156 / 107/107, exit 0 — matches the plan's recorded baseline.

Rules verified as written (no finding): rule 1 match subject+arm-bodies
(grammar.js:174-179, patterns :224-248 never captured); rule 2 cond clauses
(:168-172, `:else` keyword head is a no-op); rule 3 let bindings skip the name
(:154-159); rule 5 try/if (:161-166, :181); rule 6 constructor_call heads
(:200-207); rule 7 field_access (:214-216, field_ref :273 always `.-`-prefixed);
rule 12 list-headed callee (:218-220 callee is `_expr`, inner `call` node still
captured); defs bucket from `defun` name + `enum_case` name only
(closure_audit.py:43-44 ↔ ast.asl:47, :24); defschema/module names excluded.
The `cons` correction is right: `_expr` (grammar.js:137-152) has no cons
production, only `cons_pattern` (:243), so an expr-position `(cons a b)` parses
as `call` with ident callee and IS captured — verified also that every `(cons`
occurrence in the current input set (corpus + ```lisp blocks) sits in a match
arm pattern position, so `cons ∉ calls` today holds and the equivalence test
cannot distinguish the two rules.

## Findings

1. **[blocking] Rule 9's disambiguator is not the grammar's.** The plan
   decides qualified-ctor vs qualified-callee by "second element is a keyword
   atom". The grammar decides it lexically and completely: `qualified`
   (all-lowercase both sides, grammar.js:266) can only be a `call` callee, and
   `qualified_type` (lower/Pascal, grammar.js:269) can only be a `ctor` type
   (:210). The two regexes are disjoint and exhaustive for `/`-heads, so the
   lexical test is correct by construction and the heuristic is not: a
   zero-argument qualified ctor `(t/Cell)` — legal, `repeat($.ctor_arg)` at
   :211 admits zero — has no second element, so rule 9 as written buckets it as
   a qualified callee, while tree-sitter captures nothing (probed: parse tree
   shows `(ctor type: (qualified_type))`, query emits no capture). No current
   input contains the shape (grep over corpus + spec: zero hits) and the probe
   test omits it, so no planned gate can catch the divergence. **Disposition:**
   rewrite rule 9 to classify by head text against the qualified_type shape
   (PascalCase tail) vs qualified shape; add `(t/Cell)` and a zero-arg
   `(s/version)` (probed: `call` with qualified callee, captured) to the probe
   with hand-declared buckets.

2. **[blocking] Rule 11 "otherwise → calls" captures heads tree-sitter never
   captures.** The QUERY captures only callee nodes of type `ident`, `operator`
   or `qualified` (closure_audit.py:40-42); `call.callee` is `_expr`
   (grammar.js:218-219, :137-152), so a literal-headed list like `(-1 2)` is a
   valid `call` whose callee is an `int` node and is captured by nothing —
   probed: `(call callee: (int -1))`, query emits nothing. The same holds for
   string/bool/unit heads. Rule 11 as written ("otherwise") buckets `-1`. No
   current input has a literal-headed call in expr position
   (grammar/corpus/valid/29-literals.agentscript:51 uses `-1` only as a match
   *pattern* literal, which rule 1 correctly skips), so the equivalence test
   passes either way. The plan's stated guard — hand-declared probe sets — does
   not include the case. **Disposition:** condition rule 11 on the head's
   lexical category (ident grammar.js:271 / operator :261 / qualified :266) and
   declare everything else a no-op; add `(-1 2)` to the probe with `cons`-style
   hand-declared expectation "captured by neither extractor", plus `(- 1)` to
   pin the operator head (`-` ∈ calls; spec AGENT_SPEC_CORE.md:193 documents
   the `-1` vs `- 1` token split).

3. **[blocking] The corrected `cons` rule is pinned by no declared expected
   result.** The plan's own Risks section says the probe's hand-declared sets
   are what encode the cons correction, but the probe contains `cons` only in
   pattern position (`((cons h t) …)` match arm). If the walker implements the
   scout's exclusion instead, every gate in Items 1-3 passes green: corpus has
   no expr-position cons, and the equivalence test compares two implementations
   that agree on the inputs that exist. **Disposition:** add an expr-position
   `(cons (first-a) (rest-b))`-style form to the probe (never checked by the
   semantic checker — the probe lives in the test, as the plan notes) with
   hand-declared `cons ∈ calls`; both extractors must independently produce it.

4. **[non-blocking] Rule 9's wording misreads the ctor shape.** `ctor_arg` is
   a flat `keyword value` pair inside the ctor form (grammar.js:210-212;
   corpus 10:17 `(t/Cell :value 1)`), not a nested arg list; "walk the ctor-arg
   values (each arg list's `items[1:]`)" invites an implementation that looks
   for sub-lists that do not exist. Walking `items[1:]` with keyword atoms as
   no-ops is equivalent and is what the native AST actually holds. The probe
   gate catches a gross misreading (`inner` would vanish from `calls`), so this
   is a wording fix.

5. **[non-blocking] Rule 4 must skip the fn return type as one item, including
   when it is a list.** `type_app` (grammar.js:133) makes `(List Int64)` a
   single type node that is a *list* in the S-expr stream; if it is walked as
   an expression, a qualified type-app head (`(t/Foo a)` return type) is
   bucketed by rule 9 while tree-sitter captures nothing from type positions.
   No current input has this shape (grep of `(fn` forms: atom return types or
   no arrow), so this is an explicitness fix: after `->`, consume exactly one
   item, atom or list, and never walk it.

6. **[non-blocking] Citation range for the deletion in Item 3.** The rationale
   comment block above `QUERY` starts at closure_audit.py:31, not :33; deleting
   from :33 leaves two stale lines describing a query that no longer exists.

7. **[non-blocking] Probe coverage gap for rule 12.** A list-headed callee
   `((f x) y)` (grammar.js:218-220: inner `call` still captured via its own
   callee) is declared in the rules but appears in neither probe nor, by
   inspection, the corpus; adding one probe instance with `f ∈ calls` pins it.

8. **[non-blocking] Lowering shape: the plan's expected Python shape is
   CORRECT; the fallback is likely unnecessary.** A `dfs` with three fields
   lowers to `def Name(calls, defs, qualified): return {"calls": calls, …}` —
   dict keyed by raw field names (backend/to_python.py:189-196, verified lines
   195-196 emit `"{f}": mangle(f)`); `ok`/`err` lower to the runtime tagged
   tuples `("ok", v)` (prelude.json `ok`/`err` py templates →
   backend/runtime.py:13-14); `.-field` access lowers to dict indexing
   (to_python.py:346-351); PascalCase schema names are not mangled
   (to_python.py:140 keeps `decl_name` verbatim; mangle :38-43 only touches
   kebab and five Python keywords — `qualified` is safe); `List String` is a
   plain Python list (`list` py template `[{*}]`). The existing driver already
   round-trips a Result of a defschema payload through `run_asl`
   (packages/asl-parser/tests/reader_test.asl:120 `render-all` →
   tools/native_parser.py:43-55; harness.py:34-48). Item 1's gate asserting
   `r[1]['calls']` pins the remaining novel combination (record of three
   list-of-string fields as ok payload); keep the joined-string fallback as
   written, but expect not to use it.

9. **[non-blocking] Iterative deep-walk is sound.** `r-run`'s doubling-budget
   work list (packages/asl-parser/src/reader.asl:109-118, initial budget 64 at
   :122) recurses O(log n) ASL calls; each ASL call is one Python frame
   (to_python.py defun emission), and the fold step runs in a Python for-loop
   (backend/runtime.py:189-193, prelude.json:850-856), so a 2000-deep body
   cannot overflow. Item 2 test 3 is the right gate: it fails loudly with
   `RecursionError` on a recursive walker. Copy the 64 initial budget.

## Notes on interrogations that came out clean

- Unary minus does not exist as a form: `-1` is one literal token
  (grammar.js:255-256), `(- x)` is an operator-headed call captured as `-`
  (:261 includes `-`), handled by rule 11 once lexical-conditioned (finding 2).
- `ok-box`/`err-width` style heads: the ident regex (grammar.js:271) is
  greedy, so head tests must be full-text equality, never prefix; the probe
  already exercises both.
- `some-ish` as call AND definition: `enum_case name` capture
  (closure_audit.py:44 ↔ grammar.js:91-93) plus ident-callee capture; probe
  hand-set declares both — verified against the grammar.
- `top-module` skip is correct and for a better reason than the plan states:
  `ModuleNode` is fully typed (imports are string pairs, ast.asl:32), so no
  import-spec S-expr exists to pollute anything; and `build-module` returns the
  module's decls as TOP-LEVEL SIBLINGS of the `top-module` node
  (packages/asl-parser/src/ast.asl:425), so iterating the TopForm list captures
  every module-internal defun/enum exactly once. The walker must not also
  descend into `ModuleNode.-defs` (ast.asl:33) — harmless for sets, wrong in
  principle.
- Head normalization is safe for classification: `normalize-form` rewrites only
  the heads in the projection table (ast.asl:275-288, :63-79) at read time for
  EVERY paren list (ast.asl:330-331), and the table matches grammar.js:22-37
  exactly (`df/def/defun`, `mt/match`, `:f/:field`, `:c/:case`).
- Parse-reject divergence on spec blocks fails loudly: `_native_buckets` raises
  on `("err", …)` per Item 3, mirroring `run_query`'s exit-status check
  (closure_audit.py:64-67).

## Risks (unverified)

- Runtime list-operation asymptotics (`list-cons`/`list-append` in
  backend/runtime.py) were not inspected; a quadratic walker would make Item 2
  test 3 slow, not wrong — the test asserts the verdict, not wall time.
- Whether `checker/gate.py` / `backend/check_corpus.py` accept the new driver
  exports is delegated to Item 4's battery by design; not pre-checked here.
- Tree-sitter's error-recovery behaviour on ill-formed shapes (probed: wrong
  arity `(ok 1 2)` still yields `constructor_call` + ERROR child, no capture)
  is irrelevant because every audited input is well-formed; logged in case the
  input scope ever widens to non-corpus sources.
