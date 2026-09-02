# Reconciliation — Phase 2 plan

Inputs: `PLAN.md` (v1) + `REVIEW-spec.md` (15 findings, 0 blockers) + `REVIEW-backend.md`
(7 findings, 0 blockers). 22 findings in, 22 rows out.

Result: `PLAN.md` rewritten as v2 — one coherent plan, no errata markers.

## Spec-conformance findings

| # | Finding | Disposition | Where / reason |
|---|---|---|---|
| S1 | `DefunNode` omits type-vars (§4.2, rule 10) | accept | v2 item 3: `type-vars (List String)` on `DefunNode`, with rule-10 rationale. |
| S2 | `SchemaNode` omits type-vars and schema-level `:json-case` (§:269, :296, rule 13) | accept | v2 item 3: `type-vars (List String)` and `json-case (Option String)` (`None` = `kebab` default). |
| S3 | `EnumNode` omits type-vars (§:385) | accept | v2 item 3: `type-vars (List String)` on `EnumNode`. |
| S4 | No exported-ness on `DefunNode`; rule 8 `:doc` conditionality unenforceable | accept | v2 item 3: `is-exported (Bool)`, resolved by item 4 against the module `:export`; `:doc` mandatory-iff-exported stated. |
| S5 | `!` could be inferred from the body instead of read from the source token (rule 12) | accept | v2 item 3: `!` read verbatim from the source token between `defun` and the optional `{<type-vars>}`, never inferred. |
| S6 | Params / enum-case fields must come from `[ ... ]` vector forms (§:317-322, :385) | accept | v2 item 3: `params` is `(List Param)` from the vector form; `EnumCase.fields` same; mis-reading `( ... )` named as a mis-implementation. |
| S7 | Plan's mapping omits `match`/`mt` (`tools/transcoder.py:15-25` has it) | accept | v2 item 4: `match`/`mt` joins the head-normalisation mapping used for both dispatch and embedded SExpr heads, so bodies round-trip without a typed `match` node. Citation verified this session (`transcoder.py:16`). |
| S8 | Round-trip proves rendering, not dialect discrimination; transcoder-built twin is self-referential | accept | v2 item 5: per-form head-equality assertions across all ten mapped heads, plus one hand-written Ultra-Nano fixture alongside the `to_ultra_nano` twin. |
| S9 | `:doc`→`:d` collapse must be slot-routing, not keyword syntax (`:ident` lexical rule) | accept | v2 item 4: option keywords are named slots routed within their owning form; a stray `:d` is ordinary data. |
| S10 | "Typed AST" vs "unclassified forms stay SExpr" needs the scope stated | accept | v2 item 3 "Typed-AST scope" paragraph: typed = the four §4 heads only; deliberate split; item 4 must not widen the fallback. |
| S11 | Item 1's "one `Bool`" framing contradicts its own String example | accept | v2 item 1: driver returns one typed value, test asserts the hand-written expected value (e.g. `"LPAREN"`). |
| S12 | Plan silent on `grammar/corpus/semantic` regression (§:761-769) | accept | v2 item 4: reader retains SExpr so rule-level rejection survives; checker gate added to item 4's gate. |
| S13 | Projection name unpinned (`nano`/`ultra-nano`/`compact` drift) | accept | v2: **Ultra-Nano** used consistently; naming note under the baseline. |
| S14 | `ModuleNode.imports` / `defs` shapes unspelled (§:205 example) | accept | v2 item 3: `imports (List (Pair String String))` (path, alias), `defs (List TopForm)`. |
| S15 | Rule 13 / `:json-case` (duplicate of S2) | accept | Same fix as S2; single row since the finding is explicitly a duplicate. |

## Backend-feasibility findings

| # | Finding | Disposition | Where / reason |
|---|---|---|---|
| B1 | Verified-builtin table: every entry present with its lowering | accept (verification) | No plan change needed; recorded as re-confirmed in v2's table preamble. |
| B2 | `str_slice` is half-open, end-exclusive (`backend/runtime.py:196-200`) | accept | Verified this session (verbatim read matches); recorded in v2 item 2 and the risk resolved. |
| B3 | Harness must keep `roots=[<src dir>, <driver dir>]` — cross-imports need both dirs | accept | v2 item 1: explicit in the harness docstring with the reason (`Transpiler.link` collisions / cross-imports), so a later implementer cannot trim it silently. |
| B4 | Enum tag-compare `match` must execute at item 1, before item 4's first match test | accept | v2 item 1: driver must contain at least one `(match <enum-value> ((<case>) ...))`; defenum/defschema lowering confirmations folded into item 3/v2 risk notes. |
| B5 | Name a concrete input-length bound in item 2 (reviewer suggested e.g. 4 KiB) | accept-modified | v2 item 2 pins **≤ 2 KiB** per orchestrator reconciliation guidance (tighter than the reviewer's example); deeper input = accumulator rewrite, flagged as scope expansion. |
| B6 | `grammar/corpus/modules/core/strings.agentscript` exists | accept (verification) | v2 risk section updated from "not verified" to confirmed. |
| B7 | Two line citations wrong: `to_python.py:413-416` → `:345-352`; `check_corpus.py:57-76` → `:50-60` | accept | Both re-verified this session before folding; v2 cites `:345-352` for field access and `:50-60` is dropped in favour of symbol-name citation for the harness (checked: the cited ranges now point at the claimed code). |

## Notes folded (non-blocking review notes, not numbered findings)

- Driver must not be named `main` (`Transpiler.host_entry` / `runpy` semantics) — folded into
  v2 item 1.

## Verification performed by the reconciler

- `backend/to_python.py:345-352` = `field_access` lowering (old `:413-416` shows `def pattern`).
- `backend/runtime.py:196-200` = `str_slice`, half-open end-exclusive, returns Option.
- `backend/check_corpus.py:50-60` = `execute()` (runpy + runtime copy, as the plan describes).
- `tools/transcoder.py:15-25` includes `match → mt`.
- `AGENT_SPEC_CORE.md:317` `defun [!] [{<type-vars>}] ...` with vector params; `:269` defschema
  with type-vars; `:385` defenum with type-vars; `:199-207` module `:export`/`:import` example.
- `packages/asl-parser/src/` contains only `lexer.asl`, `reader.asl` (item 3/4 premises hold).

## Disposition count

- 22 findings in / 22 rows out.
- 21 accept, 1 accept-modified (B5), 0 reject.
- 0 blockers raised by either review; nothing flagged for orchestrator escalation.
