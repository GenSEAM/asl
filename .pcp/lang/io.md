# Lang / Io

This file groups d/c/r/l entries for the lang/io module.

### [r-56bf] An I/O surface is now on the critical path
- **Date**: 2026-08-20
- **Status**: Active
- **Cluster**: lang/io
- **Description**: Core excludes I/O by deliberate design, which was defensible while the
  benchmark consisted of pure functions. The chosen benchmark is now whole working programs that
  read input and write output, so the exclusion has moved from a clean scope boundary to a hard
  blocker: no measurement arm can run without it.
- **Requirement**: A minimal I/O surface sufficient to read input, write output, and read and write
  files, carrying the same totality discipline as the rest of the language — failures surface as
  values, never as traps.
- **Why Non-Obvious**: Excluding I/O looked free because it removed the effect-ordering and
  concurrency questions along with it. Reintroducing it brings a decision that was previously
  deferred: whether effects are tracked in the type system or left implicit. Choosing the implicit
  route is cheap now and expensive later, because it is the choice that forces function colouring
  once any concurrent construct is added.
- **Scenario**: A benchmark task requires reading a file, transforming its contents, and writing a
  result; the generated module must express all three without an escape hatch to the host language.

### [d-31c7] Effects are declared and checked, not inferred and not coloured by return type
- **Date**: 2026-08-21
- **Status**: Active — **vocabulary split 2026-08-21, see `d-8e60`**
- **Cluster**: lang/io
- **Description**: The I/O surface landed in v0.3, which forced the decision `r-56bf` said could
  not stay deferred. A `defun` or `defentry` that reaches an effectful builtin carries
  `:effects [io]`, and a declaration without it may not call one, directly or transitively.
  Purity stays the default and stays verifiable.
- **Rationale**: The alternative was to leave effects implicit, which is cheaper today and is
  exactly the choice that forces function colouring later: once a concurrent construct exists,
  every signature has to be re-typed to say what it may do. An annotation is a mild colouring paid
  at one line per effectful function, and it makes adding a second effect additive rather than
  breaking. Inference was rejected for a different reason — an inferred effect is invisible in the
  surface a later pass reads, and the module header being readable without the body is the property
  the whole design optimises for.
- **Costs accepted**: one line per effectful function, and a rule no grammar can enforce, so the
  checker's backlog grows by one before the checker exists.
- **Why Non-Obvious**: the annotation looks like ceremony while the language has one effect, so the
  temptation is to add it when a second arrives. That is the moment it becomes a breaking change to
  every signature already written, which is precisely when it cannot be afforded.

### [d-9b41] I/O failure is the host's message, not a structured union
- **Date**: 2026-08-21
- **Status**: Active
- **Cluster**: lang/io
- **Description**: Every effectful operation returns `(Result T String)`. A closed `IoError` union
  with cases for not-found, permission and the rest was designed and then rejected for now.
- **Rationale**: Three backends have to agree for the differential gate to pass, and their error
  taxonomies do not: the same missing file yields three different messages and would have to be
  classified into identical cases by three separate runtimes. A union whose cases were mapped
  differently per host would report a runtime disagreement as a language feature. A host message is
  honest about what is actually known at the boundary, and it makes the foreign boundary and the
  I/O surface share one failure representation instead of two.
- **Costs accepted**: a caller can report a failure but cannot dispatch on its kind. When that
  becomes load-bearing the union is added and the message becomes one of its cases, which is
  additive.
- **Why Non-Obvious**: the union is the obviously better-typed design, and it is what a
  totality-first language looks like it should have. The cost is invisible until three runtimes
  have to agree on which case a given host error belongs to — and the gate that would catch the
  disagreement is the one that makes portability mean anything.


### [d-8e60] The effect vocabulary is split by capability, because a browser has almost none
- **Date**: 2026-08-21
- **Status**: Active — supersedes the single `io` effect in `d-31c7`
- **Cluster**: lang/io
- **Description**: `:effects [io]` became `console` / `stdin` / `fs` / `env` / `proc`, and each
  build target declares which it provides. A target that cannot provide a declared effect refuses
  the module, naming the declaration — the same shape as §11's `:target` refusal for foreign
  declarations, applied to capabilities rather than ecosystems.
- **What forced it**: WebAssembly. `.as` reaches a browser through the Rust backend and
  `wasm32-unknown-unknown`, and that needed no new code generator — a pure module compiled on the
  first attempt. The problem was the opposite of the expected one: a module using `file-read`,
  `process-run` and `env-get` **also compiled**, to a byte-identical size, because `rustc` links
  `std::fs` for a target with no filesystem. It would have shipped and failed at run time. A
  language whose central claim is totality cannot let a target silently promise a capability it
  does not have.
- **Why now rather than when a browser build is actually wanted**: splitting later is a breaking
  change to every signature already written, and the whole point of the language is that agents
  write many modules. Splitting now cost one line of vocabulary, tags on eleven builtins, and a
  mechanical migration of four files — which the checker itself specified, since it already
  computed the reached set per function for rule 12.
- **Costs accepted**: five names to learn instead of one, and a declaration that is longer at each
  effectful function. In exchange the declaration says something a reader could not otherwise know
  without following the call graph.
- **Why Non-Obvious**: one `io` reads as the simple, orthodox choice, and the cost of it is
  invisible while every target is a native host with a filesystem. It becomes visible the first
  time a target has a *subset* of the capabilities, at which point the coarse name is not merely
  imprecise — it is wrong, and it is wrong in the direction of claiming safety that is absent.
