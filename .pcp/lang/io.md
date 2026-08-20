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
