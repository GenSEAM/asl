# Phase 1 Plan: ASL Contract Specification & Functional State-Machine AST (`asl-contract-spec-and-ast`)

## Objective
Define the pure AgentScript Smart Contract specification and core AST structures in `@genseam/asl-contracts`:
- Ban floating-point (`F64`) in contracts.
- Model contract state transitions as pure functions: `(transition State Action Context -> (Pair State (List Event)))`.
- Declare standard blockchain types: `Address`, `Balance (U256)`, `BlockContext` (`timestamp`, `number`, `sender`, `value`).
- Implement contract manifest `packages/asl-contracts/manifest.asn`.

## Work Items

### Item 1: Package Manifest & Module Definition
- **Target**: `asl/packages/asl-contracts/manifest.asn`
- **Details**: Declare `@genseam/asl-contracts` with version 0.1.0, entry `src/spec.asl`.
- **Gate**: `test -f asl/packages/asl-contracts/manifest.asn`

### Item 2: Core Contract AST & Types (`spec.asl`)
- **Target**: `asl/packages/asl-contracts/src/spec.asl`
- **Details**:
  - Types: `Address` (Str hex string), `TokenAmount` (I64 / safe integer), `BlockContext` (sender, value, timestamp, height).
  - Algebraic State: Contract state records and Transition event records.
  - Contract Declaration: `ContractSpec` defining methods, read-only getters, and state transitions.
- **Gate**: `asl check asl/packages/asl-contracts/src/spec.asl`

### Item 3: Unit Test Suite (`spec_test.asl`)
- **Target**: `asl/packages/asl-contracts/tests/spec_test.asl`
- **Details**: Verify pure state transitions, event emissions, and context verification.
- **Gate**: `PATH="$PWD/asl:$PATH" asl test asl/packages/asl-contracts/tests/spec_test.asl`

## Acceptance Criteria
- Pure functional transition model verified.
- Pre-commit gate 100% green.
