# Lang / Host

This file groups d/c/r/l entries for the lang/host module.

### [d-2030] The compiler is hosted in Rust, not Go
- **Date**: 2026-08-20
- **Status**: Active
- **Cluster**: lang/host
- **Description**: One host language was to be chosen for the compiler, with self-hosting as the
  eventual goal. Rust is chosen.
- **Rationale**: The language's defining constructs are closed unions, exhaustive matching, and
  option/result types. The chosen host has all three natively, with exhaustiveness checked by its
  own compiler, so those constructs survive translation intact. The alternative has none of them:
  a closed union must be encoded through an interface and a runtime type switch, and no
  exhaustiveness check exists — meaning the safety property this language is built on would be
  silently discarded at exactly the layer meant to preserve it. A compiler is the most
  union-saturated program there is, so the mismatch would be paid on every AST and IR node.
- **Counter-argument weighed**: the chosen host requires an ownership decision that remains
  unrecorded, which the alternative would not have. That is a decision to be made and can be made
  conservatively at first. The alternative's missing unions are not a decision — they are a
  permanent impedance mismatch with no conservative fallback.
- **Why Non-Obvious**: The alternative looks cheaper on every surface metric: simpler language,
  faster builds, no ownership question, easier hiring. The cost is invisible until the first
  recursive variant type is written, which for a compiler is immediately.

### [l-e33e] The entry point's signature is fixed by both host runtimes and by nothing in the language
- **Date**: 2026-08-29
- **Status**: Deferred
- **Cluster**: lang/host
- **Description**: A program's entry point is required by both host runtimes to take the argument
  vector and return a result whose failure is the I/O error union. Neither the specification's
  conformance checklist nor the checker says so, so the constraint exists only in the two runtimes
  that consume it.
- **Rationale for deferring**: the constraint is real and both targets already enforce it, so
  nothing is currently wrong; what is missing is the declaration that makes them agree by
  construction rather than by coincidence. Writing it down means deciding whether the entry point is
  an ordinary exported function that happens to be named specially, or a distinct declaration form
  — and that is the same question a foreign-call boundary asks (d-4b8c), so settling it here in
  isolation would pre-empt an answer owed elsewhere.
- **Why Non-Obvious**: the two hosts enforce it at *different times*. One rejects the wrong
  signature when the target is compiled; the other cannot, and now carries an explicit runtime check
  that raises instead. The behaviours therefore diverge on exactly the programs the language never
  defined — the systems target refuses to build, the scripting target builds and fails when run —
  and a language that leaves a rule to its backends gets one such divergence per backend. The
  divergence is invisible while every program written has the right shape, which is every program
  written so far.

### [d-446d] Structured Process Automation: Typed Vector Commands over Unsafe Shell Interpolation
- **Date**: 2026-09-02
- **Status**: Final
- **Cluster**: lang/host
- **Description**: Autonomous administrative scripting in AgentScript replaces brittle Bash/sh string interpolation and Python subprocess boilerplate with typed vector commands and structured process pipelines (`packages/asl-sh`). Command arguments are represented as explicit vectors (`(ProcessCmd :bin "git" :args ["status" "-s"])`), preventing shell injection vulnerabilities by design. Multi-stage pipelines stream stdout between process stages without spawning intermediate `/bin/sh` eval subshells, and outputs (exit-code, stdout, stderr, stdlog) are captured in strongly typed `(Result ProcessOutput ProcessError)` structures with timeout and path jailing enforcement.
