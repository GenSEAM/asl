# Review — Phase 2 plan: spec-conformance lens

Lens: does the typed-AST contract and its gates faithfully mirror the normative spec
(`AGENT_SPEC_CORE.md`, `.plans/PHASES.md`)?

Verdict: **approve-with-amendments**

Plan is sound on the high shape (four typed nodes, dual-projection, execution-graded gates),
and the phase goal in `.plans/PHASES.md:7` is a tight verbatim match for what the plan builds.
Findings are concentrated in two places: (a) field-shape omissions for `DefunNode` and
`SchemaNode`, and (b) the round-trip acceptance criterion. None of them are phase-goal
defects; they are correctable by tightening the contract before implementation.

## Findings

1. **`DefunNode` field shape is under-specified vs §4.2.** PLAN.md:item 3 lists `(name, !,
   params, return type, :doc, body)`. The normative BNF at `AGENT_SPEC_CORE.md:317` is
   `(defun [!] [{<type-vars>}] <ident> [<params>] -> <Type> [:doc <string>] <body-expr>+)`.
   The plan omits **type-vars** as a node field. `AGENT_SPEC_CORE.md:333-339` makes type
   parameters a routine case (`swap` example with `{A B}`). Without a `(List String)` of
   bound type variables on `DefunNode`, a checker downstream cannot satisfy rule 10
   (every type variable used is bound in `{ }`) without re-parsing — and the phase goal
   says "typed AST", not "partially typed AST". The omission is non-blocking only because
   item 4 will normalise to verbose first; still, the contract should say
   `type-vars (List String)` explicitly so a conformant implementer cannot drop it.

2. **`SchemaNode` field shape omits type-vars and `:json-case`.** PLAN.md:item 3 names
   `(name, fields incl. :default/:json options)`. `AGENT_SPEC_CORE.md:269` is
   `(defschema [{<type-vars>}] <TypeName> <field>+)`, and `AGENT_SPEC_CORE.md:296`
   specifies `:json-case` on the schema (`kebab`/`camel`/`snake`/`pascal`, default `kebab`)
   in addition to per-field `:json`. The plan names only `name` and `fields` plus options
   "incl. `:default`/`:json`" — both the schema-level `:json-case` and the type-vars binder
   are silently dropped. Same impact as finding 1: a conformant checker (rule 10) and a
   conformant JSON serializer (future) need both. The fix is to add `type-vars (List String)`
   and `json-case (Option String)` (or a default-tagged enum) to the `SchemaNode`
   contract.

3. **`EnumNode` field shape omits type-vars; the plan's own text is the source.** PLAN.md:item 3
   says `(name, cases)`. `AGENT_SPEC_CORE.md:385` is
   `(defenum [{<type-vars>}] <TypeName> <case>+)`, with the same parametric shape §4.1 has.
   The `Tree` example at `AGENT_SPEC_CORE.md:403-406` makes recursive container types
   depend on it, and rule 10 applies here too. Add `type-vars (List String)` to `EnumNode`.

4. **`:doc` is mandatory on every exported `defun`, not "optional".** PLAN.md:item 3 lists
   `:doc` as a field without conditionality, but `AGENT_SPEC_CORE.md:325-326` makes `:doc`
   **mandatory for every exported function and optional otherwise**; rule 8
   (`AGENT_SPEC_CORE.md:727-728`) repeats it as a conformance requirement. The plan's
   contract does not encode "exported-ness" on `DefunNode` at all — `name`, `!`, `params`,
   `return`, `:doc`, `body`, plus the missing `type-vars` — so there is no field on which
   to hang rule 8's conditionality. The cleanest encoding is an `is-exported (Bool)` field
   (resolved at module-scope by item 4 against the module's `:export` vector); without it,
   a checker cannot answer rule 8 without a second pass over the surrounding module.

5. **`!` is the effect marker; grammar says it sits between `defun` and the optional
   `{<type-vars>}`, not before params.** PLAN.md:item 3 records `!` as a `Bool` field on
   `DefunNode`. `AGENT_SPEC_CORE.md:317` says `(defun [!] [{<type-vars>}] ...)` — the `!`
   is present-when-marked, not a separate `Bool` you may stamp on the body. Encoding as
   `Bool` is fine for a typed AST, but the plan does not specify that the value is taken
   from the source-position token, which means a conformant-but-wrong implementation
   could store `true` because the function performs an effectful call (rule 12,
   `AGENT_SPEC_CORE.md:732`). The text should say: "`!` is read off the source token and
   stored verbatim; the AST does not infer it." Otherwise rule 12 ("every effectful form
   sits inside a `defun` or `fn` marked `!`") is unenforceable from the AST alone.

6. **Param vector vs param list — only the vector surface is normative.** PLAN.md:item 3
   says "params" without quoting the spec. `AGENT_SPEC_CORE.md:317-322` says the parameter
   list is a **vector**, and `AGENT_SPEC_CORE.md:339-340` makes this part of the
   standardisation that resolved v0's C4 inconsistency. The plan should specify that
   `DefunNode.params` is a `(List Param)` where `Param` came out of a `[ ... ]` form — a
   reader that treats it as a `( ... )` list has mis-implemented the form, and the
   gate ("defun arity") is silent about how the distinction is enforced. Same for
   `EnumCase.fields` (`AGENT_SPEC_CORE.md:385` shows `[(width Float64) (height Float64)]`).

7. **The dual-projection token mapping in the plan vs `tools/transcoder.py:15-25`.** The
   plan's mapping at PLAN.md:item 4 lists
   `defun/df, defschema/dfs, defenum/dfe, :field/:f, :case/:c, :doc/:d, :export/:x,
   :import/:i, :as/:a`. `tools/transcoder.py:15-25` matches those **plus**
   `match → mt`. The plan omits `match/mt`. This is fine for top-form dispatch (the
   plan's reader recognises only `module/defschema/defenum/defun` as heads), but item 5's
   `render-node` round-trip will accept a `(match ...)` form as a generic SExpr-in-body
   (per finding 10 below) and silently fail to normalise it. Either item 4 adds `match`
   to the dispatch and item 5 handles it in `render-node`, or the plan documents that
   `match` projection round-trips only inside a `defun` body and is not canonicalised at
   the top form.

8. **Round-trip acceptance criterion is necessary but not sufficient.** PLAN.md:item 5's
   test (`parse(nano)` and `parse(verbose)` rendering to one canonical verbose string)
   proves **rendering** equivalence. It does not prove the parser **distinguishes** the
   two dialects — the same renderer fed two parsers would pass. The normative claim the
   phase is making is "the reader accepts both dialects and produces the same AST";
   that requires additionally asserting that `parse(nano).head == parse(verbose).head`
   for **each** node field whose source surface varies (the eight keywords in finding 7
   plus `defun`/`df`, `defschema`/`dfs`, `defenum`/`dfe`). The plan should add a per-form
   head-equality assertion, or the round-trip becomes a vacuous pass when both sides are
   buggy in the same way. Also: the test uses `tools/transcoder.py:to_ultra_nano` to
   build the nano twin; that means the test is checking the parser against the
   transcoder, not against hand-written nano. A conformant-but-wrong parser that calls
   `to_ultra_nano` internally and matches its own output would pass. The test should
   include at least one hand-written nano fixture, and the "values written by hand from
   spec" line (PLAN.md:item 2) should apply to the round-trip too.

9. **Nano dialect's head forms include `dfs`/`dfe`/`df` but the spec says "bare forms are
   not part of the surface"; the `:doc` collapse `:d` collides with identifier syntax.**
   Less of a conformance issue, more of a fuzz surface: `:doc` → `:d` (`tools/transcoder.py:18`)
   means any user identifier spelled `:d` (the spec's lexical rule at
   `AGENT_SPEC_CORE.md:73` allows `:ident`, with `ident` matching `[a-z][a-z0-9-]*`), the
   round-trip would map it to `:doc` and back to `:d` — fine — but if the reader's
   dispatch table sees `:d` and routes to "documentation option" rather than "the symbol
   `:d`", a non-doc use becomes a parse error. The plan's reader must treat
   documentation as a **named-slot** in `defun`/`defschema`/`defenum`, not as a syntactic
   keyword. Plan does not say so explicitly; recommend stating it.

10. **"Unclassified forms stay as generic SExpr in the body" vs phase goal.** The phase
    goal at `.plans/PHASES.md:7` says "typed AST nodes (`ModuleNode`, `SchemaNode`,
    `EnumNode`, `DefunNode`)". PLAN.md:item 4 says unclassified top-forms (e.g. `match`
    without a typed head) survive as `SExpr` inside the node body. This is **not** a
    conflict — the four named forms become typed, everything else stays untyped at parse
    time. The plan should state this is a deliberate split (parser = typed for the four
    forms; semantic rules live in the checker per `AGENT_SPEC_CORE.md:744-747`), so the
    reviewer of the plan is not surprised that "the parser produces a typed AST" and
    "unclassified forms stay as SExpr" are both true: the typed-AST claim is scoped to
    the four heads in `§4.0–§4.4`. Worth filing non-blocking so the implementer does not
    later widen the "unclassified" escape hatch to swallow classified forms.

11. **Item-1 smoke driver asserts a value computed from builtins, but the example is a
    `match` on `token-kind`.** PLAN.md:item 1 says the driver "returns one `Bool`
    computed from their values" and the example is
    `(token-type-name (token-kind "(")) → "LPAREN"`. The example returns a `String`,
    not a `Bool`. Either the spec is "the driver must return a value derivable from the
    builtin surface" (drop the `Bool` claim) or the example is wrong. Reading the
    surrounding text, the driver is meant to evaluate **every builtin in the table**,
    fold their results into one expression, and assert its value. The string
    `"LPAREN"` is fine as that returned value (and the test asserts the string, not a
    bool), so the right fix is to drop the "one `Bool`" framing and say "one
    typed value, hand-written".

12. **Phase-2 grammar gating is not part of the plan; PHASES.md scope is silent on it.**
    `.plans/PHASES.md:22-26` says no grammar changes. The plan's dual-projection reader
    is fed by `tokenize`, which is fed by the **source text** — there is no grammar
    involved in the new path. But `AGENT_SPEC_CORE.md:761-769` says the conformance
    gate "deliberately keeps such fixtures in `grammar/corpus/semantic/`" — i.e. the
    spec's conformance checklist includes rules no grammar can enforce, and the corpus
    surface is the safety net. The phase plan does not assert that the new reader's
    output preserves enough information for the existing semantic fixtures to still
    fail for the right reason. Worth a one-line note that **item 4 retains unclassified
    forms as SExpr specifically so the checker can keep doing rule-level rejection**;
    this is the same finding as 10, but from the corpus side.

13. **Phase goal mentions Ultra-Nano, but the phase plan doesn't pin the projection
    name.** `.plans/PHASES.md:7` says "supporting both Ultra-Nano and Verbose forms
    natively". PLAN.md uses "nano" and "verbose" interchangeably. `tools/transcoder.py:7`
    names the format `to_ultra_nano`. Pick one and use it consistently — the
    `nano`/`ultra-nano`/`compact` tuple at `tools/transcoder.py:54` already shows the
    naming is drifting.

14. **`ModuleNode` field shape is present but the items list is silent.** PLAN.md:item 3
    says "`ModuleNode` schema (`:doc`, exported names as `List String`, imports, defs)".
    `AGENT_SPEC_CORE.md:205` (the example) shows `:export [shout initials]` (a vector)
    and `:import [(core/strings :as s) (core/lists :as l)]` (a list of pairs). The plan
    calls the export vector a "List String" — fine — but imports as "imports" with no
    shape, and `defs` with no shape. The latter is where the typed AST lives: `defs`
    must be a `(List TopForm)` where `TopForm` is the four-node enum named in the plan.
    The plan says "plus `AstField`/`AstCase` helper schemas and a `TopForm` enum
    wrapping the four nodes" — that handles `defs`. Imports should be
    `(List (Pair String ModulePath))` or similar; spell it out.

15. **The plan does not address `:json-case` on a schema, but a `SchemaNode` field for
    that case is the only way rule 13 of the conformance checklist can be checked
    without re-reading the source.** Already covered in finding 2; calling it out
    separately because rule 13 (`AGENT_SPEC_CORE.md:735-740`) is the rule the typed AST
    is most likely to leak information under — a parser that drops `:json-case`
    cannot later rebuild the wire format deterministically.

## Constitution check

`.pcp/CONSTITUTION.md` exists and is essentially empty (one-sentence header); no
architectural decisions or caveats to violate. No `.factory/CONSTITUTION.md`,
`CONSTITUTION.md`, or `ai-docs/constitution.yaml` at the repo root. Fall back to
basic engineering audit. No violations of the engineering audit under the spec-conformance
lens.

## Blockers

None.

## Non-blocking (filed for the implementer)

- F1: spell `DefunNode` type-vars field
- F2: add `SchemaNode.type-vars` and `SchemaNode.json-case`
- F3: add `EnumNode.type-vars`
- F4: encode exported-ness on `DefunNode` (rule 8)
- F5: clarify `!` is a source token, not inferred
- F6: param vector surface — explicitly store vector-bracketed form
- F7: add `match/mt` to dispatch + `render-node` (or scope out top-form `match`)
- F8: per-form head-equality assertions in round-trip; one hand-written nano fixture
- F9: state that option keywords are slots, not syntax
- F10: document the typed-AST scope (four heads) and the SExpr-fallback scope
- F11: drop the "one Bool" framing in item 1; assert a typed value
- F12: name the corpus/semantic regression responsibility on item 4
- F13: pick "Ultra-Nano" or "nano" and use it consistently
- F14: spell out `ModuleNode.imports` and `ModuleNode.defs` types
- F15: covered by F2

## Unverified

- The `Token` schema's field order vs `lexer.asl:16-22` was not cross-checked against a
  spec requirement — spec does not specify token-record shape, so this is implementation
  detail; fine.
- `tools/transcoder.py` claim that both grammars already accept both dialects — not
  verified this session; PHASES.md takes this as given.
