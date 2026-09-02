# Phase 1 plan review — design and spec lens

## Verdict

**approve-with-amendments.** The core decisions — one export list with case deciding kind,
`alias/TypeName` reusing the qualified shape, nominal identity by defining module — are right and
survive the checks below; but the plan closes the *grammatical* half of `r-ea8c` while leaving its
*semantic* half (a private type escaping through an exported signature) unenforced, and would mark
`r-ea8c` resolved on that basis.

Answers to the six lens questions, with evidence, are folded into the findings: Q1 **sound**
(F6), Q2 **sound — measured, and the plan's own risk 2 is overstated** (F5), Q3 **concern** (F4),
Q4 **sound with one carry-over** (F7), Q5 **defect of omission** (F3), Q6 **minor drift only**
(F6, F9).

---

## Findings

### 1. `blocker` — Nothing requires a type in an exported signature to be exported

**Claim under review:** §2.1 and the phase header — "the module header *is* the Wasm interface
contract" and this phase makes the types in exported signatures expressible. W16.7 marks
`r-ea8c` **Resolved**.

**Evidence.** `grammar/corpus/valid/06-module.agents:5` exports `[shout area tally]`;
`:11` declares `(defenum Shape …)`, which is *not* exported; `:24` declares
`(defun area [(sh Shape)] -> Float64 …)`, which *is*. That fixture checks clean today
(`checker/gate.py:35-40` runs every `corpus/valid` file and it passes) and the plan keeps it clean
— §4's matrix row 7 says "unchanged source; removed from both skip lists", and W10 promotes it to a
fully gated backend fixture. So after Phase 1 the corpus's flagship module fixture still exports a
function whose parameter type no importer can write.

That is verbatim `r-ea8c`'s own scenario (`.pcp/lang/modules.md:47-50`): *"a module declares a
domain union and a function returning it, exports the function, and no other module can write the
type of what it receives"*. The plan removes the *lexical* obstacle to writing `s/Shape` but adds
no rule that forces the author to make `Shape` writable. `ROADMAP.md:78` states the property this
is all for — the header is "readable without the body" — and an exported signature naming a
private type is a contract that cannot be honoured by any consumer.

**Why blocker rather than "would have done differently":** adding the rule later is a *new
rejection* of programs already accepted, including a corpus fixture and the `prelude/HANDBOOK.md`
shape block; and W16.7 would record `r-ea8c` closed when the requirement it states
(`.pcp/lang/modules.md:45-46`, "Types are exportable and referenceable across a module boundary")
is only half met. A false PCP resolution is the unrecoverable part.

**Amendment.**
* Add a conformance rule (new **rule 13**, or an explicit extension of rule 2) to
  `AGENT_SPEC_CORE.md` §9: *every type named in the signature of an exported `defun`, and in any
  field or case-parameter type of an exported `defschema`/`defenum`, must be a §3 built-in, a type
  variable bound in that declaration's `{ }`, or a type exported by its defining module.*
* Enforce it in W5 (`checker/resolve.py`, alongside `module_rules`), and add
  `semantic/private-type-in-exported-signature.agents` to the W11 matrix.
* Either export `Shape`/`Tree`/`Box` from `grammar/corpus/valid/06-module.agents`, or accept that
  fixture as the first case the new rule rejects. Do not leave it as a clean `valid/` fixture.
* W16.7's `r-ea8c` update must name this rule as part of what closed it.

---

### 2. `major` — `:export [<case-name>]` is already legal, and the plan gives it two contradictory meanings

**Claim under review:** W4 — "`IDENT` into `mod.exports` (unchanged meaning)"; W5.3 — "a member is
exported if it is in `target.exports` **or** is a case of an exported enum"; §2.1 sub-decision 3
and the §2.3 table row *"`s/circle` where the owning enum is not exported → `rule-9`: a case is
public exactly when its type is."*

**Evidence.** `checker/resolve.py:120` — `elif name not in self.mod.case_owner:` — a bare enum
**case name** on the `:export` vector is accepted *today* and is not a `rule-2`. So `:export
[circle]`, with `Shape` absent, is currently a well-formed module that publishes a constructor for
a type nobody can name. Keeping IDENT export semantics "unchanged" therefore keeps a second,
independent route to exporting a case — one that directly contradicts "a case is public exactly
when its type is", and one that manufactures instances of Finding 1.

The plan never cites `:120`. Every other `checker/` citation in §1.3 is accurate, so this is an
omission in the analysis rather than a misreading.

**Amendment.** Decide it in §2, not in the implementation. Recommended: drop the `case_owner`
allowance at `checker/resolve.py:120` so a case name on the export list is a `rule-2` and cases
travel only with their type — this is the reading §2.1.3 and §2.3 already assume. Add
`semantic/export-bare-case.agents` (`rule-2`) to the W11 matrix, and state the removal in W1's §4.0
amendment so the spec and the checker agree.

---

### 3. `major` — Re-export and transitivity are not answered

**Claim under review:** nothing. The plan is silent; the lens question is Q5.

The situation: `core/shapes` exports `Shape`; `text/report` imports it and exports
`(defun describe [(sh s/Shape)] -> String …)`; a third module `C` imports `text/report` as `r`.

**What the answer must be, and why.**
* `C` may call `(r/describe v)` **without** importing `core/shapes`: rule 9
  (`AGENT_SPEC_CORE.md:654-655`) constrains *qualified names `C` writes*, and `C` writes none of
  `core/shapes`'s. Type identity is by defining module (§2.2), so the checker resolves the
  parameter type through the `Loader` regardless of `C`'s import list.
* `C` **must** import `core/shapes` the moment it needs to *name* the type — to declare a `let`
  binding's type, a helper's parameter, or a `match` over the value. That is the ordinary
  consequence of §2.1 sub-decision 4 (cases are reached qualified) and of aliases being
  module-local (`AGENT_SPEC_CORE.md:164`).
* There is **no re-export**: `text/report` listing `Shape` on its own `:export` would be a
  `rule-2` under W5.1, because `Shape` is not in *its* `schemas`/`enums`. State that explicitly —
  otherwise an author will try it and get a diagnostic that reads like a bug.

**Amendment.** Add these three sentences to W1's §4.0 amendment and to a `valid/` fixture
(`12-transitive-use.agents`: three modules, `C` calls through `B` without importing `A`, and a
second function in `C` that names `A/T` and does import it). Without the fixture, the first author
to hit it will be guessing.

---

### 4. `major` — Transparent export makes the contract un-readable from the header, and the plan does not say so

**Claim under review:** §2.1 sub-decision 1, "`d-f99b` makes the export list *the* contract,
singular and machine-readable"; §2.1.3, transparency is "forced by totality".

**The transparency argument is correct.** `AGENT_SPEC_CORE.md:649` requires exhaustive `match`, and
`:301-302` makes case names both constructors and patterns; an importer that cannot see every case
cannot write a total `match`, so an opaque union would be unusable rather than restricted.
Deferral is not merely safe, it is **forced**: the opaque form maps to an abstract handle whose
semantics depend on an ownership model that is explicitly unrecorded (`ROADMAP.md:214-215`, PCP
`l-880d`). Deciding opacity now would be deciding ownership by accident.

**The gap.** Once `:export [Shape]` also publishes `circle`, `rectangle`, `radius`, `width` and
`height`, the export vector is no longer the whole public surface — it is a *seed* for it, and the
rest is only recoverable by reading the declarations. That is a real narrowing of `d-f99b`
(`.pcp/lang/modules.md:29-31`, "being declarative it can be extracted mechanically") and of
`ROADMAP.md:78` ("readable without the body"). The plan asserts one contract and then quietly makes
it two-layered.

**Which contract the product goal needs (Q3).** For `d-f484`'s stated role — "a typed glue layer
between ecosystems that meet as compiled modules … composed through declared interface contracts"
(`.pcp/lang/wasm.md:8-11`) — **transparent is the one to ship**. Data crossing a component boundary
must be described structurally for the host to marshal it; an abstract handle is a different
kind of contract that requires a host-side resource lifetime, which is exactly the unrecorded
ownership decision above. So: transparent now, opacity later as the *resource* case, not as a
general visibility knob.

**Amendment.**
* W1 §4.0: state that a module's interface contract is *the header together with the declarations
  of the types it exports*, and that expanding the second part is mechanical because those
  declarations are in the same file. One sentence; it keeps `d-f99b` honest.
* W16 entry 3: record the narrowing of `d-f99b` explicitly ("the export list names the surface; for
  a type, the declaration completes it"), rather than letting `d-f99b` read as unchanged.
* W16 entry 3 should also name `l-880d` as *why* opacity is deferred, not only exhaustiveness —
  that is the stronger and more durable reason.

---

### 5. `major` — W12 must be mechanical; the ambiguity it guards against is silently resolved today

**Claim under review:** §6.2 and W12 — "the `.2` priority at `:192` is load-bearing … a new
terminal overlapping `MOD_PATH` or the `OPERATOR` `/` can re-introduce a silent mis-parse"; the
mitigation is a **manual** one-off tree comparison.

**Measured, not argued.** I applied the plan's five W2 edits verbatim to a copy of
`grammar/agents.lark` (`QUALIFIED_TYPE.2: /[a-z][a-z0-9]*(-[a-z0-9]+)*\/[A-Z][A-Za-z0-9]*/` beside
`QUALIFIED` at `:192`) and parsed with both `ambiguity="resolve"` and `ambiguity="explicit"`:

| form | token for the qualified part | new ambiguity? |
|---|---|---|
| `:export [describe Shape]` | `IDENT describe`, `TYPE_NAME Shape` | no |
| `(x s/Shape)` in a param | **one** `QUALIFIED_TYPE 's/Shape'` | no |
| `-> (List s/Point)` | **one** `QUALIFIED_TYPE 's/Point'` | no |
| `(s/Point :x 1)` ctor | **one** `QUALIFIED_TYPE 's/Point'` | no |
| `(/ a b)` and `(/ a 2)` | `OPERATOR '/'` | no |
| `(module core/deep/mod …)` | `MOD_PATH` | no |

**The plan's risk 2 is overstated for this terminal.** The uppercase tail makes `QUALIFIED_TYPE`
lexically disjoint from `QUALIFIED`, `MOD_PATH` and `TYPE_NAME`; the only competing lexing,
`IDENT` `/` `TYPE_NAME`, cannot parse, because a bare `TYPE_NAME` is not an expression
(`grammar/agents.lark:114` requires parentheses for a ctor) and `OPERATOR` is not a type head.
Earley needs no lookahead pathology to separate them.

**What is actually exposed, and the plan does not say it.** `grammar/parse.py:32` constructs the
parser with `ambiguity="resolve"`. Under `ambiguity="explicit"` the **unmodified** grammar is
already ambiguous for `(s/concat (s/upper x) "!")` and for *every* `match` form — `(match v …)`
also parses as a call to `match`. The grammar is ambiguous by construction and correctness rests
entirely on `resolve` plus terminal priority. A manual, one-time eyeball is therefore the wrong
guard: it does not survive the next terminal, and `agents.lark` drives constrained decoding, so a
regression there corrupts the token mask rather than the parse.

**Amendment.** Replace W12's manual step with a ~15-line pytest case in `checker/t` (or
`grammar/`): parse each new fixture and assert `QUALIFIED_TYPE('s/Shape')` appears as a single
token in the Lark tree, and that the tree-sitter parse contains one `qualified_type` node covering
the same span. Cost is minutes — this review produced the Lark half in one command. Keep §6.2's
honest statement that a general tree-comparison gate is out of scope; a token-identity assertion is
not the same thing and is affordable now.

---

### 6. `minor` — Case-decides-kind is sound, but it is the one place spelling is load-bearing and the spec says the opposite elsewhere

**Q1 verdict: sound.** `TYPE_NAME` `/[A-Z][A-Za-z0-9]*/` and `IDENT`
`/[a-z][a-z0-9]*(-[a-z0-9]+)*[?!]?/` (`grammar/agents.lark:183-184`,
`grammar/tree-sitter-agents/grammar.js:233,237`) are disjoint in both grammars, and
`AGENT_SPEC_CORE.md:85,89` fixes both. `:export [describe Shape]` parses unambiguously (measured,
F5). The `agents-` reserved prefix (`AGENT_SPEC_CORE.md:104`) is lowercase-only and does not
interact. Nothing else in the language overloads case for *kind*: case already separates
identifiers from type names, and `type-var` vs `type-name` (`:88-89`) share a spelling and are
separated by *position*, not case.

**The drift.** `ROADMAP.md:79-80` states the project's stance: *"a name is a type variable because
it was declared one, never because of how it is spelled."* The export list is now the one place
where spelling decides a kind. That is a defensible exception — an explicit form such as
`(:type Shape)` exists in-idiom (`:import` and `:field` both use parenthesised keyword entries) but
costs tokens on the surface `d-133a` exists to keep small — and the same reasoning already carries
`AGENT_SPEC_CORE.md:101-102`'s division/qualification split.

**Amendment.** One sentence in W1's §4.0 amendment saying so explicitly, so the two statements do
not read as a contradiction to the next reader. Also amend `AGENT_SPEC_CORE.md:301-302` — "Case
names … are used as both constructors and patterns, **exactly like the built-in `ok`/`some`**" is
no longer true across a boundary, where they must be written `s/circle`. W1 does not list that
line.

---

### 7. `minor` — `Con` must keep `.name` unqualified; two call sites key on the bare string

**Claim under review:** W6.1 — "`Con` (`:53-57`) carries the defining module path alongside the
name". Verified: `checker/types_.py:53-56` stores a bare `name`, and `unify` at `:113-115` compares
`a.name != b.name`. Nothing in the current unifier can distinguish two modules' `Shape` — the
plan's diagnosis is exactly right, and `imported-type-mismatch` is the right fixture to pin it.

**The carry-over.** Two sites key on the *unqualified* string and must not see a qualified one:
* `checker/types_.py:115` — `numeric=a.name in NUMERIC and b.name in NUMERIC`, which selects the
  numeric-mixing diagnostic.
* `checker/types_.py:155` — `name = self.aliases.get(name, name)`, the prelude type-alias map
  (`vocab.type_aliases`, e.g. `Int` → `Int64`, `AGENT_SPEC_CORE.md:124`).

"Alongside the name" is the correct reading (a separate field, prelude types carrying a
prelude/None origin); the plan should say so in one clause so the implementation does not fold the
module path into `.name` and break both.

**Two modules defining the same type, both imported** (Q4): distinct `Con`s, distinct spellings
`s/Shape` and `t/Shape`, no ambiguity — the design answers this cleanly.

---

### 8. `minor` — W5.4 is a no-op and contradicts §2.1's own single-lexeme argument

**Claim under review:** W5.4 — "`check_type` (`:186-192`) … must skip type names that are the tail
of a `QUALIFIED_TYPE` token".

`checker/resolve.py:187` scans `t.type == "TYPE_NAME"`. If `QUALIFIED_TYPE` is a single terminal —
which §2.1 sub-decision 2 asserts and F5 measures — then `Shape` inside `s/Shape` is never a
`TYPE_NAME` token and `check_type` cannot see it. There is nothing to skip. Delete W5.4, or
replace it with what is actually needed: `check_type` must be *reached* for a `QUALIFIED_TYPE` node
by the new W5.2 pass, since `type_var_rules` (`:172-184`) is the only caller and would otherwise
skip qualified types silently.

---

### 9. `minor` — §8 must extend the mangling-collision rule to module paths

W1 adds a §8 row for qualified names, and §2.4 fixes `core/shapes` → `core_shapes` (Rust module) /
`core_shapes__area` (Python). `AGENT_SPEC_CORE.md:635-637` errors when "two distinct AgentS
identifiers mangle to the same target identifier" — it says nothing about module *paths*, and
`core/shapes` and a module named `core-shapes` collide under either scheme. One clause in W1's §8
amendment.

Also resolvable, and worth striking from §6.5: tree-sitter's `word: $ => $.ident`
(`grammar.js:22`) already coexists with the `qualified` regex token (`:236`), which has the same
shape as the proposed `qualified_type`; keyword extraction applies to anonymous string tokens, and
`:export`/`:import` do not match the `ident` pattern. No new interaction.

---

## Claims checked

| plan's claim | cited location | verified? | note |
|---|---|---|---|
| `:export` admits `IDENT` only | `grammar/agents.lark:26` | yes | exact |
| `TYPE_NAME` / `IDENT` regexes | `grammar/agents.lark:183-184` | yes | exact |
| `QUALIFIED.2` lowercase member; priority load-bearing | `grammar/agents.lark:192` | yes | comment at `:187-191` names the `(s/concat x)` incident |
| `type` has no qualified form | `grammar/agents.lark:58-59` | yes | exact |
| `ctor` head is `TYPE_NAME` | `grammar/agents.lark:114` | yes | exact |
| `enum_pattern` head is `IDENT` | `grammar/agents.lark:89` | yes | exact |
| tree-sitter export / `_type` / ctor / enum_pattern / qualified | `grammar.js:38,103-104,181,216-218,236` | yes | all exact; both grammars do agree |
| `qualified ::= ident "/" ident` | `AGENT_SPEC_CORE.md:86` | yes | exact |
| `:export` is "the public surface"; `alias/name` | `AGENT_SPEC_CORE.md:152-154` | yes | exact |
| rule 9 wording | `AGENT_SPEC_CORE.md:654-655` | yes | exact |
| rule 4 exhaustiveness | `AGENT_SPEC_CORE.md:649` | yes | exact |
| rule 8, `:doc` on exported `defun` only | `AGENT_SPEC_CORE.md:653` | yes | exact — the "no doc required on a type" matrix row is right |
| §8 table has no qualified row | `AGENT_SPEC_CORE.md:625-637` | yes | exact |
| `exports` is one flat token list | `checker/collect.py:113-114` | yes | exact |
| `known_types` is prelude + local | `checker/resolve.py:98` | yes | exact |
| `qualified_names` scans `QUALIFIED` only | `checker/resolve.py:157-168` | yes | exact |
| `rule-2` on exported-undefined | `checker/resolve.py:121` | yes | exact — **but `:120` also exempts case names; see F2** |
| `check_type` scans `TYPE_NAME` | `checker/resolve.py:186-192` | yes | exact — makes W5.4 a no-op (F8) |
| `Con` carries a bare string; `unify` compares names | `checker/types_.py:53-57`, `:113-115` | yes | exact |
| `qualified` resolves only `target.funs` | `checker/types_.py:186-191` | yes | exact |
| `lookup` reads local enums | `checker/types_.py:177-184` | partly | that range is the `case_owner` block; `lookup` begins at `:169`. Substance correct |
| `{ }` binder shadows a declared type | `checker/types_.py:157` | yes | exact; `if name in rigid:` — §6.4 is a real pre-existing hole |
| cycle detector keys on the declared module name | `checker/resolve.py:141-153` | yes | `stack.append(mod.name)` at `:140`; `mod.name` comes from the header (`collect.py:106`) |
| `06-module.agents` on both skip lists | `backend/check_corpus.py:22-23` | yes | exact, comment included |
| a user schema named `Box` is in the corpus | `06-module.agents:8` | yes | exact — the `::std::boxed::Box` qualification in W7 is justified |
| Rust `defenum` drops `{ }` binders, no indirection | `backend/to_rust.py:134-147` | yes | `:135` filters `type_params`, `:137` emits a bare `pub enum` — and `defschema` at `:124-132` has the same defect |
| gate discovery already handles `modules/` | `checker/gate.py:39`, `grammar/validate.py:73` | yes | `rglob` over `corpus/modules`, plus `corpus/valid` |
| closure audit defers qualified heads to the checker | `grammar/closure_audit.py:32-37,73-75` | yes | query buckets `qualified` separately |
| ROADMAP gap statement | `ROADMAP.md:208-211`, `:143-144` | yes | exact |
| **not claimed:** `parse.py` uses `ambiguity="resolve"` | `grammar/parse.py:32` | — | material to §6.2 (F5) |
| **not claimed:** a case name is a legal export today | `checker/resolve.py:120` | — | material to §2.1.3 (F2) |
| **not claimed:** `area` in `06-module.agents` exports a private type | `06-module.agents:5,11,24` | — | material to `r-ea8c` (F1) |

Citation accuracy is high — every `path:line` in §1 that I opened pointed at the construct claimed.
The plan's failures are omissions, not fabrications.

---

## Questions the plan does not answer

1. **Must a type in an exported signature itself be exported?** (F1.) The plan needs a normative
   answer before W5 is written; "no" makes the header a contract no consumer can honour.
2. **What does `:export [circle]` mean?** (F2.) Legal today; two conflicting readings after W5.3.
3. **Does a consumer of B need to import A?** (F3.) Answer proposed above; must reach §4.0 and a
   fixture.
4. **Can a module re-export an imported type?** Under W5.1 this is a `rule-2`. Say so, or authors
   will read the diagnostic as a bug.
5. **Is the exported-type set the contract, or a seed for it?** (F4.) Affects whether `d-f99b`'s
   "extracted mechanically" still holds, and what a Wasm interface extractor reads.
6. **What is the diagnostic when an importer constructs an imported `defschema` and omits a field
   without a `:default`?** §4.1's construction rules are enforced today for local schemas; the plan
   extends `_ctor` (W6.4) but names no code for the cross-module case in §2.3's table.
7. **Does an imported type participate in `=` / `Map` key equality across the boundary?** §2.4 keeps
   bare tuple tags in Python and namespaced variants in Rust; §6.3 covers `match` only, not
   structural comparison of two values from different modules that happen to share a tag shape.
8. **Is there a reserved namespace for compiler-generated type and module names?** `agents-`
   (`AGENT_SPEC_CORE.md:104`) is lowercase-only, so it reserves nothing in `TYPE_NAME` space, and
   §2.4 now generates target module names (`core_shapes`) from user paths.
