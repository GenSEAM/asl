# Phase 4 Plan: Verifiable Agent-to-Agent Escrow Contract Benchmark (`agent-escrow-benchmark`)

## Objective
Build and benchmark a reference Agent Escrow Contract in pure AgentScript:
- Use Case: Agent A deposits bounty (e.g. 0.05 ETH) for context digest task. Agent B submits hash receipt. Timeout refunds Agent A.
- Demonstrate mathematical proof: Zero funds can be locked indefinitely or drained by unauthorized parties.
- Benchmark: Compare gas/token efficiency vs Solidity equivalent on Arbitrum Stylus and EVM.

## Work Items

### Item 1: Reference Escrow Contract (`examples/escrow.asl`)
- **Target**: `asl/packages/asl-contracts/examples/escrow.asl`
- **Details**:
  - Escrow State: `(dfe EscrowState [created funded completed refunded])`.
  - Pure transitions: `deposit`, `submit-proof`, `claim`, `timeout-refund`.
- **Gate**: `asl check asl/packages/asl-contracts/examples/escrow.asl`

### Item 2: End-to-End Escrow & Safety Proof Test Suite (`tests/escrow_test.asl`)
- **Target**: `asl/packages/asl-contracts/tests/escrow_test.asl`
- **Details**: Run full lifecycle (deposit -> proof -> claim), verify timeout logic, and verify that SMT safety theorem passes.
- **Gate**: `PATH="$PWD/asl:$PATH" asl test asl/packages/asl-contracts/tests/escrow_test.asl`

## Acceptance Criteria
- Complete escrow lifecycle passes all invariants.
- SMT proof confirms absence of fund drain vulnerability.
