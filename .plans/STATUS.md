# Iteration Status: iter-smart-contracts-01

**Active Roadmap**: `.plans/PHASES.md`  
**Current Wave**: Wave 0 (Batch Ahead Planning & Implementation)  
**Overall State**: `planning-complete`

---

## Phase Status Summary

| Phase ID | Wave | Priority | Isolation | Status | Blockers | Verification Gate |
|---|---|---|---|---|---|---|
| `asl-contract-spec-and-ast` | Wave 0 | P0 | single-tree | `ready` | None | `asl test asl/packages/asl-contracts/tests/spec_test.asl` |
| `z3-smt-formal-verifier` | Wave 1 | P1 | single-tree | `pending` | `asl-contract-spec-and-ast` | `asl test asl/packages/asl-contracts/tests/smt_test.asl` |
| `wasm-stylus-target` | Wave 1 | P1 | single-tree | `pending` | `asl-contract-spec-and-ast` | `asl test asl/packages/asl-contracts/tests/stylus_test.asl` |
| `agent-escrow-benchmark` | Wave 2 | P1 | single-tree | `pending` | `z3-smt-formal-verifier`, `wasm-stylus-target` | `asl test asl/packages/asl-contracts/tests/escrow_test.asl` |
