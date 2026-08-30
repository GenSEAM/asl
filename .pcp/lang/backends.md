# Lang / Backends

This file groups d/c/r/l entries for the lang/backends module.

### [l-880d] Native backends are gated behind the checker and the ownership question
- **Date**: 2026-08-20
- **Status**: Partly resolved
- **Cluster**: lang/backends
- **Update 2026-08-21**: a systems-target backend now exists and its output is accepted by the
  target compiler, built on the conservative ownership strategy below rather than on a resolved
  model. What remains open is the cost of that strategy, which is now measurable rather than
  hypothetical: values are cloned at every use site.
- **Description**: Native code generation for the priority targets was postponed. Two prerequisites
  are unmet: there is no semantic checker to guarantee the input is well-formed, and no decision
  has been recorded on how values are owned and shared, without which the systems-language backend
  has to guess at every signature.
- **Rationale**: Self-hosting the compiler into native targets was chosen deliberately, and that
  choice rules out the cheaper alternative of a single shared runtime with thin bindings. The cost
  of that choice is that ownership, identifier mangling, numeric widths and concurrency must each
  be genuinely resolved rather than avoided.
- **Why Non-Obvious**: A tree-walking reference implementation is enough to measure generation
  quality, so it is tempting to treat backends as the next milestone. They are the expensive
  milestone, and everything they depend on is still open.

### [c-15f3] The corpus exercises forms, not combinations of them, and that is where the defects were
- **Date**: 2026-08-29
- **Status**: Active
- **Cluster**: lang/backends
- **Description**: Every form in the language appears in some fixture, and the gates are green on
  all of them. Two wrong-code defects nevertheless survived until a program combined forms that had
  only ever appeared apart: a constructor pattern *inside* another pattern was lowered as a binder,
  so it matched every value of the outer case; and a list match *inside* another list match
  overwrote shared backend state, dropping the outer arm's binding. Both produced output the target
  compiler accepted.
- **Impact**: coverage measured per form reads as complete while the combinatorial surface is
  untested, and the failure mode is silent — wrong answers, not crashes, on paths a happy-path
  fixture never takes. The differential gate is the only instrument that would have caught either,
  and until this milestone it ran exactly one program.
- **Why Non-Obvious**: the closure gate answers "is every name defined" and the corpus answers "is
  every form lowered", so between them they look like coverage. Neither asks whether a form still
  behaves when it is nested inside another, which is what real programs do constantly.

### [d-84a9] Backends link the transitive import closure into one output unit
- **Date**: 2026-08-29
- **Status**: Active
- **Cluster**: lang/backends
- **Description**: A program and every module it imports, transitively, are lowered into a single
  target artifact, with each imported module's names prefixed by the module path that defines them
  — never by the alias reaching them. Emission stays dependencies-first.
- **Rationale**: Every gate in the tree builds exactly one target artifact from exactly one source
  path. Emitting one target module per source module would require a build driver, a package
  layout and a link step on each target before a single fixture could be gated, which is a large
  cost paid before anything is observable. Whole-closure linking reuses the module resolution the
  checker already performs and keeps every gate driving one artifact.
- **Why Non-Obvious**: What it costs is separate compilation and per-module target packaging, and
  that cost is not visible while every program is small. It is worth revisiting when a target has
  its own module system to honour rather than merely a namespace to borrow.

### [c-055e] The Rust lowering dropped every type-parameter binder, had no indirection for a recursive case, and derived comparison traits by declaration kind rather than by content
- **Date**: 2026-08-29
- **Status**: Active
- **Cluster**: lang/backends
- **Description**: A generic declaration of any kind lost its binders in the Rust output, a
  self-referential union was emitted without indirection, and records derived equality and ordering
  unconditionally while unions derived neither. One corpus fixture produced thirteen compiler
  errors.
- **Why Non-Obvious**: It was invisible because that one fixture sat on the backend gate's skip
  list, and a skip-list entry reads as a known gap rather than as an untested defect — nobody
  re-derives what a skip is actually hiding. Two follow-on facts only appear once the binders are
  emitted: the ownership strategy clones at every use site, so a bare type parameter needs a
  cloning bound or the code stops compiling; and the comparison derives have to be conditional on
  content, because the floating-point type implements neither of them and the derive fails at the
  declaration rather than at a use. The same missing derives independently blocked eight builtins
  found from the vocabulary side — one defect with two discoverers.

### [c-4c51] A body's non-final expressions were evaluated for their value and then discarded, so an effect lowered as a pure expression vanished
- **Date**: 2026-08-29
- **Status**: Active
- **Update (2026-08-29, after review)**: the description below blames one backend. Both had it, in
  the same shape, and both were fixed by the same shared helper — checked against the head commit,
  not taken from a report. That matters for the lesson rather than for the credit: a defect present
  in both emitters is one the differential gate cannot see, which is why d-c15c exists.
- **Cluster**: lang/backends
- **Description**: Where a body holds several expressions, only the last one's value is the body's
  value; the earlier ones are there for their effect. The Rust lowering computed each of them and
  then threw the result away without emitting it, so any earlier expression that lowered to a pure
  expression rather than to statements disappeared from the output entirely.
- **Why Non-Obvious**: It hid behind the shapes that happen to lower to statements — most do, and
  the ones that do not are exactly the effectful forms whose absence is silent. The output still
  compiled and still exited zero; the only symptom was a missing line of program output. The
  differential gate caught it on the first program that put a propagating call in a non-final
  position, which is the second defect that gate has found in how one form nests inside another,
  and neither would have been visible to a gate that only compiles.

### [d-9dd9] The emitters carry a real lexical scope, rather than a special case for the shadowing that exposed its absence
- **Date**: 2026-08-29
- **Status**: Active
- **Cluster**: lang/backends
- **Description**: Each emitter maintains a stack of the names bound at the point it is emitting,
  pushed and popped by every binding form, and a name resolves against that stack before it
  resolves against anything module-level. The defect that exposed the gap — a binder inside an
  imported unit sharing a name with one of that unit's own definitions, which was emitted as the
  definition — is a consequence of the missing scope, not a case to be handled.
- **Rationale**: Lowering is a translation between two scoping disciplines, so an emitter without a
  scope is not incomplete, it is unsound; the symptom is a function of which names happen to
  collide, and every future collision shape is a separate special case. The stronger reason to pay
  for the general fix here is what the failure looked like: it was silently wrong on *both*
  backends and wrong the same way, so the differential gate compared two wrong answers and found
  agreement. A gate built on cross-backend agreement cannot be the thing that tells us a scoping
  rule is right, because both emitters share the assumption that is wrong.
- **Why Non-Obvious**: the root-unit case was correct throughout, which is the case every existing
  fixture exercised, so the defect reads as impossible from the passing evidence. Shadowing is also
  the archetypal "rare in practice" shape, and treating it as rare is what makes an emitter without
  a scope survive to the point where the wrong output is trusted.

### [c-6b02] "Exercised" meant "the lowering works at the one type someone happened to use"
- **Date**: 2026-08-29
- **Status**: Active
- **Cluster**: lang/backends
- **Description**: Ten builtins were broken over part of their declared type at head `a635ab4`, with
  every gate green: `/`, `mod`, `checked-div`, `checked-mod`, `list-sum`, `min`, `max`, `list-sort`,
  `list-min`, `list-max`. The first five lowered to runtime helpers taking `i64` while declaring
  `N N -> N` or `(List N) -> N`; `min`/`max` lowered to `std::cmp::min`/`max`, which do not compile
  on `f64` at all; the last three were bounded by `Ord`, which `f64` does not implement. A
  mechanical sweep of all 440 admissible (builtin × instantiation) probes found **39 failures over
  16 builtins**, none of which the checker rejected. Two of them, `/` and `mod`, were inside the set
  the coverage figure called exercised, and neither had ever been executed at any type.
- **Why Non-Obvious**: coverage was counted per builtin, so one instantiation retired the whole
  signature. The generic declaration is in `prelude.json` and the monomorphic implementation is in
  `rt.rs`, and nothing compared the two until a probe was generated from the declaration and
  compiled.

### [d-a70b] Every admissible instantiation compiles, and the sweep's own size is recorded
- **Date**: 2026-08-29
- **Status**: Active
- **Update 2026-08-30 (Phase 2 fix wave)**: `tier_a.narrowed` is recorded as the sorted list of
  probe labels, not a bare count, so swapping one narrowed probe for another keeps the count and is
  now visible. The `Int32` limit is written into `coverage.lock`'s `note` rather than implied: Tier A
  compiles `Int32` on both backends, but nothing executes it because the Python backend has no
  `Int32` representation — the 400/400 figure means "compiles", not "ran".
- **Cluster**: lang/backends
- **Description**: `backend/monomorphism.py` generates the admissible instantiation set from
  `prelude.json` via `parse_signature`, emits every probe into one source, checks it in one pass and
  compiles it with one `rustc` and one `py_compile`. Admissibility is asked of the checker rather
  than restated: a probe the checker rejects is a narrowed signature, not a lowering bug, and the
  count of those is pinned too. Effectful, variadic and higher-order builtins are excluded, each
  recorded by name and reason in `prelude/coverage.lock` alongside the probe count and the type
  domains, and the gate fails on a shrunken sweep as loudly as on a failing probe.
- **Rationale**: the alternative is a per-builtin eyeball, which is what let `filter` and
  `list-sort-by` ship with lowerings that did not compile. Recording the sweep's own size is what
  stops the failure count being reduced by removing probes: dropping `Float64` from the numeric
  domain removes the failing instantiations *and* the failures.
- **Costs accepted**: 400 probes, ~5.5 s per gate run. Exclusions are a real gap — the sweep proves
  that every instantiation *compiles*, never that it *computes*, and it cannot reach a higher-order,
  variadic or effectful builtin at all.

### [d-e5a1] min and max follow Python's rule for NaN and for ties; the JS templates are known-wrong and unchanged
- **Date**: 2026-08-29
- **Status**: Active
- **Cluster**: lang/backends
- **Description**: `rt::min(a, b)` returns `a` unless `b < a`, and `rt::max` returns `a` unless
  `b > a`. So a NaN in the first operand propagates and a NaN in the second does not, and a tie
  returns the first argument — measured identical to Python's `min`/`max` in both operand positions,
  and pinned by `23-numeric.agentscript`'s `minmax` entry. `list-min`/`list-max` use the same reduce
  rather than `iter().min()`, whose tie and NaN behaviour differ. `prelude.json`'s `js` templates
  are `Math.min`/`Math.max`, which propagate NaN from either position and are therefore wrong under
  this rule; they are **not** changed, because there is no JS runtime and no gate could check the
  change. Phase 4 owns them.
- **Why Non-Obvious**: the obvious repair — an inline `if {0} <= {1} { {0} } else { {1} }` — is
  wrong twice over: it puts its first argument in the output twice, so a pure expression is
  evaluated twice, and it inverts the NaN result in both operand positions.

### [c-3ef8] list-sort over Float64 with a NaN present is unspecified
- **Date**: 2026-08-29
- **Status**: Superseded
- **Update 2026-08-30 (Phase 2 fix wave)**: resolved — the ordering builtins now carry a total
  order in which a NaN-holding value sorts after every value that does not and ties with other
  NaN-holding values (d-6e1f), implemented on both backends and pinned by `backend/cases`. The
  "unspecified" position is withdrawn; this entry is kept for the observation that made it worth
  writing: compiling at a type was never the same as specifying a meaning at that type.
- **Cluster**: lang/backends
- **Description**: `rt::sort` compared with `partial_cmp` and treated an incomparable pair as equal.
  That was a defensible choice and not a total order, so the result depended on the input's
  arrangement. Python's `sorted` was no better — `sorted([3.0, nan, 1.0])` is `[3.0, nan, 1.0]` — so
  no fixture asserted it and neither backend could be called wrong.
- **Why Non-Obvious**: `list-sort` was gated at `Float64` by the Tier-A sweep, which made it look
  settled. Compiling at a type is not the same as having a specified meaning at that type.

### [d-6e1f] Ordering over Float64 is a total order: NaN sorts last and ties in input order
- **Date**: 2026-08-30
- **Status**: Active
- **Cluster**: lang/backends
- **Description**: `list-sort`, `list-min`, `list-max`, `min` and `max` share one order. A value
  holding a NaN sorts after every value that does not, and two NaN-holding values tie, so a stable
  sort leaves them in input order. `rt.rs` implements it as `nan_last`, which tests "holds a NaN"
  (`partial_cmp(x, x).is_none()`) *before* comparing, so the order is transitive — the naive
  fallback, asking `partial_cmp` first, sorts two values that tie with each other onto opposite
  sides of a third and Rust's sort panics. `runtime.py` mirrors it with an `order_key` that collapses
  every NaN-holding value to one key. Selection uses the same order, so `min` is the head of
  `list-sort`, not a separate rule.
- **Rationale**: the language's reason to exist is byte-reproducible output, and a program sorting a
  `(List Float64)` that reaches `nan` is one the language admits; declaring it unspecified made that
  gap invisible rather than portable (supersedes c-3ef8). `min`/`max` already followed Python's rule
  (d-e5a1); this extends the same order to the list selection and sort builtins.
- **Why Non-Obvious**: `partial_cmp(..).unwrap_or(Equal)` reads as the obvious fix and is what the
  first repair used; it freezes NaN in place under a stable sort, disagrees with Python, and is not
  a total order.

### [d-8b3c] Numeric edges are fixed: / and mod trap at MIN / -1, checked-* return none, and float64-to-int64 returns none out of range
- **Date**: 2026-08-30
- **Status**: Active
- **Cluster**: lang/backends
- **Description**: `MIN / -1` is the one quotient with no representable two's-complement answer.
  `/` and `mod` trap there on both backends (Rust's `Num::quot` returns `None` and `div` panics;
  Python raises `Trap`), while `checked-div` and `checked-mod` return `none`, because totality is
  the purpose of the checked forms. `float64-to-int64` returns `none` when `x` is NaN, an infinity,
  or outside `[-2^63, 2^63)`, on both backends — the range is decided before the cast, so Rust's
  saturating `as i64` never answers `i64::MAX` for `1e30` and Python's unbounded int never answers a
  value outside `Int64`.
- **Rationale**: the declared contract was silent on overflow, which is exactly why the two
  implementations drifted — Python returned `9223372036854775808`, outside `Int64`, where Rust
  panicked. "Trap, or none for the checked form" is the only contract both hosts can honour without
  widening a fixed-width type. Pinned by `backend/cases/23-numeric-edge.json` and
  `23-numeric-from-float.json`.
- **Why Non-Obvious**: a widening host (Python) and a trapping host (Rust) make the *correct* answer
  depend on which target runs the program; agreeing on the wrong answer here was masked because the
  boundary cases were absent, so the differential gate stayed green over a case that crashed one
  backend.

### [c-0d5b] Four cross-backend divergences were only reachable once the never-executed builtins ran
- **Date**: 2026-08-29
- **Status**: Active
- **Cluster**: lang/backends
- **Description**: Making the vocabulary execute found four defects the repair list did not name,
  each invisible while the builtin was unexercised. (1) `mod` at `Float64`: the Python runtime
  computed `a - div(a, b) * b`, which is exact and therefore zero for floats, against Rust's `%`.
  (2) `string-from-float64` at NaN and in exponent notation: Rust's `{:?}` gives `NaN`, `1e16` and
  `1e-5` where Python's `repr` gives `nan`, `1e+16` and `1e-05`. (3) `list-sum` of an empty
  `(List Float64)`: Python's `sum([])` is the integer `0`, so the declared `Float64` rendered as
  `"0"`. (4) `zip`'s Python template named `_agentscript.zip`, which does not exist — the runtime calls it
  `zip_` to avoid shadowing the builtin, so every Python program calling `zip` raised `NameError`.
- **Why Non-Obvious**: each is in a builtin the coverage figure was happy to call covered, and three
  of the four are in the *rendering* of a value rather than in its computation, which is the part a
  reader assumes the standard library got right.

### [c-8f6c] Destructuring a bare binding moves out of it, and the emitter's own ownership rule did not cover match
- **Date**: 2026-08-29
- **Status**: Active
- **Cluster**: lang/backends
- **Description**: The Rust emitter's stated strategy is to clone at each use site where a binding is
  read more than once, and it was implemented for call arguments only. A `match` on a bare name moved
  out of it, so a `let`-bound `Result` that is matched and then passed to `result-map` failed to
  compile — a program the Python backend accepts. The scrutinee is now cloned under the same rule.
- **Why Non-Obvious**: the corpus scrutinised fresh expressions almost everywhere, so the moving case
  needs a binding that is read again *after* the match, which no fixture had. The failure is a
  compile error rather than a wrong answer, so it looks like a language restriction rather than a
  backend gap.
