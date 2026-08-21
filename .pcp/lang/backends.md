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
- **Update 2026-08-21 (b)**: the question is narrower than this entry assumed. It belongs to the
  systems target alone — the two targets adopted in `d-bf87` are reference-counted or
  garbage-collected and raise no ownership decision at all, and one of them now has a working
  backend that never had to answer it.
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

### [d-bf87] Kotlin and Swift replace Go as the priority native targets
- **Date**: 2026-08-21
- **Status**: Active
- **Cluster**: lang/backends
- **Description**: Go was named a priority target throughout the record and never built. It is
  demoted to best-effort — wanted eventually, gated and planned for by nothing — and Kotlin and
  Swift take its place.
- **Rationale**: The reasoning is `d-2030` applied to targets rather than to the compiler's host.
  This language's defining constructs are closed unions, exhaustive matching and option/result
  types. Both replacements have all three natively, with exhaustiveness checked by their own
  compilers, so the constructs survive translation. Go has none of them: a closed union becomes an
  interface plus a runtime type switch with no exhaustiveness check, discarding the safety property
  at the layer meant to preserve it. Neither replacement raises the ownership question `l-880d`
  holds open for the systems target, which is a second reason they are cheaper.
- **Counter-argument weighed**: Go is more widely deployed, builds faster, and its output would be
  more legible to more readers. That buys reach for a language whose value proposition is the
  checking; a target that cannot check what the language guarantees is reach at the cost of the
  claim.
- **Why Non-Obvious**: The demoted target looks like the pragmatic one on every surface metric, and
  the record had already committed to it in three documents. The mismatch is invisible until the
  first closed union is lowered, which for this language is in the first program.

### [l-720b] Mobile platform access is the motive for the target change and is deferred
- **Date**: 2026-08-21
- **Status**: Deferred
- **Cluster**: lang/backends
- **Description**: The product direction behind `d-bf87` is generating whole mobile applications
  for both platforms. Nothing of that direction is in scope yet: the targets were adopted for their
  semantic fit alone, and platform APIs, UI and the foreign boundary that would reach them remain
  outside the language.
- **Rationale**: Adopting the targets is cheap and reversible; committing to the platforms' SDKs is
  neither, and it lands on top of the foreign-boundary decision `d-4b8c` rather than beside it.
  Deciding them together would settle the harder question by implication.
- **Why Non-Obvious**: Once both mobile targets exist, "generate an app" reads as the obvious next
  step, and the absence of I/O, FFI and UI reads as an oversight rather than as three unmade
  decisions.

### [c-6d3f] A backend without a compiler gate is not gated
- **Date**: 2026-08-21
- **Status**: Active
- **Cluster**: lang/backends
- **Description**: The corpus gate invoked `rustc` and `swiftc` but had nothing to invoke for
  Python, so the Python column reported the transpiler's exit code and nothing more. It had been
  emitting `s(/, concat, ...)` — not valid Python — for every qualified name, and every fixture
  read `ok`. `compile()` is the standard library's accept/reject oracle and is now called like the
  other two.
- **Consequences found the same day**: with the gate in place, four further defects surfaced
  immediately that no existing fixture reached — a keyword-collision list with six entries where
  the target has about thirty-five, a runtime higher-order signature that no emitted closure could
  satisfy, unconditional derives on a record holding a user enum, and a synthesized comparison that
  emitted several statements on one line and so was valid only up to two fields.
- **Why Non-Obvious**: the file's own header already warned that a gate not invoking the target
  measures the transpiler's exit code and nothing more. The warning was acted on for the two
  backends with an obvious external compiler and not for the one whose compiler is a function call,
  because there was no missing binary to notice.
