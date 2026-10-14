# asl-contracts (package `aslContracts`)

Experimental. Three ASL modules of record types and pure validation functions; nothing in them runs a contract, a prover or a Wasm module.

- `spec.asl`: state-transition records for a smart-contract sketch (`BlockContext`, `ContractEvent`, `TransitionResult`, `transitionSuccess`, `transitionRevert`, `isValidAddress`, `validateNonNegativeBalance`).
- `stage.asl`: pipeline stage contracts (`StageContract`, `stageTransition`, `isStageTerminal?`, `validateStageContract`).
- `toolPlane.asl`: tool descriptors, scopes, secret masking and runbooks (`ToolDescriptor`, `isToolInScope?`, `isAgentAuthorized?`, `maskToolSecrets`, `canonicalMemToolDescriptors`).

The `manifest.asn` description names SMT safety proofs and a Wasm Stylus ABI; the package has no code for either. The manifest has no `:modules` list. Module names use the prefix `aslContracts/`; all 3 files in `src/` pass `asl/host/out/asl-host check` (2026-10-14).

## Modules and exports

From the `:x` list in each module header under `src/` (2026-10-14): 3 modules, 44 exported names. Long lists are cut at 18 names; the header of each file has the full list.

- `aslContracts/spec` (`src/spec.asl`, 8): `BlockContext`, `ContractEvent`, `TransitionResult`, `isValidAddress`, `makeBlockContext`, `transitionSuccess`, `transitionRevert`, `validateNonNegativeBalance`.
- `aslContracts/stage` (`src/stage.asl`, 10): `PipelineStage`, `StageStatus`, `StageContract`, `makeStageContract`, `stageTransition`, `stageSetOutput`, `stageSetError`, `isStageTerminal?`, `isStageSuccessful?`, `validateStageContract`.
- `aslContracts/toolPlane` (`src/toolPlane.asl`, 26): `ToolSafety`, `ToolDescriptor`, `SecretRef`, `ToolRunbook`, `ToolScopeContext`, `safetySafe`, `safetyGuarded`, `safetyDangerous`, `makeSecretRef`, `makeToolDescriptor`, `makeRunbook`, `makeScopeContext`, `isToolInScope?`, `isAgentAuthorized?`, `isSafetyPermitted?`, `maskToolSecrets`, `validateToolDescriptor`, `toolMemQuery`, and 8 more.

## Tests

Measured 2026-10-14 with the stage-0 host, run from the directory that contains the `asl/` checkout:

```sh
asl/host/out/asl-host test asl/packages/asl-contracts/tests/<file>.asl
```

3 of 3 test files exit 0 (81 assertions and refutations pass in those files).

| File | Result | Detail |
|---|---|---|
| `specTest.asl` | pass | 18 assertions |
| `stageTest.asl` | pass | 33 assertions |
| `toolPlaneTest.asl` | pass | 30 assertions |
