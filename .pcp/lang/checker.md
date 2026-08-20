# Lang / Checker

This file groups d/c/r/l entries for the lang/checker module.

### [l-78ae] Semantic checker is the next load-bearing component, not the backends
- **Date**: 2026-08-20
- **Status**: Deferred
- **Cluster**: lang/checker
- **Description**: Most of the conformance checklist cannot be enforced by any grammar: name
  resolution across module boundaries, import cycles, type-variable binding, match exhaustiveness,
  arity, and the reserved-prefix rule are all semantic. Two independent grammars currently agree
  with each other and neither checks any of it.
- **Rationale for priority**: Located evidence puts the great majority of failures in
  LLM-generated code at the type level rather than the syntactic one, with grammar-level
  constraints capturing only a small fraction of the achievable error reduction. Building
  transpiler backends before the checker would be optimising the part already known to be small.
- **Why Non-Obvious**: The conformance gate is green, which reads as "the language is validated".
  It validates only that two parsers agree on shape. Nothing yet rejects a program that imports a
  cycle, calls a function with the wrong arity, or fails to handle a union case.
