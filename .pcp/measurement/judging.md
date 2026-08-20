# Measurement / Judging

This file groups d/c/r/l entries for the measurement/judging module.

### [c-9af5] The language's designer cannot be its scoring judge
- **Date**: 2026-08-20
- **Status**: Active
- **Cluster**: measurement/judging
- **Description**: Qualitative review of transpiled output is wanted, and the assistant that
  designed the language has been asked to provide it. That is useful for one class of judgement
  and disqualifying for another, and the two must not be merged.
- **Boundary**: Pass and fail stay mechanical — tests execute, the target compiles or does not,
  the reference implementation and each backend agree or do not. No judgement enters the gate.
  Qualitative critique of idiomaticity, readability and transpiler artifacts is reported alongside,
  never folded into the score.
- **Why Non-Obvious**: A judge who authored the thing being judged does not need to be dishonest to
  bias the result. Every ambiguous case resolves toward the design they already chose, and the
  errors correlate rather than cancel — which is precisely what a scoring metric assumes they do
  not. The bias is undetectable from inside, so it has to be excluded structurally rather than
  guarded against.
