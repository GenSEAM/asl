# Lang / Types

This file groups d/c/r/l entries for the lang/types module.

### [r-b539] Closed tagged unions and keyed collections are coverage-critical
- **Date**: 2026-08-20
- **Status**: Active
- **Cluster**: lang/types
- **Description**: Two absences bound how much of a real domain can be typed. Without a
  user-declarable closed union, domain states get encoded as strings or integers, which defeats
  the type-safety goal at exactly the points where it pays. Without a keyed collection, a large
  class of ordinary programs cannot be written at all.
- **Requirement**: Users can declare a closed set of alternatives and destructure it
  exhaustively; an associative collection is available with the same totality discipline as the
  existing option-returning accessors.
- **Why Non-Obvious**: Benchmark suites of small self-contained functions rarely need either, so a
  benchmark-driven scope decision will systematically under-weight both while the compiler itself
  cannot be written without the first.

### [d-c912] Type identity is nominal, keyed by defining module and name, never by alias
- **Date**: 2026-08-29
- **Status**: Active
- **Cluster**: lang/types
- **Description**: Two types are the same type when the same module declared them under the same
  name. A union declared in one module and a same-named one declared in another are different
  types; one module reached through two different aliases yields one type.
- **Rationale**: An alias is module-local and chosen freely by whoever imports, so letting it
  participate in identity would make a type's identity change when an importer renames its alias —
  destroying the property the module system exists for. Structural identity was rejected for a
  different reason: it contradicts the tagged runtime representation both backends emit, and it
  would make a closed union's guarantee meaningless the moment the union crossed a boundary.
- **Why Non-Obvious**: Both wrong answers leave every gate green. Alias-keyed identity fails only
  when one module is imported twice; name-keyed identity fails only when two modules pick the same
  name — and neither shape occurs unless a fixture is written to force it.
