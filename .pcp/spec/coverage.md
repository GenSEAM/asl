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
