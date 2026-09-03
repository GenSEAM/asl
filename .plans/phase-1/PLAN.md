# Phase 1 Plan: ASL Harness Core Schema & Epistemic State Machine

## Goal
Implement pure AgentScript data models, epistemic ledger, and FSM transition function for the portable agent harness in `packages/asl-harness/src/`.

## Work Items

### Item 1: Core Lifecycle Enums & Effect Data Structures
- **File**: `packages/asl-harness/src/core.asl`
- **Specification**:
  - `AgentState`: `(idle)`, `(planning)`, `(acting)`, `(verifying)`, `(reflecting)`, `(completed)`, `(failed)`
  - `AgentEvent`: `(start [task: Str])`, `(plan-ready [steps: (List Str)])`, `(effect-done [effect-id: Str result: Str])`, `(verified [approved: Bool reason: Str])`, `(abort [reason: Str])`
  - `AgentEffect`: `(search [query: Str max-results: I64])`, `(fetch [url: Str])`, `(infer [prompt: Str schema-name: Str])`, `(memory-query [query: Str top-k: I64])`, `(memory-save [key: Str val: Str])`, `(run-tool [tool: Str args-json: Str])`, `(emit-final [answer: Str])`
- **Gate**: `.venv/bin/python checker/gate.py && .venv/bin/python tools/native_parser.py packages/asl-harness/src/core.asl`

### Item 2: Epistemic Ledger & Grounding Fact Structure
- **File**: `packages/asl-harness/src/ledger.asl`
- **Specification**:
  - `EpistemicFact`: `id: Str`, `claim: Str`, `source-id: Str`, `exact-snippet: Str`, `confidence: F64`, `verified: Bool`
  - `EpistemicLedger`: `task: Str`, `facts: (List EpistemicFact)`, `unverified-count: I64`, `token-budget: I64`, `context-used: I64`
  - Helpers: `create-ledger`, `record-fact`, `mark-fact-verified`, `compute-unverified`, `calculate-remaining-tokens`
- **Gate**: `.venv/bin/python checker/gate.py && .venv/bin/python tools/native_parser.py packages/asl-harness/src/ledger.asl`

### Item 3: Pure State Transition Function (FSM)
- **File**: `packages/asl-harness/src/state_machine.asl`
- **Specification**:
  - `step: (state: AgentState, event: AgentEvent, ledger: EpistemicLedger) -> (Pair AgentState (List AgentEffect))`
  - Transition invariants:
    - `idle` + `start` -> transitions to `planning`, emits initial model inference or memory recall effect.
    - `planning` + `plan-ready` -> transitions to `verifying` (or `acting` if plan is groundable).
    - `acting` + `effect-done` -> transitions to `verifying` before committing to state.
    - `verifying` + `verified(true)` -> advances to next action or `completed`.
    - `verifying` + `verified(false)` -> transitions to `reflecting` and emits replan or correction effect.
    - `is-terminal-state: (state: AgentState) -> Bool`
- **Gate**: `.venv/bin/python checker/gate.py && .venv/bin/python tools/native_parser.py packages/asl-harness/src/state_machine.asl`

### Item 4: Unit Test Suite for State Machine & Ledger
- **File**: `packages/asl-harness/tests/state_machine_test.asl`
- **Specification**:
  - Tests step transitions across full happy path: `idle` -> `planning` -> `acting` -> `verifying` -> `completed`.
  - Tests rejection and reflection path: ungrounded fact transitions to `reflecting`.
- **Gate**: `.venv/bin/python checker/gate.py && .venv/bin/python tools/native_checker.py packages/asl-harness/tests/state_machine_test.asl`
