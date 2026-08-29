# Lang / Lexical

This file groups d/c/r/l entries for the lang/lexical module.

### [c-099a] Reserved-prefix rule names a form the lexer cannot produce
- **Date**: 2026-08-20
- **Status**: Resolved
- **Update 2026-08-29**: retired. The bare prefix is indeed unlexable, but a name that *starts*
  with it is an ordinary identifier, which is what the rule was always about and what the checker
  now rejects. The fixture is rejected under the reserved-prefix rule by name, so it can no longer
  pass for an unrelated reason.
- **Cluster**: lang/lexical
- **Description**: The specification reserves an identifier prefix for compiler-internal names,
  but writes that prefix in a shape the identifier rule cannot lex. The rule therefore never
  fires, and the conformance fixture meant to prove it is rejected for an unrelated lexical
  reason instead.
- **Why Non-Obvious**: The fixture passes, the gate is green, and the reserved namespace looks
  defended. It is not: a name that actually matches the identifier rule and starts with the
  reserved word is accepted. A test that passes for the wrong reason is worse than a missing
  test, because it removes the pressure to write the right one.

### [c-40b5] Two grammars can accept the same text and disagree about what it means
- **Date**: 2026-08-29
- **Status**: Active
- **Cluster**: lang/lexical
- **Description**: The conformance gate compares accept/reject verdicts, so it is blind to the two
  grammars building different trees for a program both accept. This happened: a qualified name in
  head position was re-lexed by the Earley grammar as an alias, the division operator and a member,
  which is a legal call, while the tooling grammar read it as one qualified name. The backend then
  emitted that reading, and the backend gate passed it because it checked only one target's output
  with a compiler.
- **Impact**: the divergence is silent by construction. It is fixed for this case by an explicit
  lexer priority, but the gate that should have caught it still cannot: nothing compares the two
  trees. Until something does, agreement between the grammars is asserted for shape and checked
  only for verdict.
- **Why Non-Obvious**: "both grammars parse every fixture" reads as "the grammars agree". It means
  they agree on the *language*, which is a weaker claim than agreeing on the *parse*, and the
  weaker claim is the one the gate tests.

### [l-b1b8] The pattern rule carries one alternative per prelude case, and the parser never takes any of them
- **Date**: 2026-08-29
- **Status**: Deferred
- **Cluster**: lang/lexical
- **Description**: The Lark grammar spells out a separate pattern alternative for each of the
  prelude's own union cases, alongside the general alternative for a user-declared case. The Earley
  parse resolves every one of those patterns to the general alternative instead, so the specific
  alternatives produce no node and no consumer can ever be reached through them.
- **Rationale for deferring**: nothing is broken. Both emitters and the checker treat a prelude case
  exactly as they treat a user-declared one, which is the behaviour d-5837's nominal identity wants
  anyway — a prelude union should not be a second kind of union — so removing the alternatives is a
  simplification rather than a fix, and it touches the artifact that two grammars must agree on.
  Deferred until something else opens the pattern rule, so the change is made and re-gated once.
- **Why Non-Obvious**: the grammar is the document a reader consults to learn what the parse tree
  looks like, and it currently describes a shape the parser does not produce. Anyone writing a new
  consumer will handle nodes that never arrive, and will read the absence of those nodes in a trace
  as evidence their own code is wrong. A dead production is not neutral: it is a false statement in
  the artifact whose whole purpose is to be normative about shape.
