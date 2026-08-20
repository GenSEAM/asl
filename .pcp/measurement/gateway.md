# Measurement / Gateway

This file groups d/c/r/l entries for the measurement/gateway module.

### [l-298e] Measurement is blocked on external access details, not on design
- **Date**: 2026-08-20
- **Status**: Blocked
- **Cluster**: measurement/gateway
- **Description**: The measurement protocol is pre-registered and its thresholds are fixed, but no
  run can happen until the gateway endpoint, the exact model identifier, and the environment
  variable carrying the credential are supplied. The external agent's headless invocation is
  likewise unspecified.
- **Requirement**: Credentials reach the harness through the environment only and never enter the
  repository or any committed artifact.
- **Why Non-Obvious**: The harness can be written and unit-tested without any of this, which makes
  the blocker easy to defer past the point where it matters. It is a hard gate on the project's
  central claim, and the claim cannot be self-certified by the party that designed the language.
