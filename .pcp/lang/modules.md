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

### [r-ea8c] A module must be able to export a type, and an importer to name it
- **Date**: 2026-08-29
- **Status**: Resolved
- **Cluster**: lang/modules
- **Description**: The export list admits only value names, and no qualified form exists in type
  position, so a record or union declared in one module is permanently private to it. A module can
  export a function but not the type appearing in that function's signature.
- **Requirement**: Types are exportable and referenceable across a module boundary, on the same
  contract the export list already provides for values.
- **Scenario**: a module declares a domain union and a function returning it, exports the function,
  and no other module can write the type of what it receives — so the value can be obtained but not
  stored, passed on, or matched in a helper.
- **Why Non-Obvious**: both grammars agree on this, so no drift gate can see it, and every example
  written so far exports functions over built-in types only, where the hole never shows. It cuts
  directly against the module system being the property the whole design is for (r-43ea, d-f99b):
  composition by reading a contract does not work if half the contract is inexpressible.
- **Update (2026-08-29)**: Resolved by d-5837, d-c912, d-d06b and d-b47d together — the export list
  admits type names, an alias-qualified type is a single lexeme in both grammars, the checker
  resolves types across the boundary under nominal identity, and an exported signature may only
  name public types. That last one is what closes the requirement rather than half of it: without
  it the scenario above is still reachable in a program that checks clean. Deliberately not closed:
  opaque export (d-d06b), separate compilation (d-84a9), and a cycle detector keyed on a module's
  declared name rather than on its path.
- **Update (2026-08-29, after review)**: the arity of a call reached through an alias was recorded
  above as a fourth open hole. It is no longer one — the review passes closed it and it carries a
  fixture. The remaining three stand.

### [d-5837] Types cross a module boundary on the existing export list, alias-qualified
- **Date**: 2026-08-29
- **Status**: Active
- **Cluster**: lang/modules
- **Description**: A module publishes a record or a union by naming it on the same `:export` vector
  that already publishes functions, and an importer reaches it through the same alias-qualified
  form that already reaches values. No second vector, no second namespace mechanism, no new
  punctuation.
- **Rationale**: d-f99b makes the export list *the* contract, singular and machine-readable; a
  separate export vector for types would be two contracts free to disagree about what is public.
  The entry's case decides its kind, because the language already fixes type names as PascalCase
  and identifiers as lowercase, so no keyword is needed to tell them apart. This is the one place
  where spelling decides a kind, and it is a deliberate exception to the stance that a name is a
  type variable because it was declared one and never because of how it is spelled — recorded as
  an exception rather than left to read as a contradiction.
- **Why Non-Obvious**: The obvious reading is that a separate list is safer because it is
  explicit. It is the opposite: two lists can disagree, and the thing being optimised is that one
  pass can compose on another by reading a single contract.

### [d-d06b] An exported type is transparent; opacity is deferred and the syntax left additive
- **Date**: 2026-08-29
- **Status**: Active
- **Cluster**: lang/modules
- **Description**: Exporting a union publishes its cases; exporting a record publishes its fields.
  There is no opaque export in this version, and the export syntax is left in a shape that can
  grow one later without invalidating anything written now.
- **Rationale**: Totality forces transparency: a match must be exhaustive and case names are both
  constructors and patterns, so an importer that cannot see every case cannot write a legal match —
  an opaque union would be unusable rather than merely restricted. The stronger reason to defer
  opacity is that an opaque type is an abstract handle whose semantics depend on the ownership
  model l-880d deliberately leaves unrecorded; settling opacity now would settle ownership by
  accident. Transparency is also the form the compiled-module interface contract needs, because
  data crossing a component boundary has to be described structurally for a host to marshal it.
- **Why Non-Obvious**: This narrows d-f99b, which is worth stating rather than leaving implied: the
  export list is now a *seed* for the public surface rather than the whole of it, and a mechanical
  extractor has to read the header together with the declarations of the types it names. Both are
  still in one file, so the property survives — but the claim "the surface is the export list" is
  no longer literally true.

### [d-b47d] An exported signature may only name public types
- **Date**: 2026-08-29
- **Status**: Active
- **Cluster**: lang/modules
- **Description**: Every type named in an exported function's signature, in an exported record's
  field, or in an exported union's case parameters must itself be public — a built-in, a type
  variable bound by that declaration, or a type exported by the module that defines it. Checked
  against the *defining* module, so a type published by one module and used in another's exported
  signature needs no re-export.
- **Rationale**: The lexical half of the fix — making a type expressible across a boundary — does
  not by itself make the header a contract. Without this rule a module can still export a function
  whose parameter type no importer can write, which is verbatim the gap r-ea8c records. It carries
  its own diagnostic code rather than extending the existing "exported but not defined" one,
  because a gate asserts the specific code a fixture declares, and sharing a code would let one
  defect satisfy the other's fixture.
- **Why Non-Obvious**: The rule is a *new rejection of already-accepted programs* — it broke one
  corpus fixture and one test fixture, both of which had exactly this defect and both of which
  checked clean. That cost is small now and grows with every program written before it lands.
