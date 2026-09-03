# Phase 5 Plan: Anti-Hallucination & Precision Guardrails

## Goal
Construct an automated grounding and invariant verification pipeline in pure ASL: citation verification against retrieved search/doc snippets, algebraic schema conformity via `asl-codec`, AST invariant checks via `asl-lint`, and pre-execution assertion gates.

## Work Items

### Item 1: Grounding & Citation Overlap Validator in ASL
- **File**: `packages/asl-harness/src/grounding.asl`
- **Specification**:
  - `dfe GroundingVerdict`: `(:c fully-grounded [overlap-score: F64])`, `(:c partially-grounded [overlap-score: F64 missing-tokens: (List Str)])`, `(:c ungrounded [detail: Str])`
  - `verify-citation-overlap`: takes claimed sentence and source snippet, measures token containment / 3-gram intersection.
  - `filter-ungrounded-claims`: purges or flags any statement lacking grounded evidence above threshold `0.75`.
- **Gate**: `.venv/bin/python checker/gate.py && .venv/bin/python tools/native_parser.py packages/asl-harness/src/grounding.asl`

### Item 2: Schema & AST Invariant Verifier
- **File**: `packages/asl-harness/src/verifier.asl`
- **Specification**:
  - `validate-model-json`: checks that LLM JSON output parses into valid `JsonValue` (`asl-codec/core/codec.asl`) and conforms to target schema keys.
  - `lint-asl-code`: checks generated ASL code against `asl-lint` rules (anti-patterns, unbounded recursion, unhandled `Result`).
  - Pre-execution Gate: If verification fails, FSM blocks tool execution and triggers `AgentEvent.verification-fail(reason)`.
- **Gate**: `.venv/bin/python checker/gate.py && .venv/bin/python tools/native_parser.py packages/asl-harness/src/verifier.asl`

### Item 3: Anti-Hallucination Test Suite
- **File**: `packages/asl-harness/tests/test_grounding.ts`
- **Specification**:
  - Test 1: Grounded answer with verbatim citations -> verification PASS.
  - Test 2: Hallucinated claims with fabricated facts -> verification FAIL, FSM transitions to `reflecting`.
  - Test 3: Malformed JSON or unhandled AST error -> blocked before execution.
- **Gate**: `.venv/bin/python checker/gate.py && npx tsx packages/asl-harness/tests/test_grounding.ts`
