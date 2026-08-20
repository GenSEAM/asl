# Spec / Closure

This file groups d/c/r/l entries for the spec/closure module.

### [c-ca5c] Specification asserts closure instead of proving it
- **Date**: 2026-08-20
- **Status**: Active
- **Cluster**: spec/closure
- **Description**: The specification's central claim is that it is closed — that every identifier
  appearing in its own examples is defined within it — because a model can only be judged on forms
  the document actually gave it. Examples nevertheless call helpers that are defined nowhere. This
  is the exact defect the predecessor document was criticised for.
- **Why Non-Obvious**: Closure degrades silently. Examples are written to illustrate one construct,
  and any plausible-looking helper invented for the illustration reads as if it must be defined
  elsewhere. Only an automated audit distinguishes "defined" from "looks defined", so closure has
  to be a gate in the pipeline rather than a property anyone asserts in prose.
