# Lang / Projection

This file groups d/c/r/l entries for the dual-projection architecture and AST readability.

### [d-1eed] Dual-Projection Architecture: Nano Wire Default & Verbose Human Inspection
- **Date**: 2026-09-02
- **Status**: Final
- **Cluster**: lang/projection
- **Description**: AgentScript enforces a dual-projection firewall: physical source files on disk and inter-agent protocol frames standardize on the high-density Nano format (`asl/coord`, compact S-expressions) to conserve token budgets and eliminate token waste. Human developers inspect and debug code via non-mutating verbose projections (virtual editor documents or terminal views). Full manual file expansion and re-compression occur only upon explicit user request, avoiding volatile Git clean/smudge filters or automated on-save mutations.

### [c-adc8] Deep Control-Flow Nesting and Attentional Drift
- **Date**: 2026-09-02
- **Status**: Final
- **Cluster**: lang/projection
- **Description**: S-expression nesting deeper than four control-flow levels induces attentional drift during autoregressive LLM generation, multiplying the risk of mismatched delimiters and hallucinated out-of-scope bindings. Deeply nested match and conditional blocks must be decomposed into linear pipelines using early-exit error propagation and localized helper definitions.

### [r-8d8e] Non-Mutating Virtual Projection Inspection Tooling
- **Date**: 2026-09-02
- **Status**: Final
- **Cluster**: lang/projection
- **Description**: The toolchain must provide read-only virtual projection inspection (`asl view`, `asl sql view`, virtual IDE schemes) that renders compact AST sources into fully documented verbose representations and parameterized multi-dialect SQL targets without altering on-disk files.
