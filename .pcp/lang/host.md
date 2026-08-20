# Lang / Host

This file groups d/c/r/l entries for the lang/host module.

### [d-2030] The compiler is hosted in Rust, not Go
- **Date**: 2026-08-20
- **Status**: Active
- **Cluster**: lang/host
- **Description**: One host language was to be chosen for the compiler, with self-hosting as the
  eventual goal. Rust is chosen.
- **Rationale**: The language's defining constructs are closed unions, exhaustive matching, and
  option/result types. The chosen host has all three natively, with exhaustiveness checked by its
  own compiler, so those constructs survive translation intact. The alternative has none of them:
  a closed union must be encoded through an interface and a runtime type switch, and no
  exhaustiveness check exists — meaning the safety property this language is built on would be
  silently discarded at exactly the layer meant to preserve it. A compiler is the most
  union-saturated program there is, so the mismatch would be paid on every AST and IR node.
- **Counter-argument weighed**: the chosen host requires an ownership decision that remains
  unrecorded, which the alternative would not have. That is a decision to be made and can be made
  conservatively at first. The alternative's missing unions are not a decision — they are a
  permanent impedance mismatch with no conservative fallback.
- **Why Non-Obvious**: The alternative looks cheaper on every surface metric: simpler language,
  faster builds, no ownership question, easier hiring. The cost is invisible until the first
  recursive variant type is written, which for a compiler is immediately.
