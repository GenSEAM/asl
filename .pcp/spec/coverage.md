# Spec / Coverage

This file groups d/c/r/l entries for the spec/coverage module.

### [l-3434] Most of the vocabulary has never appeared in an example
- **Update 2026-08-29**: no longer only a generation-quality concern. The first two never-exercised
  builtins to be compiled both had broken lowerings for the systems target — one invoked a closure
  literal inline, which defeats the target compiler's own inference, and one passed its arguments in
  the wrong order. An unexercised builtin is not merely undemonstrated; it is unverified, and the
  gates cannot see it because nothing calls it.
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

### [c-c6a3] A gate that asks whether the expected code is among those reported lets a half-implemented rule pass with spurious company
- **Date**: 2026-08-29
- **Status**: Active
- **Cluster**: spec/coverage
- **Description**: The semantic gate asserted that a fixture's declared rule appeared among the
  codes reported, not that it was the only one. A rule can then fire correctly while the pass that
  was supposed to stop reporting a stale resolution failure still reports it, and the fixture
  passes with the defect intact. The same weakness had a twin on the backend side, where a syntax
  check accepted any well-formed lowering, including one that read a qualified name as a division.
- **Why Non-Obvious**: Both look like the strict version of themselves. Asserting the *specific*
  code was already the hard-won lesson over merely asserting rejection, and it is easy to read that
  as finished. The exactness has to be opt-in rather than blanket, because two long-standing
  fixtures legitimately report two codes each — so the honest fix admits that the older fixtures
  keep the weaker guarantee rather than pretending a single assertion covers everything.

### [d-c15c] The differential gate accepts a declared expected output per case, not only cross-backend agreement
- **Date**: 2026-08-29
- **Status**: Active
- **Cluster**: spec/coverage
- **Description**: A whole-program case may state the output the program is supposed to produce.
  The gate then fails on a mismatch against that statement as well as on a disagreement between the
  targets, so a case can be wrong while every target agrees.
- **Rationale**: Cross-backend agreement answers "are the targets equivalent", which is a real and
  separate question, but it is silent on "is either of them right". The two coincide only while the
  emitters' mistakes are independent, and they are not: the emitters share a lowering strategy and a
  set of assumptions, so the likeliest defects are the ones both make. This was demonstrated rather
  than reasoned about — a leading effect inside a conditional clause was dropped by both emitters at
  once, and the gate reported agreement on output neither should have produced.
- **Costs accepted**: the expected output is written by hand and can itself be wrong, and it has to
  be maintained when a fixture changes. That is the point: it is a second, independently authored
  statement of intent, and its cost is what makes it independent.
- **Why Non-Obvious**: a differential gate reads as the strong form of testing precisely because it
  needs no oracle, and adding one looks like a step backwards to ordinary expected-output testing.
  It is the opposite — the oracle is what turns "the targets match" into evidence about the
  language, and the two checks fail on disjoint defect classes.
