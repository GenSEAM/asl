# Lang / Ffi

This file groups d/c/r/l entries for the lang/ffi module.

### [d-4b8c] The reason to exist is a total boundary over an untyped ecosystem
- **Date**: 2026-08-21
- **Status**: Active
- **Cluster**: lang/ffi
- **Description**: The language competes not by replacing the host ecosystem but by being a
  checked, total layer over it. Foreign functions are declared with types, and **every foreign call
  yields a fallible value rather than a bare one**, so a caller cannot use a result without
  accounting for failure.
- **Rationale**: Host type stubs declare argument and return types but carry **no exception
  information whatsoever**. A statically checked program in the host language therefore still
  cannot see that a call may fail — the failure is invisible to its own checker. Wrapping every
  foreign call makes the boundary total by construction, which is strictly more safety than the
  host's own checker can express, not merely equal to it. Optional host types map onto the
  language's own optional type, so absence is handled rather than discovered at runtime.
- **Feasibility, measured**: bindings are derivable mechanically. Runtime introspection of the host
  yields nothing, but the separately shipped stub corpus covers the standard library broadly and a
  prototype generated correct declarations from it, including optional types. Generation must parse
  stubs properly rather than by pattern matching; a regex prototype produced visible defects.
- **Costs accepted**: foreign interop moves from excluded to central, which reverses an earlier
  scope decision. A module that binds host libraries is no longer portable across targets —
  portability survives only for the pure core, and the effectful edges belong to one ecosystem.
- **Why Non-Obvious**: the obvious framing is that a new language must beat the incumbent at
  writing applications, which it cannot, because applications are mostly ecosystem. The defensible
  framing inverts it: keep the ecosystem, replace only the part where the incumbent is provably
  weakest — the untyped, exception-carrying boundary that its own type checker cannot see.
