# asl-contracts (package `aslContracts`)

Experimental. Three ASL modules of record types and pure validation functions.

## Modules (`asl/packages/asl-contracts/src`)
- `spec.asl`: state-transition records for a smart-contract sketch (`BlockContext`, `ContractEvent`, `TransitionResult`, `transitionSuccess`, `transitionRevert`, `isValidAddress`, `validateNonNegativeBalance`).
- `stage.asl`: pipeline stage contracts (`StageContract`, `stageTransition`, `isStageTerminal?`, `validateStageContract`).
- `toolPlane.asl`: tool descriptors, scopes, secret masking and runbooks (`ToolDescriptor`, `isToolInScope?`, `isAgentAuthorized?`, `maskToolSecrets`, `canonicalMemToolDescriptors`).

SMT proofs and a Wasm Stylus ABI are named in `manifest.asn` but have no code in the package.

## Tests (2026-09-24)
| file | `./bin/asl test` (asl-core) | `asl/host/out/asl-host test` |
|---|---|---|
| `asl/packages/asl-contracts/tests/specTest.asl` | exit 0, 18 assertions | exit 0, 18 assertions |
| `asl/packages/asl-contracts/tests/stageTest.asl` | exit 0, 33 assertions | exit 0, 33 assertions |
| `asl/packages/asl-contracts/tests/toolPlaneTest.asl` | exit 0, 30 assertions | exit 1, 1 load error |
