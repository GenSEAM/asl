# Measurement / Harness

This file groups d/c/r/l entries for the measurement/harness module.

### [r-7ea3] Agent capability is measured externally, never asserted
- **Date**: 2026-08-20
- **Status**: Active
- **Cluster**: measurement/harness
- **Description**: The project's core claim is that agents handle this language well and get more
  done per pass. That claim cannot be self-certified by the same assistant that designed the
  language, and cannot be inferred from the language looking regular.
- **Requirement**: Capability is measured by an external agent driving a gateway-hosted model
  against the pre-registered protocol, with a weak model chosen deliberately so that a positive
  result is not an artifact of frontier capability. Work-per-pass is measured as a first-class
  outcome alongside correctness, since it is the stated benefit.
- **Scenario**: An external agent is given the specification and a task, and its output is scored
  without the language's authors in the loop.
- **Why Non-Obvious**: Every intermediate artifact so far — grammars, corpus, conformance gate —
  measures internal consistency, which is necessary and proves nothing about the actual claim.
