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

### [d-7a55] A foreign function is named in the language's own case, with an explicit escape
- **Date**: 2026-08-21
- **Status**: Active
- **Cluster**: lang/ffi
- **Description**: `defextern` names its function in kebab-case like every other identifier and
  reaches the host through the §8 mangling that already exists; `:symbol "..."` overrides that for
  the spellings mangling cannot reproduce. The alternative — writing the host spelling directly —
  was rejected because `pl/read_csv` is not a name the identifier rule can lex.
- **Rationale**: Reusing §8 means the boundary introduces no second naming convention, and it means
  `read-csv` reaching `read_csv` costs nothing. But §8 deliberately does not special-case acronyms,
  so it cannot round-trip every host name; `:symbol` makes that failure explicit at the one
  declaration where it happens instead of silently resolving to a name the host does not have. The
  generator emits it exactly when the round trip fails, never always and never never.
- **Why Non-Obvious**: allowing the host spelling verbatim looks like the simpler design and
  removes a concept. It also breaks the lexical rule for every snake_case ecosystem, which is most
  of them — and the specification's own handbook shipped an unparseable example for exactly this
  reason before a gate caught it.
