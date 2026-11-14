# Inference and the type lens

Status: design proposal with measurements and a working prototype, 2026-11-13. Nothing in the language changes with this document.
Ledger: `.asl/mem/audits/fable-20261113/inference.asn` (measurements, prior records, plan rows `INFER-01..09`). Prototype: `tools/typeLens/typeLens.asl`.

The idea (principal, 2026-11-13): what the toolchain can derive at build time is not written in the code, yet is one cheap question away whenever a model or a person reads or searches code, so nobody opens another file to learn a type.

This continues decisions already taken, it does not open a new line:

| Earlier record | What it decided | State today |
|---|---|---|
| D17 (2026-09-08) | nominal types, Hindley-Milner bidirectional inference, "without heavy annotation overhead on AI agents" | inference runs inside function bodies; top-level parameters stay mandatory (`ERR_UNTYPED_PARAM`, row UNTYPEDPARAM 2026-10-03) |
| principle InferWhatCanBeInferred (2026-10-16) | an annotation the author writes is honoured, one left out is inferred or inserted by the fixer | applied to effects only |
| EFFECT-INFER-20261016, EFFINFER-LEFT-20261016 | effects inferred by a call-graph fixpoint; `!` optional; "inferred effect shown by tools (effect-boundary lens, know cards, receipts)" | inference landed in `resolve.asl`; the showing half did not: no op prints an inferred effect, the cards print the declared mark |
| LAMBDAINFER-RESYNC (2026-10-09) | lint and codemod dropping inferable lambda annotations | `needsPrincipal`, never run; the corpus still carries them (1.2 to 1.3 percent of tokens, below) |
| LLM-AUTHORS-20261016 | every rule is judged by what it costs the model that writes the code | the measure this document uses |
| asl-know cards (KNOW, 2026-10-16) | per-package card with declared signatures, tiered L0/L1/L2 | generated, 82 cards; `(:know :q)` answers ERR_UNIMPLEMENTED (visualization audit VZ-I-16); declared facts only |
| HL-MM4-BORROW | borrow inference for parameters | open; the same class of fact (inferred, never written, must be visible) and the lens is where it would show |

What is new here: the measurement of how much inference can save, the line where signatures stay, and the read side (the lens), which the earlier rows named and nobody built.

## 1. What the annotations cost

Method: tiktoken 0.12.0 `o200k_base`, `encode_ordinary`; each construct is deleted from the text by a reader-aware scratch script and the file re-counted, so the figure is the real token delta, not a character share. The script is a measuring instrument and is not in the tree (rule D157). Three samples, all read at main on 2026-11-13:

- **sample7**: 7 modules of 7 packages (asl-json json, asl-csv csv, asl-text escape, asl-stats describe, asl-utils timeout, asl-sched cron, asl-cas cas), 160 functions, 22 633 tokens.
- **langeff9**: the 9 modules of the 2026-10-09 ASL/Python study, 123 functions, 12 488 tokens today (12 037 then). Their Python sides were scratch files and were never committed, so only the recorded total (6 547) is available; breaker and math each exist in two packages and the study does not say which, asl-engine and asl-mem were taken.
- **ref30**: the 30 reference solutions of `asl/bench/gen/ref`, each in ASL, typed Python and TypeScript, 40 ASL functions, 2 831 tokens. This is the only set where all three languages are in the tree, so the cross-language ratios come from it.

| Construct | sample7 | langeff9 | ref30 | Who can infer it |
|---|---|---|---|---|
| parameter types of `fn` | 4.78 % | 7.94 % | 7.88 % | private functions: whole module (call sites and body). Exported: not without reading every importer |
| return type of `fn` | 3.35 % | 3.69 % | 6.15 % | local (the body), except a recursive group, which needs one annotation |
| lambda parameter and return types | 1.22 % | 1.32 % | 0 | local, already optional; the corpus just still writes them |
| let-binding types | 0 | 0.20 % | 0 | local, already inferred |
| effect mark `fn !` | 0.20 % | 0 | 0 | whole program, already inferred (EFFECT-INFER) |
| `!` name suffix | 0.52 % | 0.06 % | 0 | a naming convention, not an annotation; stays |
| export list `:x [...]` | 0.95 % | 2.65 % | n/a | not inferable: it states intent. Derivable only as "everything some other module uses", which makes an API an accident |
| import list `:i [...]` | 0.16 % | 0.38 % | n/a | not inferable while aliases exist; negligible |
| field types in `schema` and `enum` declarations | 0.30 % | 0.62 % | 3.39 % | not inferable: they are the anchors everything else is inferred from |
| record field types at construction | 0 | 0 | 0 | already absent: `(Account :balance 1)` carries names only |
| explicit `(some x)` and `(ok x)` wrapping | 0.92 % | 0.15 % | 1.20 % | not inference but implicit coercion; it would hide where a failure enters. Stays |
| **all function, lambda and let types plus the mark** | **9.42 %** | **12.85 %** | **13.67 %** | upper bound of this whole programme |
| of which locally inferable (return, lambda, let, mark) | 4.77 % | 5.18 % | 6.15 % | |
| of which private-function signatures | 5.41 % | 5.75 % | n/a | |
| of which exported-function signatures | 2.59 % | 5.61 % | n/a | proposed to stay |

A function header line is 12.7 % (sample7) and 18.6 % (langeff9) of all tokens; 100 of 160 and 45 of 123 functions are private.

### Against Python and TypeScript (ref30)

| Variant of the ASL side | ASL tokens | vs typed Python (2 396) | vs TypeScript (2 624) | vs untyped Python (about 2 157) |
|---|---|---|---|---|
| today | 2 831 | 1.18 | 1.08 | 1.31 |
| return types dropped | 2 657 | 1.11 | 1.01 | 1.23 |
| all function types dropped | 2 444 | 1.02 | 0.93 | 1.13 |

Untyped Python is the typed file with annotations stripped through `ast`, scaled by the unparse ratio (2 389 to 2 151).

On langeff9 the same removal moves the recorded ratio from 1.91 to 1.66 (all function types) or 1.81 (local only). So:

- Inference is worth **5 to 14 percent of source tokens**, depending on how far it goes. The proposed line (section 2) takes 6.8 % on sample7 and 7.3 % on langeff9.
- On idiomatic code (ref30) that is the whole distance to typed Python. On the older modules it is not: their 1.9x is idiom and stdlib surface (audit finding L-04, plan row FABLE-LANG-06), and inference removes about a quarter of the excess.
- Source size is the small term. The language audit (L-16) puts 96.6 % of receipt tokens in payload strings, and an agent pays for what it reads far more often than for what it writes. The larger saving is on the read side: section 3 and the measured lens output in section 5.

## 2. Which annotations become optional

The rule is one sentence: **a type is written where it is a promise to someone else, and inferred everywhere else.** A promise is an exported function, a schema or enum declaration, and a foreign binding.

| Construct | Proposal | Inference | Why |
|---|---|---|---|
| let binding | optional (already) | local, bidirectional | no change |
| lambda parameters and return | optional (already); codemod removes the written ones (9 813 typed against 2 332 untyped lambdas in asl/packages, git grep 2026-11-13) | local, from the expected function type of the call | executes LAMBDAINFER-RESYNC; 1.2 to 1.3 % |
| effect | optional (already) | whole-program fixpoint | no change in the language; the lens finally shows it |
| return type of a private function | optional | local: the type of the body's tail expression; a recursive group must annotate one member, and the diagnostic names which | cheap, single pass, no cross-module work |
| parameter types of a private function | optional, **only after the experiment arm says so** | per module: parameters start as type variables, constrained by the body and by every call site in the same module, then generalised once per binding group | the largest single item and the riskiest one for error locality |
| exported function | parameter and return types stay mandatory | checked, never inferred | below |
| schema and enum fields | mandatory | none | anchors |
| `(some x)`, `(ok x)`, export list | unchanged | none | not inference |

### Why exported signatures stay in the source

Recording inferred signatures in a generated interface file was the alternative. It is rejected for exports and adopted for everything else (as the card, section 3), for five reasons:

1. **Stability.** An inferred export changes type when a body changes. With a written signature the body is checked against the promise and the error lands in the module that broke it, not in forty importers.
2. **Error locality.** With a signature at each boundary, an inference failure is confined to one module and the diagnostic can name expected and actual at the line that disagrees. Whole-program inference reports the place where two constraints finally met, which is often neither of the two wrong places.
3. **Compile speed and cache keys.** A module can be checked against its dependencies' interfaces alone. The interface digest (exported signatures, exported types, inferred effects) becomes the cache key: a body edit that leaves the interface untouched invalidates nothing downstream. Today `checkCached.asl` stamps a closure by its dependencies' source digests, so any byte in any dependency re-checks every importer. With inferred exports the key would depend on bodies again.
4. **The author is a model.** A model that writes the header first has written down its plan for the body; the header is the cheapest form of that plan. Typed TypeScript and typed Python are both strong priors, and exported functions are where a model calling the function needs the type to be findable by search.
5. **Generics.** `fn safeTail l: (List T) -> (List T)` states polymorphism in the open. Inferring it for exports means let-generalisation across modules, which no mainstream language does.

Private functions carry none of these arguments: nobody outside the file can depend on them, and the lens (section 3) shows their inferred signature in the same answer as their text.

### How errors stay precise

- Every diagnostic that involves an inferred type keeps the form the checker already has, `expected T, found U`, and adds the origin of each side when it was inferred: `expected Int64 (from the call at line 14), found String (parameter n is used with stringLength at line 9)`.
- A private function whose parameter cannot be resolved to one type is not reported as a puzzle. Under InferWhatCanBeInferred the fixer writes the most constrained signature it found into the header and the checker reports the remaining disagreement against that written line.
- An unresolved variable never becomes `Any` silently. Today an untyped top-level parameter is an error; the replacement is `ERR_AMBIGUOUS_TYPE name: annotate, candidates (List Int64) | (List String)`.
- `asl fix --annotate FILE` writes every inferred signature back into the source. Inference is then a display and typing convenience, never a one-way door: a file can always be turned into its fully annotated form and back.

### The fn-header problem (audit L-08)

The bare `fn name a: T -> R` line is the dominant failure class, and it is the same line that carries 13 to 19 % of the tokens. The two questions interact:

- A header with no types, `fn name a b`, is shorter but is still the non-form line that models get wrong. Inference does not fix L-08, and L-08 must not wait for it.
- If the wrapped form `(fn name [a b] body)` wins its arm (FABLE-LANG-02), untyped parameters make it identical to the lambda and to Clojure's `defn` vector, the strongest S-expression prior there is. So the header arm and the inference arm should be run as a 2 by 2, not one after the other.
- A direct observation from this unit: the prototype's first write (45 functions, written by the model that wrote this document) put a stray `)` at the end of all 45 function bodies, the exact vestigial-closer class of L-08; `asl check` located all of them.

### The experiment (asl/EXPERIMENT.md)

Proposed additional arm, same tasks, models, repetitions and scoring as `asl`:

| Arm | Language shown to the model | Checked by |
|---|---|---|
| `aslInferred` | the `asl` card with one sentence changed: "parameter and return types of a function may be omitted; the checker infers them" and the card's examples written without types except on the task's entry function | normalised to the current surface by filling the header from the reference signature where the reply left it out, then as `asl` |

- The normaliser is honest only for the entry function, whose signature the task fixes. Helper functions the model invents have no reference signature, so until INFER-04 lands their omitted types are filled by the normaliser from a per-task run of the probe in section 4 or the trial is scored as failed at stage `check`. Both scores are published.
- Decision rule: private-function inference (INFER-04, INFER-05) is adopted only if raw pass@1 of `aslInferred` is not more than 5 points below `asl` on both models and tokens per solved task is lower. If `aslInferred` is worse, only lambda and private return-type inference proceed.
- Expected directions, stated before any run: fewer header-shape failures (less to get wrong on the line), more type errors surfacing far from their cause (Int and Float never mix, Option is explicit, so a model that relied on the header to keep itself consistent loses that), no change on enum and match tasks.
- With the wrapped-header arm this gives the 2 by 2: {bare, wrapped} x {typed, inferred}. `aslWrapFn` exists; the fourth cell is `aslWrapInferred`.

### How others draw the line

| Language | Line | What an agent gains or loses |
|---|---|---|
| OCaml | everything inferred, including exports; `.mli` interface files optional but conventional, generated by `ocamlc -i` | shortest source; without `.mli` an export's type moves with its body; Merlin answers type-at-point, which is the lens. The `.mli` is the stable unit of reading and the build's cache key |
| Haskell | top-level signatures optional in the language, required by convention and by `-Wmissing-signatures`; local bindings inferred | the community reached "write the top level, infer the rest" by itself, for error locality |
| Rust | function signatures mandatory, everything inside inferred; no global inference by design | errors never cross a function boundary; a signature is always greppable. Cost: the header tokens measured above |
| TypeScript | parameters must be typed (or contextually typed), returns inferred; `.d.ts` generated; `isolatedDeclarations` (5.5) makes exported returns mandatory so declaration files can be emitted without type checking | the newest data point, and it moved toward mandatory exports for exactly the compile-speed and cache-key reason in 3 above |
| Crystal | global inference, annotations rarely needed | shortest of the typed languages; pays with whole-program compile times, no separate compilation and errors far from their cause |
| Python | optional, unchecked by the language | the cheapest to write and the prior models know best; the type is found by reading the callee or not at all |

ASL today is at Rust's line. The proposal moves it to Haskell-by-convention made mandatory, which is where TypeScript's `isolatedDeclarations` landed: **exports written, everything else inferred, every inferred fact one question away.** Crystal's line is rejected on compile speed and error locality, OCaml's without `.mli` on stability.

## 3. The type lens

Everything the checker knows and the source does not say is served by one mechanism with four entry points. All answers are single-line ASN rows followed, when text was asked for, by the unchanged source: the code is never rewritten for display, so an anchor copied from a lens answer still matches the file.

### Agent plane

| Form | Answer | Tokens (measured in section 5 or estimated from it) |
|---|---|---|
| `(:read :file F :symbol S :types true)` | the symbol's text, one `(:fn ...)` row for it (signature, effect, witness, let types) and one `(:use ...)` row per imported or local name its text mentions | text plus 30 to 47 per row |
| `(:read :file F :types true)` | the same for a whole file | file plus rows |
| `(:read :file F :types table)` | rows only, no text: the outline with types | 30 to 47 per function |
| `(:observe :dim type :symbol S)` | one row: `(:type "pkg/mod#name" :sig "..." :fx pure :from "path:line" :inferred (ret))` | about 40 |
| `(:observe :dim type :file F :at "12:18")` | the type of the smallest expression at that position: `(:type :at "12:18" :expr "(listHead xs)" :is "(Option Int64)")` | about 30 |
| `(:query :text T)` | each definition hit carries `:sig` and `:fx`, so a search result is enough to write the call | plus 15 to 25 per hit |
| `(:read :card "asl-json/json")` | the module card, below | 300 to 800 |

`:types` is off by default so existing callers and the byte-stable prefix (rule context) do not change. `:inferred (...)` lists which parts of a signature were not written in the source, so a reader always knows what is a promise and what is a consequence.

Row grammar (the prototype prints exactly this):

    (:lens :file "<path>" :module "<name>" [:symbol "<name>"] :basis (declaredSignatures inferredEffects [probedLetTypes]))
    (:use "<alias/name>" :sig "<fn signature | schema | enum | case of Enum>" :from "<module path | local>")
    (:fn "<name>" :line N :sig "<params -> ret>" :fx pure|effect [:marked false] [:via "<builtin>"] [:lets ((name "Type") ...)])
    (:source)
    <text>

### The module card

One generated file per module: every export with its full signature (inferred parts filled in), effect and the witness of the effect, exported types with fields and cases, and the interface digest.

- It extends the existing asl-know L2 rows (`(:sym name :mod :kind :sig)`) with `:fx`, `:via`, `:inferred` and a header `(:iface :module M :digest D :src S)`. One artefact serves three purposes: the unit of reading for an agent (asl-json: card 764 tokens against 5 907 for the source, asl-csv 632 against 2 762), the interface the checker compiles importers against, and the cache key.
- It is not a second source of truth. Rule ledger applies: what a command reconstructs is not stored in the tracked tree. Cards live in the build cache next to the check stamps, keyed by source digest, and are regenerated by `asl check`; the tracked asl-know cards remain a published rendering for readers without a build.

### Staleness

A lens answer is a function of (file bytes, dependency interface digests, checker version). The model is:

- **Signature and use rows** come from a parse and the dependency summaries: recomputed on every call, never stale, a few milliseconds per file. No cache.
- **Effects** need the closure's call graph; they are computed from the summaries the check cache already holds, and the row carries `:asOf <digest>` only when it was served from a stamp.
- **Expression and let types** need a check of the module. They are served from the check stamp when the module's digest matches, computed on demand otherwise, and when the module does not check at all the answer says so, `(:type ... :stale checkFailed :diag "path:line:col code")`, instead of guessing. Staged content (rule txn) is checked as staged: the lens sees what `(:check)` sees.
- An answer never mixes generations silently: every row from a stamp carries the digest it was computed for, and a mismatch downgrades the row to `:stale true` with the reason.

### Human plane

- **Terminal**: `asl lens FILE [--symbol S]` prints the source with inlay hints as dim trailing text: inferred return types after the header, `: Type` after each let name, `!` and the witness after an effectful function, and the signature of an imported name once, at its first use. `--plain` gives the ASN rows.
- **HTML**: `asl lens FILE --html` renders the same rows through asl-html: the source in a `pre`, each hint a `span` with a class per fact kind (type, effect, inferred, stale), hover on an imported name shows its card row, and a toggle hides or shows each kind. The page takes its data as the ASN rows, so `tools/map` can embed it per module without a second generator: the map's module node links to the module's lens page, and the map's edge list already knows which cards to preload.
- Colour is the only place where the two planes differ. The facts and their order are identical, so a person and a model looking at the same symbol see the same thing.

## 4. What the checker has to export

The prototype uses only what `asl-checker` exports today, and that boundary is the finding:

| Fact | Available today | How the prototype gets it | Missing API |
|---|---|---|---|
| declared signature of a function, schema, enum, case | yes, `resolve.collectSummary` | direct | none |
| signature of an imported symbol | yes, `resolve.loadModuleClosure!` gives every dependency's summary | direct | none |
| inferred effect and its witness | yes, `resolve.refineEffects` | direct | none |
| type of a let binding | computed inside `check.asl`'s frame machine, not exported: `checkSource` returns diagnostics only | a probe: one binding per function is annotated with a fresh schema type in an in-memory copy, `checkSource` is run, and the type is read back from `ERR_TYPE_MISMATCH let binding: expected TypeLensProbe, found T`; one check per round, rounds = the largest number of bindings in one function | `check.typedBindings forms deps path -> (List (name line col Type))` |
| type of an arbitrary expression, lambda parameter, match binder | no | not done | `check.typeAt forms deps path line col -> (Option Type)`, which needs positions on `rd/SExpr` nodes (the reader drops them; only top-level `PosForm` keeps a line) |
| inferred return or parameter type of an unannotated function | not applicable: the checker rejects them | not done | arrives with INFER-03 and INFER-04 |

The same gap shows on the compile side: the native lowering rejected the prototype's first build with `'with' needs a record of known schema: annotate the value` for a variable bound by a match arm whose type the checker had already inferred. The checker's types do not reach the lowering, so today some annotations are mandatory only because two passes do not share one typed tree. Exporting it (INFER-02) serves the lens and removes that class of forced annotation at once.

## 5. Prototype results

See the `:prototype` rows of `.asl/mem/audits/fable-20261113/inference.asn` for the commands, exit codes and sizes of this section.

Commands, all through `./bin/asl` at main on 2026-11-13, one niced process at a time:

| Command | Exit | Result |
|---|---|---|
| `asl check tools/typeLens/typeLens.asl` | 0 | 17 modules checked |
| `asl test tools/typeLens/tests/typeLensTest.asl` | 0 | 8 assertions and 3 refutations executed |
| same test, mutant: member looked up by the alias instead of the name | 1 | fails at "the imported function's signature is shown" |
| same test, mutant: no probe annotation inserted | 1 | fails at "each unannotated let binding carries the checker's inferred type" |
| `asl run tools/typeLens/typeLens.asl asl/packages/asl-checker/src/lint.asl --lets` | 0 | 5 s |
| `asl run tools/typeLens/typeLens.asl tools/map/map.asl --symbol dataJson --lets` | 0 | 2 s |
| `asl run tools/typeLens/typeLens.asl tools/map/map.asl` | 0 | 3 s |

The test also holds the mutant as data: the same importer is viewed against a dependency whose `scale` returns `Float64`, the row must change and the old signature must be absent.

What a reader gets and what it replaces (`o200k_base` tokens):

| View | Lens answer | Of which fact rows | Files it replaces | Share |
|---|---|---|---|---|
| `lint.asl`, whole file, let types | 2 147 | 1 040 in 22 rows | lint 1 104 + reader 2 170 + ast 27 589 + resolve 38 839 = 69 702 | 3.1 % |
| `map.asl`, symbol `dataJson`, let types | 994 | 598 in 14 rows | map 9 963 + json 5 907 = 15 870 | 6.3 % |
| `map.asl`, whole file | 14 587 | 4 621 in 121 rows | map 9 963 + html 5 236 + json 5 907 + fleet/run | under 69 % |

The replaced column is the upper bound, whole files; an agent that already reads by symbol pays less, but still one `(:read :symbol)` round trip per imported name (12 for lint, 5 plus 8 local callees for `dataJson`), each of which the lens answers in the same call. A row costs 38 to 47 tokens today because `:from` is an absolute path; relative paths bring it to about 30.

What the prototype shows today:

- the declared signature of every function in the file or the one asked for, with its line;
- the inferred effect of each, `:marked false` when the source has no `!`, and the builtin that causes it;
- the checker's inferred type of every unannotated let binding (probe, exact, one extra check per round);
- for every imported name the text mentions, as a call, a constructor, a pattern or a type in a signature: the function signature and effect, the schema with fields, the enum with cases, or the case with its owner;
- in symbol mode, the signature of every local function the symbol calls.

What is missing, and the row that supplies it:

- types of lambda parameters, match binders and arbitrary expressions; `:at line:col` (INFER-02);
- local schemas and enums named in a symbol's signature (`Model`, `PlanRow` in the `dataJson` view) are not listed in symbol mode; builtin signatures are left to `(:help :builtin)` (INFER-01);
- `:from` is absolute and the module is addressed by file, not by `pkg/mod#name` (INFER-01);
- no cache: every call parses the import closure (2 to 5 s here under load 20 to 30); no staleness marks because nothing is cached yet (INFER-03);
- a file that does not check gets signatures and effects but silently no let types; the design's `:stale checkFailed` row is not printed (INFER-01);
- no terminal inlay or HTML rendering (INFER-08); not an op of the agent plane, only `asl run` (INFER-01).

## 6. Staged plan

Rows `INFER-01..09` in `inference.asn`, in backlog schema. Order and reason:

1. **INFER-01 lens as an op** (sonnet): `:types` on `(:read)`, `(:observe :dim type :symbol)`, `:sig` on `(:query)` hits, from summaries only. No checker change. This is the half of EFFECT-INFER that was never built.
2. **INFER-02 typed tree export** (opus): positions on reader nodes, `typedBindings` and `typeAt`; the probe in the prototype becomes the gate's oracle and is then deleted.
3. **INFER-03 module card as interface and cache key** (opus): digest of exports, early cutoff in `checkCached`.
4. **INFER-04 experiment arm** `aslInferred` and `aslWrapInferred` (sonnet), run with FABLE-LANG-01; decides 6 and 7.
5. **INFER-05 lambda annotation codemod** (haiku draft, sonnet gate): executes LAMBDAINFER-RESYNC.
6. **INFER-06 private return types optional** (opus), after 2.
7. **INFER-07 private parameter types optional** (opus), only if the arm passes.
8. **INFER-08 human view**: `asl lens`, HTML overlay, map embedding (sonnet).
9. **INFER-09 `asl fix --annotate`** and origin-carrying diagnostics (sonnet), with 6.

Exported signatures, schema and enum declarations, explicit `some` and `ok`, and export lists do not change in any stage.
