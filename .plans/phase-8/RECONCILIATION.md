# RECONCILIATION — Phase 8 PLAN.md v2

Reviews folded in: `REVIEW-scope.md` (scope & correctness), `REVIEW-architect.md`
(equivalence contract). Both verdicts: approve-with-amendments. Five findings
dispositioned by the orchestrator; five rows below — every finding has exactly one.

| # | Finding | Disposition | Amendment in PLAN.md v2 |
|---|---|---|---|
| B1 | [blocking, architect] Rule 9's "second element is a keyword atom" disambiguator is not the grammar's; the zero-arg qualified ctor `(t/Cell)` has no second element and would be mis-bucketed as a callee. | **accept** | Rule 9 rewritten to classify lexically by head spelling: qualified ctor iff the final `/`-separated segment starts uppercase (`qualified_type`, grammar.js:269); otherwise qualified callee (`qualified`, grammar.js:266). The two regexes are disjoint and exhaustive for `/`-heads, so the test is total and covers the zero-arg ctor by construction. Probe (Item 2 test 1) amended to include `(t/Cell)` (zero-arg ctor — neither bucket) alongside the existing `(t/Cell :value 1)`; hand-declared expectations state both arities. Context line range and Risks bullet 3 rewritten to match. Citations verified this session: grammar.js:266/:269 regexes, `repeat($.ctor_arg)` at :211. |
| B2 | [blocking, architect] Rule 11 "otherwise → calls" over-captures: the QUERY captures only `ident`/`operator`/`qualified` callees (closure_audit.py:40-42) while `call.callee` is `_expr` (grammar.js:218-219), so a literal head like `(-1 2)` is a `call` node captured by nothing. | **accept** | Rule 11 now conditioned on the head's lexical category: **calls** only for `ident` (kebab, full-text equality) and `operator` heads (including `-`), plus `cons` per rule 6; literal heads (`int`/`float`/`string`/`bool`/`unit`) are explicit no-ops. Probe amended with `(-1 2)` (literal head — neither bucket) and `(- 1)` (operator head — `-` ∈ calls); hand-declared `calls` set gains `-`. Citations verified: QUERY capture lines at closure_audit.py:40-42, `operator` includes `-` at grammar.js:261, `int` literal at :256. |
| B3 | [blocking, architect] The corrected `cons` rule (expr-position cons IS a call) is pinned by nothing: the probe has `cons` only in match-arm pattern position, so a walker implementing the scout's exclusion passes every gate. | **accept** | Probe amended to carry an expr-position `(cons h t)` in the first match arm's body, with hand-declared `cons ∈ calls` asserted against **both** extractors; the pattern-position `((cons h t) …)` arm remains, so the probe now distinguishes the two positions in one source. Item 2's **Why** and Risks bullet 2 updated: the probe is now named as what pins the rule. Verified: `_expr` (grammar.js:138-152) has no cons production, only `cons_pattern` (:243). |
| N1 | [non-blocking, scope] Item 3's source-collection citation `:82-92` is short: the collection ends at closure_audit.py:94 (`sources.append`); `run_query(sources)` sits at :95. | **accept** | All three citations updated to `:82-94`: Context (input scope), Item 2 test 2 (independent reconstruction), Item 3 (factor scope). Item 3 now states `collect_sources()` returns the list and the call-site replacement stays at the former `:95` call site. Verified: closure_audit.py:82-94 is the glob through `sources.append(p)`; `run_query(sources)` is line 95. |
| N2 | [non-blocking, scope] Item 4's gate is the full battery, green on `main` today, so "Fails now if any prior item broke a package-level invariant" describes a gate that cannot be red before the work exists. | **accept** | Item 4's **Gate** reworded: explicitly not a red-now gate; described as the post-merge regression sweep that passes only if Items 1-3 introduce no regression outside the two files they edit. Battery command unchanged. |

## Notes for the orchestrator

- The remaining non-blocking findings in both reviews (scope 1, 3-9; architect 4-9)
  were dispositioned before reconciliation and required no plan text beyond what
  the five rows above produce; none altered the item ordering. PLAN.md v2 keeps
  the same 4-item structure in the same order.
- The acceptance criterion (command + the 107/107 / verbatim-baseline claims) and
  the exact-equivalence contract (orchestrator decision 1) are unchanged.
- Citation audit: every `path:line` the five dispositions turn on was opened and
  matched this session (grammar.js:243, :261, :266, :269, :211, :218-219, :138-152;
  closure_audit.py:40-42, :82-95). No finding was built on a wrong citation.
- No source files were edited; the only writes were the two plan artifacts.
