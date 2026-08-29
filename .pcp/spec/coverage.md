# Spec / Coverage

This file groups d/c/r/l entries for the spec/coverage module.

### [l-3434] Most of the vocabulary has never appeared in an example
- **Update 2026-08-29 (Phase 2, closing)**: closed at **107/107 builtins executed**, under a
  metric that changed to make the number mean something (d-7c21, d-31f0). Ten fixtures
  (`corpus/valid/19`-`28`) and 88 differential cases execute the 74 builtins that had never run.
  Recorded as *not* proven: execution is traced on the Python side only, the host errno mappings
  for `already-exists`/`invalid-path`/`interrupted`/`other` are unreachable from a deterministic
  case, and the eight builtins under `coverage.lock`'s `unproven` have no `defenum`-typed
  instantiation until Phase 1's derives land.
- **Update 2026-08-29**: no longer only a generation-quality concern. The first two never-exercised
  builtins to be compiled both had broken lowerings for the systems target — one invoked a closure
  literal inline, which defeats the target compiler's own inference, and one passed its arguments in
  the wrong order. An unexercised builtin is not merely undemonstrated; it is unverified, and the
  gates cannot see it because nothing calls it.
- **Date**: 2026-08-20
- **Status**: Resolved
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

### [d-7c21] Vocabulary coverage counts evaluation, not mention, and the figure is data
- **Date**: 2026-08-29
- **Status**: Active
- **Update 2026-08-30 (Phase 2 fix wave)**: the gate's own conditions were hardened after the
  review demonstrated each could be faked. An `unexecuted` fixture's reason must now name a PCP id,
  so a bare "not executed" is no longer a pass; `exec_coverage.py --write` refuses to record a lower
  executed count without `--allow-regression`; an `unproven` entry expires when its builtin acquires
  a user-defined-type instantiation; and the `N`-domain rule is exact per `N`-position rather than a
  substring test. The five conditions grew guards rather than new conditions.
- **Cluster**: spec/coverage
- **Description**: A builtin is covered when its lowering was *evaluated* while the gate suite ran
  a program, in a case whose result is checked against a value in the repository. Being named in
  the corpus or in the specification's markdown does not count, nor does sitting in a branch no
  case takes. The floor (95%), the ratchet on the exact count, the per-builtin executed
  instantiations and the Tier-A probe set are checked in as `prelude/coverage.lock`, and the gate
  fails on five separate conditions: below the floor, below the lock, above the lock, a
  `corpus/valid` fixture no program runs, and a Tier-A block that disagrees with the sweep.
- **Rationale**: The previous metric counted a call head found by a static scan. On the same tree
  it read 38 of 107 while the executed set was 33, and only 21 builtins were in both — wrong in
  both directions. Seventeen counted builtins had never run, `/` and `mod` among them, which is
  exactly how they sat inside the "exercised" set while being broken over two thirds of their
  declared numeric domain.
- **Costs accepted**: the lock has to be updated deliberately, in the commit that earns it; an
  unchanged lock beside a raised count is a failure rather than a silent improvement. That is what
  stops the number drifting.
- **Why Non-Obvious**: raising the floor and widening the scan root both read as strengthening the
  gate, and neither touches what actually ran. Under the executed metric a markdown edit and a
  wider scan root have no effect at all, rather than being merely discouraged.

### [d-31f0] The coverage numerator is traced by wrapping the lowering templates, not by a scan
- **Date**: 2026-08-29
- **Status**: Active
- **Cluster**: spec/coverage
- **Description**: `backend/exec_coverage.py` rewrites every entry of `to_python.LOWER`, in its own
  process only, as `(_rec.hit('<name>') or (<template>))`. `hit` returns `None`, so `or` always
  yields the original expression and the format placeholders are untouched because the rewrite
  happens on the template before `.format`. The recorder therefore fires exactly when the emitted
  expression is evaluated. Call sites are recorded the same way, keyed by (source, line, column),
  and intersected with the checker's per-site instantiations, which is what makes "executed at
  `Int64` and at `Float64`" a checkable claim rather than a hand-written field.
- **Rationale**: The design this replaced counted a static parse of the executed sources. It was
  demonstrated fakeable rather than argued about: a ten-line fixture whose single case takes the
  `else` arm past sixty builtin calls moved the reported figure from 21 to 32 with none of the
  eleven builtins executed. The same fixture now moves nothing, and the gate names it as executed
  by no program.
- **Costs accepted**: the monkeypatch is one-way, so anything that traces must own its process —
  the unit tests spawn subprocesses for exactly this reason. Execution is recorded on the Python
  side only; the Rust side is compile-gated by `monomorphism.py` and compared by `differential.py`.
- **Why Non-Obvious**: a tree-sitter scan over precisely the sources that run reads as an execution
  measurement. It is a measurement of the text of the programs that run, which is a different thing.

### [c-1f7d] The generated call forms had a second arity source, wrong for 34 of 107 builtins
- **Date**: 2026-08-29
- **Status**: Active
- **Cluster**: spec/coverage
- **Description**: `prelude/generate.py` counted whitespace-separated words on the left of `->` to
  decide how many arguments to render in a call form, in two places. A parenthesised type counts as
  several words, so `(map-get a b c d)` was shipped for a two-argument builtin — in
  `AGENT_SPEC_CORE.md` §6 and in `HANDBOOK.md`, the artifact injected into the prompt. Both copies
  now call `vocab.parse_signature`, which is the same reader the checker uses.
- **Why Non-Obvious**: the heuristic is right for every builtin whose arguments are all primitive,
  which is most of the examples anyone looks at, and the generator check compares generated output
  against itself rather than against the signature.

### [d-9c4e] The differential harness is data-driven, and its input types come from the entry
- **Date**: 2026-08-29
- **Status**: Active
- **Cluster**: spec/coverage
- **Description**: `backend/differential.py` was one hardcoded task with a single `String` input and
  a map-only serializer. It now discovers tasks from `backend/cases/*.json` and `bench/tasks/*.json`,
  takes multi-argument typed inputs, encodes returns through a recursive `J` trait in
  `backend/rust/harness.rs`, normalises the Python side so `Option`/`Result`/`Pair`/non-finite
  floats encode identically, and lets a program-mode case declare its files with modes, its stdin,
  its expected stdout and its expected exit status. Argument and return types are read from the
  entry's own declaration in the source, never from a field beside the cases.
- **Rationale**: a restated signature is a second source, and a second source is free to drift from
  the one the backends compile. Fixture case files live in `backend/cases/`, not `bench/tasks/`,
  because `bench/harness/run.py` globs the latter and would take them for measurement tasks.
- **Why Non-Obvious**: the return shape looks like the hard part, so a flat per-shape enum looks
  sufficient. The shapes compose — `(Option (List T))`, `(List (Pair K V))`,
  `(Result (Option Int64) IoError)` are all reachable from the vocabulary — and no flat tag spells
  any of them.
