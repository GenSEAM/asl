# Lang / Backends

This file groups d/c/r/l entries for the lang/backends module.

### [l-880d] Native backends are gated behind the checker and the ownership question
- **Date**: 2026-08-20
- **Status**: Partly resolved
- **Cluster**: lang/backends
- **Update 2026-08-21**: a systems-target backend now exists and its output is accepted by the
  target compiler, built on the conservative ownership strategy below rather than on a resolved
  model. What remains open is the cost of that strategy, which is now measurable rather than
  hypothetical: values are cloned at every use site.
- **Description**: Native code generation for the priority targets was postponed. Two prerequisites
  are unmet: there is no semantic checker to guarantee the input is well-formed, and no decision
  has been recorded on how values are owned and shared, without which the systems-language backend
  has to guess at every signature.
- **Rationale**: Self-hosting the compiler into native targets was chosen deliberately, and that
  choice rules out the cheaper alternative of a single shared runtime with thin bindings. The cost
  of that choice is that ownership, identifier mangling, numeric widths and concurrency must each
  be genuinely resolved rather than avoided.
- **Why Non-Obvious**: A tree-walking reference implementation is enough to measure generation
  quality, so it is tempting to treat backends as the next milestone. They are the expensive
  milestone, and everything they depend on is still open.

### [c-15f3] The corpus exercises forms, not combinations of them, and that is where the defects were
- **Date**: 2026-08-29
- **Status**: Active
- **Cluster**: lang/backends
- **Description**: Every form in the language appears in some fixture, and the gates are green on
  all of them. Two wrong-code defects nevertheless survived until a program combined forms that had
  only ever appeared apart: a constructor pattern *inside* another pattern was lowered as a binder,
  so it matched every value of the outer case; and a list match *inside* another list match
  overwrote shared backend state, dropping the outer arm's binding. Both produced output the target
  compiler accepted.
- **Impact**: coverage measured per form reads as complete while the combinatorial surface is
  untested, and the failure mode is silent — wrong answers, not crashes, on paths a happy-path
  fixture never takes. The differential gate is the only instrument that would have caught either,
  and until this milestone it ran exactly one program.
- **Why Non-Obvious**: the closure gate answers "is every name defined" and the corpus answers "is
  every form lowered", so between them they look like coverage. Neither asks whether a form still
  behaves when it is nested inside another, which is what real programs do constantly.

### [d-84a9] Backends link the transitive import closure into one output unit
- **Date**: 2026-08-29
- **Status**: Active
- **Cluster**: lang/backends
- **Description**: A program and every module it imports, transitively, are lowered into a single
  target artifact, with each imported module's names prefixed by the module path that defines them
  — never by the alias reaching them. Emission stays dependencies-first.
- **Rationale**: Every gate in the tree builds exactly one target artifact from exactly one source
  path. Emitting one target module per source module would require a build driver, a package
  layout and a link step on each target before a single fixture could be gated, which is a large
  cost paid before anything is observable. Whole-closure linking reuses the module resolution the
  checker already performs and keeps every gate driving one artifact.
- **Why Non-Obvious**: What it costs is separate compilation and per-module target packaging, and
  that cost is not visible while every program is small. It is worth revisiting when a target has
  its own module system to honour rather than merely a namespace to borrow.

### [c-055e] The Rust lowering dropped every type-parameter binder, had no indirection for a recursive case, and derived comparison traits by declaration kind rather than by content
- **Date**: 2026-08-29
- **Status**: Active
- **Cluster**: lang/backends
- **Description**: A generic declaration of any kind lost its binders in the Rust output, a
  self-referential union was emitted without indirection, and records derived equality and ordering
  unconditionally while unions derived neither. One corpus fixture produced thirteen compiler
  errors.
- **Why Non-Obvious**: It was invisible because that one fixture sat on the backend gate's skip
  list, and a skip-list entry reads as a known gap rather than as an untested defect — nobody
  re-derives what a skip is actually hiding. Two follow-on facts only appear once the binders are
  emitted: the ownership strategy clones at every use site, so a bare type parameter needs a
  cloning bound or the code stops compiling; and the comparison derives have to be conditional on
  content, because the floating-point type implements neither of them and the derive fails at the
  declaration rather than at a use. The same missing derives independently blocked eight builtins
  found from the vocabulary side — one defect with two discoverers.

### [c-4c51] A body's non-final expressions were evaluated for their value and then discarded, so an effect lowered as a pure expression vanished
- **Date**: 2026-08-29
- **Status**: Active
- **Update (2026-08-29, after review)**: the description below blames one backend. Both had it, in
  the same shape, and both were fixed by the same shared helper — checked against the head commit,
  not taken from a report. That matters for the lesson rather than for the credit: a defect present
  in both emitters is one the differential gate cannot see, which is why d-c15c exists.
- **Cluster**: lang/backends
- **Description**: Where a body holds several expressions, only the last one's value is the body's
  value; the earlier ones are there for their effect. The Rust lowering computed each of them and
  then threw the result away without emitting it, so any earlier expression that lowered to a pure
  expression rather than to statements disappeared from the output entirely.
- **Why Non-Obvious**: It hid behind the shapes that happen to lower to statements — most do, and
  the ones that do not are exactly the effectful forms whose absence is silent. The output still
  compiled and still exited zero; the only symptom was a missing line of program output. The
  differential gate caught it on the first program that put a propagating call in a non-final
  position, which is the second defect that gate has found in how one form nests inside another,
  and neither would have been visible to a gate that only compiles.

### [d-9dd9] The emitters carry a real lexical scope, rather than a special case for the shadowing that exposed its absence
- **Date**: 2026-08-29
- **Status**: Active
- **Cluster**: lang/backends
- **Description**: Each emitter maintains a stack of the names bound at the point it is emitting,
  pushed and popped by every binding form, and a name resolves against that stack before it
  resolves against anything module-level. The defect that exposed the gap — a binder inside an
  imported unit sharing a name with one of that unit's own definitions, which was emitted as the
  definition — is a consequence of the missing scope, not a case to be handled.
- **Rationale**: Lowering is a translation between two scoping disciplines, so an emitter without a
  scope is not incomplete, it is unsound; the symptom is a function of which names happen to
  collide, and every future collision shape is a separate special case. The stronger reason to pay
  for the general fix here is what the failure looked like: it was silently wrong on *both*
  backends and wrong the same way, so the differential gate compared two wrong answers and found
  agreement. A gate built on cross-backend agreement cannot be the thing that tells us a scoping
  rule is right, because both emitters share the assumption that is wrong.
- **Why Non-Obvious**: the root-unit case was correct throughout, which is the case every existing
  fixture exercised, so the defect reads as impossible from the passing evidence. Shadowing is also
  the archetypal "rare in practice" shape, and treating it as rare is what makes an emitter without
  a scope survive to the point where the wrong output is trusted.
