# asl-plugin

ASL types and functions for a plugin registry: manifests, capability lookup, call dispatch with caller authentication, sandbox path checks, a dynamic tool plane, and a codegen target registry.

## Modules (`asl/packages/asl-plugin/src`)
- `types.asl`: `PluginKind` (wasm, native FFI, host driver), `PluginManifest`, `PluginRegistry`, `PluginCall`, `CallerAuth`, `DispatchReceipt` and error constructors.
- `plugin.asl`: `emptyRegistry`, `registerPlugin`, `lookupManifest`, `hasCapability?`, `findPluginsByCapability`, `dispatchCall`, `sealRegistry`.
- `security.asl`: `validateSandboxPath`, `verifyArtifactDigest`, `authorizeCall`, caller signature and nonce checks, `constantTimeEqual`.
- `dynamicTool.asl`: tool domains that load and unload per turn (`loadDomain`, `unloadDomain`, `renderLandscape`, `lookupToolHelp`).
- `targetRegistry.asl`: `registerCodegenTarget`, `lookupTarget`, `dispatchTargetCodegen`.

No plugin implementation (database, filesystem, network) ships in this package; `types.asl` only names capability kinds.

## Tests (2026-09-24)
`./bin/asl test` (lenient asl-core) exits 0 on `asl/packages/asl-plugin/tests/pluginTest.asl` (9 assertions, 3 refutations), `targetRegistryTest.asl` (28, 25) and `dynamicToolTest.asl` (89, 13). `asl/host/out/asl-host test` exits 1 on all three with 61, 8 and 1 load errors.
