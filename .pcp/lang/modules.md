# Lang / Modules

This file groups d/c/r/l entries for the lang/modules module.

### [r-43ea] Modularity is a first-class language goal, not a later feature
- **Date**: 2026-08-20
- **Status**: Active
- **Cluster**: lang/modules
- **Description**: Reuse across generations is a primary product goal. A language with a single
  flat namespace cannot deliver it: nothing generated in one pass can be referenced by the next
  without re-emitting it. Core v0.1 deliberately excluded a module system as "minimal scope",
  which silently contradicts that goal.
- **Requirement**: A unit of source is a module by default. Names are addressable across units,
  visibility is explicit rather than positional, and composing two independently produced units
  must not require editing either.
- **Scenario**: An agent emits a self-contained unit in one pass; a later pass composes it into a
  larger program having read only its exported surface, not its body.
- **Why Non-Obvious**: Cutting modules reads as harmless scope reduction because every benchmark
  task fits in one file. The cost only appears at the metric that actually matters — how much
  usable work survives a single pass — where it caps reuse at zero.
