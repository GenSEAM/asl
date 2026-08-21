# Lang / Lexical

This file groups d/c/r/l entries for the lang/lexical module.

### [c-099a] Reserved-prefix rule names a form the lexer cannot produce
- **Date**: 2026-08-20
- **Status**: **Resolved 2026-08-21** — the prefix is now `as-`, which the identifier rule
  produces, and the fixture `reserved-prefix.as` declares `as-internal`: a name that genuinely
  lexes, so a checker rejecting it would be rejecting it for the stated reason. The prefix also
  has its first real user — the entry point a backend emits for `defentry` is `as-entry`, which is
  what makes the reservation load-bearing rather than decorative.
- **Cluster**: lang/lexical
- **Description**: The specification reserves an identifier prefix for compiler-internal names,
  but writes that prefix in a shape the identifier rule cannot lex. The rule therefore never
  fires, and the conformance fixture meant to prove it is rejected for an unrelated lexical
  reason instead.
- **Why Non-Obvious**: The fixture passes, the gate is green, and the reserved namespace looks
  defended. It is not: a name that actually matches the identifier rule and starts with the
  reserved word is accepted. A test that passes for the wrong reason is worse than a missing
  test, because it removes the pressure to write the right one.
