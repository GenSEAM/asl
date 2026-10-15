---
name: asl-contracts
description: Map of asl/packages/asl-contracts, an experimental pure AgentSlang package of contract records and validation functions (a smart-contract state-transition sketch, pipeline stage contracts, and tool descriptors with scopes and secret masking). Use when reading, changing or testing those modules. It has no SMT or Z3 proofs, no Wasm Stylus or CosmWasm ABI and no chain connection; those are named in its manifest description only.
---

# asl-contracts (package `aslContracts`)

Experimental. Three modules of record types and pure validation functions, entry `src/spec.asl`.

| Module | Holds |
|---|---|
| `src/spec.asl` | Smart-contract state-transition sketch: `BlockContext` (`sender` `value` `timestamp` `height`), `ContractEvent`, `TransitionResult`, `makeBlockContext`, `transitionSuccess`, `transitionRevert`, `isValidAddress` (0x plus 40 hex digits), `validateNonNegativeBalance` |
| `src/stage.asl` | Pipeline stage contracts: `PipelineStage`, `StageStatus`, `StageContract`, `stageTransition`, `isStageTerminal?`, `isStageSuccessful?`, `validateStageContract` |
| `src/toolPlane.asl` | Tool descriptors and their policy: `ToolSafety`, `ToolDescriptor`, `isToolInScope?`, `isAgentAuthorized?`, `maskToolSecrets`, `canonicalMemToolDescriptors` |

What it is not, today: `manifest.asn` describes "SMT formal safety proofs, and Wasm Stylus ABI",
but no code in the package emits SMT-LIB2, calls a prover, or targets Arbitrum Stylus or
CosmWasm. Balances are `I64` and checked by `validateNonNegativeBalance`; nothing proves
conservation. Treat those as plans.

## Testing

Run from the workspace root; exit 0 and the executed assertion count are the evidence:

```bash
asl/host/out/asl-host test asl/packages/asl-contracts/tests/specTest.asl
asl/host/out/asl-host test asl/packages/asl-contracts/tests/stageTest.asl
asl/host/out/asl-host test asl/packages/asl-contracts/tests/toolPlaneTest.asl
```

On 2026-10-14 these executed 18, 33 and 30 assertions, all passing.
