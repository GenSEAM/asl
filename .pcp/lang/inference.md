# Lang / Inference

This file groups d/c/r/l entries for the lang/inference module.

### [r-a624] Lambda parameter and return types must be inferred, not written
- **Date**: 2026-08-21
- **Status**: Active
- **Cluster**: lang/inference
- **Description**: A lambda passed to a higher-order builtin currently repeats types the callee's
  signature already fixes completely. Nothing is learned by writing them and nothing is checked
  that could not be checked without them — the position determines them uniquely.
- **Requirement**: Annotations on a lambda are optional wherever the expected type is determined by
  the context it appears in. Named declarations keep their mandatory annotations; those form the
  module surface and are read without the body.
- **Measured cost of not doing this**: on the first benchmark task, removing these redundant
  annotations moves the language from 1.83x to 1.66x the size of equivalent typed Python. It is the
  single largest removable overhead found.
- **Why Non-Obvious**: Mandatory annotations everywhere looks like consistency, and consistency
  looks like a virtue in a language meant to be unambiguous. But an annotation that cannot differ
  from what the context implies carries no information — it is ceremony that costs exactly the
  budget the project is trying to spend on problem-solving instead.
