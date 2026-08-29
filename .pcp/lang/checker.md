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
