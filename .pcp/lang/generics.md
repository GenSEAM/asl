# Lang / Generics

This file groups d/c/r/l entries for the lang/generics module.

### [r-8f23] User code must be as polymorphic as the prelude
- **Date**: 2026-08-20
- **Status**: Active
- **Cluster**: lang/generics
- **Description**: The built-in collection operations are polymorphic, but nothing lets a user
  declare a type parameter. Reuse is therefore capped at whatever shipped in the prelude: any
  shared abstraction a user writes must be duplicated per concrete type.
- **Requirement**: Users can parameterise functions and records over types, with inference at call
  sites so the common case costs no annotation.
- **Why Non-Obvious**: The language looks expressive in examples precisely because the polymorphic
  operations used there are built in. The ceiling is invisible until someone tries to factor out
  their own reusable abstraction.
