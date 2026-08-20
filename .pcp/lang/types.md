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
