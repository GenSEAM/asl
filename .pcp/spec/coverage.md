# Spec / Coverage

This file groups d/c/r/l entries for the spec/coverage module.

### [l-3434] Most of the vocabulary has never appeared in an example
- **Date**: 2026-08-20
- **Status**: Deferred
- **Cluster**: spec/coverage
- **Description**: Roughly a quarter of the declared builtins are exercised anywhere in the
  specification or the conformance corpus. The rest are declared in tables and never shown in use,
  so their signatures are unverified and no worked example teaches them.
- **Rationale**: The specification is the artifact injected into the prompt. Examples carry more
  weight than tables for a reader that learns by pattern, so an unexercised builtin is close to an
  absent one from the point of view of the thing being optimised.
- **Why Non-Obvious**: The closure gate passes, which proves no example uses an undefined name. It
  says nothing about the converse — defined names that no example uses — and that direction is the
  one that degrades generation quality.

### [d-4e21] Vocabulary coverage is enforced by a gate, not tracked as a number
- **Date**: 2026-08-21
- **Status**: Active — resolves `l-3434`
- **Cluster**: spec/coverage
- **Description**: `prelude/coverage_audit.py` fails when any builtin declared in `prelude.json`
  appears in no example, scanning the conformance corpus, `examples/`, `bench/` and `backend/t`.
  Coverage went from 22 of 92 to 103 of 103, and adding a builtin without an example now breaks a
  gate rather than lowering a statistic nobody reads.
- **Rationale**: This is the converse of the closure gate, and the repository's existing idiom: a
  property the specification claims is worth exactly what a command enforces. `l-3434` recorded the
  gap as a deferred task, which meant it could drift back the moment attention moved.
- **Implementation note**: extraction needs three capture kinds, not one. Arithmetic and comparison
  heads are `operator` nodes, `ok`/`err`/`some`/`none`/`list`/`pair` have their own grammar rule
  because their heads double as pattern heads, and only the remainder are `ident` heads. A single
  `ident` query undercounted by 41.
- **Why Non-Obvious**: coverage reads like a documentation metric, so gating on it looks like
  bureaucracy. It is not: the artifact being covered is the one injected into the prompt, and a
  builtin shown only in a table is close to absent for a reader that learns by pattern.
