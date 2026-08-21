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

### [d-f99b] Module surface is private by default and machine-readable
- **Date**: 2026-08-20
- **Status**: Active
- **Cluster**: lang/modules
- **Description**: Every source file is a module whether or not it declares a header; the header
  only names the module and opens part of it. Visibility is private by default, so the exported
  list is a deliberate, stable contract rather than an accident of what happened to be top-level.
- **Rationale**: The unit of one agent pass is a working module, so the property to optimise is
  whether a later pass can build on an earlier one without reading its body. An explicit export
  list is exactly that surface, and being declarative it can be extracted mechanically rather than
  inferred. Public-by-default was rejected: it makes every internal helper part of the contract,
  which is the opposite of reusable.
- **Why Non-Obvious**: Private-by-default reads as friction when writing the first module, because
  every reuse costs an explicit export. The benefit only appears at the second module, and the
  cost of the alternative only appears once something internal has been depended upon and can no
  longer be changed.


### [d-5c12] Whole-program compilation, and mangling through the module path
- **Date**: 2026-08-21
- **Status**: Active
- **Cluster**: lang/modules
- **Description**: Imports now resolve. An entry module pulls its imports in transitively and each
  backend emits one output file containing every module, dependencies first. Modules are indexed by
  their declared `module` header rather than by filename, and a top-level name from an imported
  module is qualified by that module's path.
- **Rationale for whole-program**: separate compilation would need a module system per target in
  each of four backends and buys nothing at this size, where a program is a handful of modules
  built together. Indexing the header rather than the filename also detects two files declaring one
  module, which a filename convention cannot.
- **Rationale for mangling through the path, not the alias**: an alias is module-local. Two modules
  may each bind `s` to a different module, and mangling the alias gave both of their members the
  same target name with no error — `grammar/corpus/valid/09-aliases.as` is that case, and it now
  compiles because the module path is unique by construction.
- **What it uncovered**: `06-module.as` had been skipped by every backend since it was written.
  Un-skipping it found four defects in the Rust backend alone, none reachable by any other fixture:
  type parameters dropped from every declaration, a user type application losing its arguments, a
  recursive enum emitted without indirection, and — the subtle one — a user schema named `Box`
  shadowing `std::boxed::Box` so the indirection that was added silently was not one.
- **Costs accepted**: no separate compilation, so a large program is rebuilt whole. Imported *types*
  are still unnameable, because the type grammar has no qualified form; cross-module composition is
  over functions until that is added.
- **Why Non-Obvious**: a skipped fixture reads as a known limitation with a known cost. This one was
  hiding four unrelated defects in a backend everything else exercised, because it was the only
  fixture with a generic declaration — the skip was load-bearing in a way its comment did not say.
