# Lang / Backends

This file groups d/c/r/l entries for the lang/backends module.

### [l-880d] Native backends are gated behind the checker and the ownership question
- **Date**: 2026-08-20
- **Status**: Deferred
- **Cluster**: lang/backends
- **Description**: Native code generation for the priority targets is postponed. Two prerequisites
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
