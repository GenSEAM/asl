# Lang / Checker

This file groups d/c/r/l entries for the lang/checker module.

### [l-78ae] Semantic checker is the next load-bearing component, not the backends
- **Date**: 2026-08-20
- **Status**: Resolved
- **Update 2026-08-29**: built and gated. Every rule listed below is enforced, plus the
  construction rules the conformance checklist omitted and type checking generally. Two of the
  three things it was meant to make visible turned out to be language holes rather than program
  errors: types cannot cross a module boundary (r-ea8c), and a literal had no declared type
  (d-043b).
- **Cluster**: lang/checker
- **Description**: Most of the conformance checklist cannot be enforced by any grammar: name
  resolution across module boundaries, import cycles, type-variable binding, match exhaustiveness,
  arity, and the reserved-prefix rule are all semantic. Two independent grammars currently agree
  with each other and neither checks any of it.
- **Rationale for priority**: Located evidence puts the great majority of failures in
  LLM-generated code at the type level rather than the syntactic one, with grammar-level
  constraints capturing only a small fraction of the achievable error reduction. Building
  transpiler backends before the checker would be optimising the part already known to be small.
- **Why Non-Obvious**: The conformance gate is green, which reads as "the language is validated".
  It validates only that two parsers agree on shape. Nothing yet rejects a program that imports a
  cycle, calls a function with the wrong arity, or fails to handle a union case.

### [d-4e72] The checker is hosted where the tooling already is, and its fixtures are the artifact
- **Date**: 2026-08-29
- **Status**: Active
- **Cluster**: lang/checker
- **Description**: The semantic checker is written in the language the existing parser, gates and
  backends are written in, not in the language chosen to host the compiler (d-2030). The durable
  output of this work is the fixture corpus — each case naming the rule it violates — not the
  implementation, and the eventual port is written against that corpus rather than re-deriving the
  semantics from the specification a second time.
- **Rationale**: The compiler host has no frontend at all yet, so hosting the checker there would
  begin with an AST, bindings and a unifier before a single rule could be enforced, while the
  measurement path stays blocked on a component that does not exist. Hosting it beside the existing
  tooling made it a gate the same day and gave the harness a stage to classify against. What must
  not be duplicated is the *meaning* of a rule, and that lives in the fixtures: a port that passes
  them enforces the same language, whatever it is written in.
- **Costs accepted**: the inference rules get written twice. That is a real cost and it is bounded
  by the fixture corpus, which is what makes the second writing a re-implementation rather than a
  redesign.
- **Why Non-Obvious**: the host decision looks settled by d-2030, and it is — for the compiler. A
  checker that gates a corpus is not yet the compiler, and treating the two as one decision would
  have paid the compiler's startup cost to get a gate.

### [c-2d38] A pass that recurses on one node kind silently skips every form whose children are of another
- **Date**: 2026-08-29
- **Status**: Active
- **Cluster**: lang/checker
- **Description**: The resolve pass descended through expressions only. A conditional's children
  are clauses rather than expressions, so every check that pass owns — name binding, the effect
  marker, call arity, construction — was disabled inside every conditional in the corpus, for as
  long as the form has existed. The same shape appeared once more, one layer down: a record field's
  default is a value of that field's type and was never typed against it.
- **Rationale**: Recorded as one entry with two instances because the lesson is the class, not
  either instance. A traversal is a claim about which forms a pass reaches, and that claim is
  invisible in the pass itself: the code reads as complete, because the branch it never takes is
  spelled nowhere. The durable countermeasure is a descent that continues through intermediate
  nodes by default and requires a form to opt out by declaring a handler, so a newly added form is
  reached rather than skipped — the failure mode of the safe default is a redundant visit, of the
  unsafe one a silent hole.
- **Why Non-Obvious**: no gate could see either instance, and none was weak — a hole in a traversal
  produces *fewer* diagnostics, and every fixture that would have exposed it was a program the gate
  expects to pass. Both were found by reading the pass against the grammar, and the corpus was
  green before and after. Coverage of a rule is therefore not evidence the rule runs everywhere the
  grammar admits the form; only a fixture placing the violation inside each nesting shape is.

### [d-bad1] A check the conformance checklist does not list is coded by name, never by the next free rule number
- **Date**: 2026-08-29
- **Status**: Active
- **Update 2026-08-29 (Phase 2)**: `map-key-order` (d-2c8f) is the second such check. The plan it
  came from carried a parked instruction to code it `rule-14`; this entry overrode that, §9's items
  1-13 were read in full, and none covers the domain of a `Map` key (item 6 governs mixing numeric
  *operands*). The asymmetry recorded below therefore grows by one rather than being closed.
- **Cluster**: lang/checker
- **Description**: Diagnostic codes are rule numbers exactly where the specification's conformance
  checklist has a corresponding item, and descriptive names everywhere else. A check with no
  checklist entry — the arity of a type application, and the checker's own internal failure — is
  named rather than given the next unused number.
- **Rationale**: The numbers are not the checker's namespace; they are the checklist's, and a
  fixture declaring the rule it violates is asserting against the specification rather than against
  the implementation. Minting a number the specification does not define would make the checker the
  authority on what the rules are, which is the inversion the fixture corpus exists to prevent, and
  it would collide the moment the checklist grows an item of its own. A name also survives a
  renumbering of the checklist, which a number does not.
- **Consequence accepted**: the checklist and the checker's diagnostic set are no longer in
  one-to-one correspondence — the checklist has no item for type-application arity, so a reader
  enumerating the rules will not find that check among them. That asymmetry is the price of keeping
  the numbers meaning what the specification says they mean, and it is recorded here rather than
  discovered later. Closing it means adding a checklist item, which is a specification change.
- **Why Non-Obvious**: taking the next number reads as the tidier option and costs nothing visible
  on the day. What it costs is the property that a fixture's declared rule is checkable against a
  document rather than against the code that produced it.

### [d-2c8f] A Map key must be orderable, so Float64 is not a legal key type
- **Date**: 2026-08-29
- **Status**: Active
- **Update 2026-08-30 (Phase 2 fix wave)**: raised from the syntactic pass to the type layer.
  `map-key-order` now reports against the *inferred* type at every `Map`-producing call site
  (`map-empty`, `map-from-pairs`, `map-set`), not only against a written `(Map K V)` annotation, so
  a `Float64` key reached through inference — `(map-from-pairs (list (pair 1.5 "a")))` — is rejected
  where it previously checked clean and failed at `rustc` with `E0277`. The implementation review
  demonstrated the gap live; `grammar/corpus/semantic/map-key-inferred.agentscript` and
  `checker/t/test_map_keys.py` pin it.
- **Cluster**: lang/checker
- **Description**: The checker rejects any declared type in which `Float64` occurs anywhere inside a
  `Map`'s first argument, recursively — `(Map Float64 V)`, `(Map (Pair Float64 T) V)`,
  `(Map (List Float64) V)` — under the code `map-key-order`. The specification's type table said `K`
  must support equality while §6 specified `map-keys`, `map-values` and `map-pairs` as ordered by
  sorted key; sorting needs an order, not equality. Both the table and `HANDBOOK.md` now say so.
- **Rationale**: the declaration was wider than any backend can implement. `rt.rs` uses `BTreeMap`,
  which needs `Ord`, and `f64` has no total order, so all forty `K = Float64` instantiations across
  the ten `Map` builtins type-checked and twenty-four of them failed at `rustc`. Repairing this
  would mean replacing the Map representation for every program to support a key type the
  specification never intended. Narrowing before the Tier-A sweep is what lets that gate's floor be
  100% rather than 100% minus a skip list.
- **Costs accepted**: this is a language narrowing — a program that type-checked yesterday does not
  today. Measured blast radius on the corpus, the modules and the bench sources: zero. It reaches
  the handbook at a cost of about sixty characters, because a narrowing the model-facing artifact
  does not carry makes the language narrower without making the *taught* language narrower.
- **Deliberately not covered**: `defschema` derives `Ord` unconditionally, so a record with a
  `Float64` field is an equally illegal key and an equally illegal `list-sort` element. That is the
  `defenum`/`defschema` derive defect Phase 1 owns; extending this check through user types belongs
  with that fix.
- **Why Non-Obvious**: the contradiction is between two sections of one document, each defensible
  alone, and the checker enforced neither — so the only symptom was a `rustc` error about a trait
  bound in the runtime, which reads as a backend bug rather than a specification one.

### [d-4a19] Per-call-site instantiations are serialized out of the checker, not written by hand
- **Date**: 2026-08-29
- **Status**: Active
- **Cluster**: lang/checker
- **Description**: `checker/resolve.call_instantiations(path, roots)` returns every builtin call site
  in a file with the concrete types its arguments were inferred at. It is serialization of inference
  that already runs — `types_.declared` with `fresh` given is exactly instantiation — and the
  coverage tracer intersects it with the sites that actually ran, keyed by (source, line, column).
- **Rationale**: the rule "an `N`-typed builtin must execute at `Int64` and at `Float64`" is the
  whole Tier-B guard against the defect class this phase exists to close, and in the plan it was a
  hand-written field in a lock file. A hand-written field is a claim about coverage that nothing
  checks; the intersection makes it a measurement. The intersection, rather than the checked sites
  alone, is what matters: a builtin may be *called* at `Float64` on a line no case reaches.
- **Costs accepted**: only the root unit's sites are reported. The checker collects an imported
  module's header and never walks its body, so no instantiation exists for it to report, and the
  tracer records sites in the root unit only to match.

### [c-5d55] A builtin name in value position typed clean and lowered to a dangling reference
- **Date**: 2026-09-03
- **Status**: Final
- **Cluster**: lang/checker
- **Description**: §6 gives a builtin a type, not a value: Core has no first-class reference to one, and a higher-order position takes an `fn` that calls it. Nothing enforced that. `(map string-upper xs)` checked clean and emitted `string_upper(_x)` on Python and `string_upper.clone()` on Rust — a name that exists in neither output, because builtins are lowered as inline templates rather than as functions. The same hole made a common typo silent: `==` is not an operator, so `(== a 0.0)` lexes as `=` applied to `=`, `a` and `0.0`, which typed clean and lowered to `_agentscript.eq(=, a)` and to `(= == a.clone())`. The resolver now reports `builtin-reference` for a builtin name outside call-head position, and two fixtures pin it.

### [c-eddd] Builtin call arity went unchecked and silently dropped arguments
- **Date**: 2026-09-03
- **Status**: Final
- **Cluster**: lang/checker
- **Description**: `callee_arity` deliberately returned nothing for builtins, reasoning that `list` is variadic as a constructor and nullary as a pattern and that telling them apart needs the type layer. A pattern never reaches a call node, so only the variadic case actually needed excusing — and excusing all of them cost a wrong answer rather than a missing diagnostic: `(and a b c)` checked clean and the Python backend emitted `(a and b)`, discarding the third operand with nothing reported. It was found in the self-hosted lexer, where four of `is-symbol-char`'s six clauses had never run. Arity now comes from §6's declared signature for every non-variadic builtin.
