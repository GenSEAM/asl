# asl-plugin

ASL types and functions for a plugin registry: manifests, capability lookup, call authorisation with caller signatures and nonces, sandbox path and artifact digest checks, a dynamic tool plane, and a codegen target registry.

- `types.asl`: `PluginKind` (wasm, native FFI, host driver), `PluginManifest`, `PluginRegistry`, `PluginCall`, `CallerAuth`, `DispatchReceipt` and error constructors.
- `plugin.asl`: `emptyRegistry`, `registerPlugin`, `lookupManifest`, `hasCapability?`, `findPluginsByCapability`, `dispatchCall`, `sealRegistry`. `dispatchCall` checks the export, the nonce and the caller signature, bumps the instance's invocation count and returns a receipt with an empty output buffer; it does not load or run plugin code.
- `security.asl`: `validateSandboxPath!`, `verifyArtifactDigest!` (runs `shasum -a 256`, falling back to `sha256sum`, directly rather than through a shell), `authorizeCall!`, caller signature and nonce checks, `constantTimeEqual`.
- `dynamicTool.asl`: tool domains that load and unload per turn (`loadDomain`, `unloadDomain`, `renderLandscape`, `lookupToolHelp`).
- `targetRegistry.asl`: `registerCodegenTarget`, `lookupTarget`, `dispatchTargetCodegen`.

No plugin implementation (database, filesystem, network) ships in this package; `types.asl` only names capability kinds.

Module names use the prefix `asl-plugin/`; `manifest.asn` lists the same 5 modules. All 5 files in `src/` pass `asl/host/out/asl-host check` (2026-10-14).

## Modules and exports

From the `:x` list in each module header under `src/` (2026-10-14): 5 modules, 83 exported names. Long lists are cut at 18 names; the header of each file has the full list.

- `asl-plugin/dynamicTool` (`src/dynamicTool.asl`, 33): `ToolParam`, `ToolDef`, `ToolDomain`, `ToolPlane`, `MountReceipt`, `UnmountReceipt`, `ActiveLandscape`, `baseTools`, `emptyPlane`, `createParam`, `createTool`, `createDomain`, `domainLoaded?`, `hasTool?`, `lookupTool`, `toolCount`, `activeDomains`, `loadDomain`, and 15 more.
- `asl-plugin/plugin` (`src/plugin.asl`, 8): `emptyRegistry`, `registerPlugin`, `lookupManifest`, `lookupInstance`, `hasCapability?`, `findPluginsByCapability`, `dispatchCall`, `sealRegistry`.
- `asl-plugin/security` (`src/security.asl`, 9): `validateSandboxPath!`, `verifyArtifactDigest!`, `validateManifestSecurity!`, `authorizeCall!`, `computeCallerSignature!`, `verifyCallerSignature!`, `verifyCallerNonce`, `constantTimeEqual`, `validateManifestHash!`.
- `asl-plugin/targetRegistry` (`src/targetRegistry.asl`, 8): `TargetRegistry`, `emptyTargetRegistry`, `registerTarget`, `registerCodegenTarget`, `hasTarget?`, `lookupTarget`, `dispatchTargetCodegen`, `listRegisteredTargets`.
- `asl-plugin/types` (`src/types.asl`, 25): `PluginKind`, `PluginCapability`, `PluginExport`, `PluginManifest`, `PluginInstance`, `PluginRegistry`, `PluginBuffer`, `PluginError`, `PluginResult`, `PluginCall`, `CallerAuth`, `DispatchReceipt`, `DispatchFault`, `kindWasm`, `kindNativeFfi`, `kindHostDriver`, `errNotFound`, `errDuplicateId`, and 7 more.

## Tests

Measured 2026-10-14 with the stage-0 host, run from the directory that contains the `asl/` checkout:

```sh
asl/host/out/asl-host test asl/packages/asl-plugin/tests/<file>.asl
```

8 of 9 test files exit 0 (322 assertions and refutations pass in those files).

| File | Result | Detail |
|---|---|---|
| `argvTest.asl` | **fail** | spawns `bin/asl run ...`, which does not exist |
| `artifactDigestTest.asl` | pass | 15 assertions, 3 refutations |
| `callerAuthTest.asl` | pass | 40 assertions, 4 refutations |
| `dynamicToolTest.asl` | pass | 89 assertions, 13 refutations |
| `pluginTest.asl` | pass | 9 assertions, 3 refutations |
| `pluginTypesTest.asl` | pass | 18 assertions, 5 refutations |
| `registryDispatchTest.asl` | pass | 43 assertions, 5 refutations |
| `sandboxPathTest.asl` | pass | 17 assertions, 5 refutations |
| `targetRegistryTest.asl` | pass | 28 assertions, 25 refutations |
