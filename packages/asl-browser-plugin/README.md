# asl-browser-plugin (package `aslBrowserPlugin`)

ASL modules written for a Manifest V3 browser extension: a service-worker message router (`background`), content-script page-context extraction and action dispatch (`content`), generators that emit JavaScript text for DOM probes, table extraction and text selection (`domCompiler`), routing between local and remote inference (`localSlm`), mesh registration packets (`meshClient`), an action safety tier check (`safetyGate`), and records for tabs, an OPFS workspace path check, browser capabilities and trace frames (`runtime`).

Status (2026-10-14): the extension cannot be loaded into a browser. `manifest.json` points `background.service_worker` and `content_scripts.js` at `src/background.asl` and `src/content.asl`, which a browser does not execute; `src/manifest.asn` points at `dist/background.js` and `dist/content.js`, and `src/popup.html` loads `../dist/popup.js`, but there is no `dist/` directory and nothing in the repository compiles these modules to JavaScript. The `src/offscreen.html` page that both manifests name does not exist.

The package holds `manifest.json`, `extension.asn`, `src/manifest.asn` and `src/popup.html` alongside the ASL modules. Module names use the prefix `aslBrowserPlugin/`, except `src/popup.asl`, which declares `browserPlugin/popup`. All 9 `.asl` files in `src/` pass `asl/host/out/asl-host check`.

## Modules and exports

From the `:x` list in each module header under `src/` (2026-10-14): 9 modules, 68 exported names. Long lists are cut at 18 names; the header of each file has the full list.

- `aslBrowserPlugin/background` (`src/background.asl`, 3): `initServiceWorker`, `routeActionMessage`, `handleMessage`.
- `aslBrowserPlugin/content` (`src/content.asl`, 9): `PageContext`, `makePageContext`, `formatPageContext`, `extractPageContext`, `isValidActionType?`, `isValidSelector?`, `dispatchAction`, `executeContentAction`, `execInPageAgent`.
- `aslBrowserPlugin/domCompiler` (`src/domCompiler.asl`, 3): `compileProbeJs`, `compileTableExtractor`, `compileTextSelector`.
- `aslBrowserPlugin/localSlm` (`src/localSlm.asl`, 5): `InferenceRoute`, `InferenceTarget`, `selectInferenceRoute`, `dispatchLocalPerception`, `evaluateConfidence`.
- `aslBrowserPlugin/meshClient` (`src/meshClient.asl`, 5): `MeshNodeInfo`, `MeshCommandPacket`, `formatNodeRegistration`, `formatMeshResponse`, `parseMeshCommand`.
- `aslBrowserPlugin/plugin` (`src/plugin.asl`, 3): `startPlugin`, `getPluginVersion`, `getAslanyBrand`.
- `browserPlugin/popup` (`src/popup.asl`, 2): `renderPopup`, `viewModel`.
- `aslBrowserPlugin/runtime` (`src/runtime.asl`, 33): `BrowserTab`, `TabQuery`, `BrowserAgentState`, `BrowserRuntimeBridge`, `WasmRpcBridge`, `makeBrowserTab`, `listActiveTabs`, `filterTabsByQuery`, `extractTabContext`, `crawlDomainTree`, `makeBrowserAgent`, `handleAgentTick`, `executeAgentAction`, `makeBrowserRuntimeBridge`, `makeWasmRpcBridge`, `dispatchBatchRpc`, `OpfsWorkspace`, `BrowserCapability`, and 15 more.
- `aslBrowserPlugin/safetyGate` (`src/safetyGate.asl`, 5): `BrowserAction`, `classifyActionTier`, `validateBrowserAction`, `isActionPermitted?`, `makeBrowserAction`.

## Tests

Measured 2026-10-14 with the stage-0 host, run from the directory that contains the `asl/` checkout:

```sh
asl/host/out/asl-host test asl/packages/asl-browser-plugin/tests/<file>.asl
```

3 of 3 test files exit 0 (70 assertions and refutations pass in those files).

| File | Result | Detail |
|---|---|---|
| `browserAgentTest.asl` | pass | 26 assertions, 11 refutations |
| `runtimeTest.asl` | pass | 18 assertions, 7 refutations |
| `safetyGateTest.asl` | pass | 4 assertions, 4 refutations |
