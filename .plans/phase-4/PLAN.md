# Phase 4: `asl-native-gate-runner` Plan

## Objective
Enhance `packages/asl-cli/src/cli.asl` and `packages/asl-gates/src/gates.asl` to execute multi-file verification suites directly without falling back to python scripts.

## Work Items
1. Support batch glob and file lists in `asl-gates/src/gates.asl`.
2. Connect `dispatch-cmd "gate"` in `asl-cli` directly to `asl-gates/gates/run-suite`.
3. Add regression tests in `packages/asl-cli/tests/cli-test.asl`.

## Acceptance Gate
`node asl/bin/asl gate asl/packages/asl-cli/src/cli.asl asl/packages/asl-gates/src/gates.asl`
