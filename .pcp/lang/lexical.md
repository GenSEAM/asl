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

### [d-9c1f] The language is renamed AgentScript, and the identifier surface moves with it atomically
- **Date**: 2026-08-30
- **Status**: Active
- **Cluster**: lang/lexical
- **Description**: The name, extension, reserved prefix, runtime alias and tracer env vars move
  together — `AgentS` → `AgentScript`, `.agents` → `.agentscript`, `agents-` → `agentscript-`,
  `_as` → `_agentscript`, `AGENTS_EXEC_COVERAGE`/`AGENTS_EXEC_SOURCE`/`AGENTS_COVERAGE_LOCK` →
  `AGENTSCRIPT_*` — with the tree-sitter grammar name/scope/file-types and the Go module name
  moving too. Frozen by owner: `AGENT_SPEC.md` + `SPEC_REVIEW.md` (v0 provenance), `.plans/**`
  (phase history), the repo directory `asex` and `ASEX_GATEWAY_KEY` (external filesystem/credential
  contracts). The fork's `.as` extension is not adopted: it collides with ActionScript and belongs
  to the abandoned `as-lang` identity.
- **Rationale**: the old name was a working title and the owner named the product. One atomic
  change, not a series, because the extension, reserved prefix, runtime alias and env vars are one
  surface — a partial rename fails loudly (a `; run:` header names the alias the emitter no longer
  imports) or silently (a stale `*.agents` glob reads zero fixtures and a gate with no empty-set
  guard passes).
- **Why Non-Obvious**: the acceptance greps for the old name are themselves easy to get wrong —
  `rg 'AgentS'` and `rg 'tree-sitter-agents'` both match the *new* names `AgentScript` /
  `tree-sitter-agentscript`, so a naive "no old strings" check reports a wall of false positives on
  a clean tree. The gates that actually prove the rename are the word-bounded scans (`\bAgentS\b`,
  `tree-sitter-agents\b`) plus the byte-identity canaries: `prelude/coverage.lock` untouched,
  `backend/cases/*.json` changed only in `"src"`, differential expectations unchanged.

### [l-a250] Comments become unattached string literals, and the replacement does not reach top level
- **Date**: 2026-09-03
- **Status**: Resolved
- **Cluster**: lang/lexical
- **Description**: `;` line comments are retired in favour of **free-standing string literals bound to nothing** — notes. A note parses under both grammars at top level and inside a declaration body, checks clean, and lowers harmlessly on every target; `grammar/corpus/valid/33-notes.agentscript` gates the note and `34-multiline-strings.agentscript` gates the newline escape (the backends escape a newline in a string literal). The removal is complete in the core: `;` is gone from `AGENT_SPEC_CORE.md` §2 and both core grammars, and the native lexer (`packages/asl-parser/src/lexer.asl`) emits an error token for `;`. The conventions that depended on `;` moved with it: `checker/gate.py` reads the rule name from a leading `"expect:"`/`"expect-only:"` note instead of a `; expect:` header, `check_corpus.py` reads run assertions from a `<fixture>.run` sidecar instead of a `; run:` header, and the formatter gained a `note` printer. **Deliberate exception**: ASN keeps `;` line comments because a bare string is a data value there, so the note is not unambiguous; its `COMMENT` terminal lives outside the shared-core terminal block and `docs/ASN_SPEC.md` records the divergence.
