---
name: asl-contracts
description: Pure functional, formally verifiable smart contracts for Arbitrum Stylus (Wasm) and CosmWasm in AgentScript. Use when authoring contracts, verifying mathematical balance conservation with SMT-LIB2 / Z3, or designing agent escrow protocols.
---

# AgentScript Verifiable Smart Contracts Skill

`@genseam/asl-contracts` enables pure functional, provably secure smart contract engineering without reentrancy vulnerabilities.

## Core Invariants
- **Zero Reentrancy**: Contracts are pure state transition functions: `(transition State Action Context -> (Pair State (List Event)))`.
- **Zero Floating-Point**: Floating-point numbers (`F64`) are banned at the specification level.
- **SMT Proofs by Construction**: S-expression ASTs translate directly to SMT-LIB2 formulas for Z3/CVC5 theorem provers.

## Running Contract Tests
```bash
# Run contract specification test suite
asl test asl/packages/asl-contracts/tests/spec_test.asl
```
