# Lang / Typing

This file groups d/c/r/l entries for the lang/typing module.

### [d-133a] One strictly typed language, made small by inference rather than by a mode switch
- **Date**: 2026-08-21
- **Status**: Active
- **Cluster**: lang/typing
- **Description**: A typed/untyped mode switch was considered as a way to cut token cost and
  rejected. The language stays strictly typed everywhere; the cost is reduced by inferring types
  instead of by allowing them to be absent.
- **Rationale**: Measured on the first benchmark task, inference recovers about two thirds of the
  distance to a fully untyped dialect while giving up nothing. The remaining difference is
  annotations on the exported surface, which exist so a later pass can compose a module by reading
  only its contract — the property the whole design is for.
- **Costs of the rejected switch**: an untyped dialect cannot target a systems language at all,
  since concrete types must come from somewhere; that would eliminate the self-hosting target
  chosen elsewhere. It also doubles what an agent must learn and makes identical source text mean
  different things in different modes, which is the class of ambiguity this language exists to
  remove.
- **Deferred, not refused**: a module-granular gradual mode remains possible later, at the cost of
  fragmenting guarantees at module boundaries. It should be decided from measurement, not
  anticipation — nothing has yet been measured about whether the token cost matters at all.
- **Why Non-Obvious**: "typed" and "annotated" read as the same property, so the cost of writing
  types gets attributed to having them. They are separable, and almost all of the cost is in the
  writing.

### [d-043b] A numeric literal takes its type from context, with one documented default
- **Date**: 2026-08-29
- **Status**: Active
- **Cluster**: lang/typing
- **Description**: An unsuffixed integer literal is whichever integer type its position requires,
  and the documented default width where nothing constrains it. A literal with a decimal point is
  always the float type. Written into the specification, not only into the checker.
- **Rationale**: The specification fixed the numeric widths and forbade implicit conversion but
  never said what type a literal has, so the most ordinary expression in the language — adding one
  to a variable — had no defined meaning and each implementation was free to pick. The alternative,
  requiring a width on every literal, reintroduces exactly the ceremony inference exists to remove,
  and on the most common form in any program.
- **Why Non-Obvious**: fixing the widths reads as having settled numeric typing completely. It
  settles it for *values that have a declared type*; a literal has none, which is why the gap
  survived a specification review that was looking for width ambiguity.
