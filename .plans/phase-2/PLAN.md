# Phase 2 Plan: SMT-LIB2 Formal Verification Engine (`z3-smt-formal-verifier`)

## Objective
Implement native S-expression to SMT-LIB2 theorem translator for contract safety verification:
- Prove conservation of balance: `sum(balances_after) == sum(balances_before) + msg.value - transfers_out`.
- Prove no unauthorized balance mutation (only sender or owner can mutate).
- Prove termination (total functional transitions with no unbounded iteration).
- Emit standardized SMT-LIB2 queries readable by Z3 and CVC5.

## Work Items

### Item 1: SMT-LIB2 AST & Emitter (`smt.asl`)
- **Target**: `asl/packages/asl-contracts/src/smt.asl`
- **Details**:
  - `SmtSort`: Int, Bool, BitVec256.
  - `SmtExpr`: `(assert ...)`, `(check-sat)`, `(declare-const ...)`.
  - Invariant Generator: Translates contract transitions and asserts safety invariants.
- **Gate**: `asl check asl/packages/asl-contracts/src/smt.asl`

### Item 2: Formal Verification Test Suite (`smt_test.asl`)
- **Target**: `asl/packages/asl-contracts/tests/smt_test.asl`
- **Details**: Test generation of conservation invariants, integer overflow checks, and check-sat generation.
- **Gate**: `PATH="$PWD/asl:$PATH" asl test asl/packages/asl-contracts/tests/smt_test.asl`

## Acceptance Criteria
- SMT-LIB2 emission produces syntactically valid S-expression formulas.
- Invariant formulas prove conservation and access control properties.
