# Lang / Io

This file groups d/c/r/l entries for the lang/io module.

### [r-56bf] An I/O surface is now on the critical path
- **Date**: 2026-08-20
- **Status**: Resolved
- **Update 2026-08-29**: built, with the deferred decision taken rather than dodged (d-4533).
  Failures are a closed union rather than host strings, so the two runtimes' independently derived
  error mappings are comparable — and the differential gate now runs whole programs and compares
  exit status as well as output, including a failing path, because the mapping is the part most
  likely to disagree. What the language still cannot do is not I/O: it is that the measurement
  harness still drives a pure entry function.
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

### [d-4533] Effects are tracked, by a marker on the signature rather than in the type
- **Date**: 2026-08-29
- **Status**: Active
- **Cluster**: lang/io
- **Description**: A declaration that touches the world carries a one-token marker. It is inferred
  inside a body — nothing has to be threaded through expressions — but mandatory on the
  declaration, because the declaration is the surface a caller reads without the body. A lambda
  carries its own marker, and handing a marked lambda to a function makes that call effectful.
- **Rationale**: The alternative that costs nothing today is leaving effects implicit, and that is
  precisely the choice that forces function colouring the moment any concurrent construct is added:
  every existing signature would then have to be revisited, by which time there are programs
  written against them. The marker costs one token per effectful declaration and one rule for a
  generating agent, and it buys the property the module system is for — a caller sees that a module
  touches the world from its header. A monadic encoding was rejected as the opposite trade: maximum
  precision at a per-program token cost, in a language whose reason to exist is what fits in one
  pass.
- **Costs accepted**: the rule over-approximates. A marked lambda that is passed somewhere and never
  applied still colours the call that received it. Removing that imprecision means carrying effects
  inside function types, which is the machinery being avoided; the approximation is the seam where a
  real effect system would later go.
- **Why Non-Obvious**: effect tracking reads as a purity feature, and purity reads as a thing a
  pragmatic language trades away. What is actually being bought is the *option* on concurrency:
  ordering was never the problem — evaluation order is already specified — and the cost of the
  decision is paid entirely in the future, by whoever adds the first concurrent construct.
