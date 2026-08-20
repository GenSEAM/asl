# Lang / Lexical

This file groups d/c/r/l entries for the lang/lexical module.

### [c-099a] Reserved-prefix rule names a form the lexer cannot produce
- **Date**: 2026-08-20
- **Status**: Active
- **Cluster**: lang/lexical
- **Description**: The specification reserves an identifier prefix for compiler-internal names,
  but writes that prefix in a shape the identifier rule cannot lex. The rule therefore never
  fires, and the conformance fixture meant to prove it is rejected for an unrelated lexical
  reason instead.
- **Why Non-Obvious**: The fixture passes, the gate is green, and the reserved namespace looks
  defended. It is not: a name that actually matches the identifier rule and starts with the
  reserved word is accepted. A test that passes for the wrong reason is worse than a missing
  test, because it removes the pressure to write the right one.
