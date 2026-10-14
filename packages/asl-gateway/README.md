# asl-gateway (package `aslGateway`)

An LLM gateway written in ASL: an HTTP server that takes OpenAI-style chat requests and routes them to upstream providers or to local agent CLIs, with routing rules, a per-provider circuit breaker, token buckets, a spend budget, request batching, a fleet model for serverless endpoints, usage telemetry and a status cockpit page. It also holds the record formats and parsers that the rest of the workspace uses for wire headers, credentials, browser, media and sync requests.

Status (2026-10-14): 21 of the 29 files in `src/` pass `asl/host/out/asl-host check`. `src/server.asl` and `src/cliDispatch.asl` import `asl/packages/asl-cli/src/system` by path, which the host does not resolve (the declared name is `asl-cli/system`), so these modules and every module that imports them (`browserGateway`, `chat`, `dispatch`, `gateway`, `plugin`, `poolDispatch`) fail the check. Until that import is fixed the server (`server.asl serve`, `start`, `status`, `stop`) does not start.

## What the modules do
- `server.asl`: `main`/`mainWith`, with the modes `start`, `status`, `stop`, `serve`, `run`, `config`/`configCheck`/`convert`, `restart`/`update`. `serve` listens with the host builtin `tcpListen` and forwards to the upstream with `tcpConnect`. Also `inspectCompletionTurn`, which splits `<think>...</think>` text from the output (`extractThinkBlocks`) and rejects a turn when `detectEshViolation` finds a claim of a passing test or gate while the caller reports no verified execution.
- `chat.asl`, `router.asl`, `breaker.asl`, `budget.asl`, `batchPool.asl`, `poolDispatch.asl`, `dispatch.asl`, `fleet.asl`, `upstream.asl`, `usage.asl`: the request path (chat effects, route scoring, breaker state, budget gate, batching, endpoint lifecycle, upstream settings and providers, usage records).
- `config.asl`: `~/.asl/gateway.asn` parsing and validation. `cliDispatch.asl`: running local agent CLIs as providers. `plugin.asl`: the provider plugin contract (capabilities, send, health, deploy/start/stop/status lifecycle, spend gate).
- `lmk.asl`: `resolveLmkProfile` picks key and base URL from, in order, UI override, local `.asl/gateway.asn`, global `~/.asl/gateway.asn`, environment, fallback; the fallback base URL is `http://127.0.0.1:8765/v1`. `maskApiKey` masks keys.
- `wire.asl`: `formatWireHeaders` (`X-ASL-Wire-Protocol: asn/1.0`, `X-Tool-Call-Dialect: asn-sexpr`, `Accept: application/asn+sexpr, application/json`), `isToolCall?`, `extractToolName`, `demuxRawAsnTurn`, ASN reply helpers.
- `cockpit.asl`, `getRoutes.asl`, `omniApi.asl`, `localTime.asl`: the cockpit HTML page, GET routes, the omni API and local-time formatting from tzif/POSIX rules.
- `search.asl`, `research.asl`: web search engines (Tavily, Serper, Wikipedia, SearXNG, DuckDuckGo) over `curl`, and the research hub.
- `gateway.asl`, `browserGateway.asl`, `browser.asl`, `media.asl`, `sync.asl`: config and rate limits, browser target descriptors and turn inspection, action, media and sync record formats and receipts.
- `pyText.asl`, `htmlEntities.asl`: Python-compatible string, JSON, URL and charset helpers used by the parity ports.

Parts of the package are ports of an earlier Python gateway: `wireParityTest.asl` and `upstreamParityTest.asl` compare against fixtures recorded from the Python original, `cockpitTest.asl` replays recorded cases, and some modules export both camelCase and snake_case names for the same function.

`manifest.asn` lists 18 of the 29 modules and a module `aslGateway` that no file declares; `breaker`, `budget`, `chat`, `cliDispatch`, `config`, `dispatch`, `fleet`, `plugin`, `router`, `upstream` and `usage` are missing from it.

## Lifecycle families (serverless endpoints)
A `(:lifecycle :provider P :family F ...)` row in `~/.asl/gateway.asn` gives provider P's plugin a lifecycle; P's endpoints then start cold, and a request that no warm endpoint admits starts one through the spend gate (`plugin.asl` `pluginStart!`, budget `actionScaleUp`) and waits up to `coldStartMs`.
- `dispatch.asl` `LifecycleFamily`: `:name` (the row's `:family`) and `:make`, a fn of the row's props (`Map String rd/SExpr`), the provider's `UpstreamProvider` row, `UpstreamSettings` and env, returning `(Result LifecycleSpec String)`.
- `LifecycleSpec`: `:lifecycle` (`plugin.asl` `Lifecycle`: deploy, start, stop, status), `:scale` (`ScaleModel`), `:startCost` (microUSD charged per allowed start), `:unit` (budget unit of that charge).
- `status` is polled at most every 100 ms until the endpoint is warm or down. The family does not gate: the gateway gates and charges.
- Built in: `http` (`httpFamily`). A provider package adds its family from a launcher outside this package through `server.asl` `mainWith args modulePath families`; asl-gateway never imports a provider package. `asl-modal` is one such provider.

## Modules and exports

From the `:x` list in each module header under `src/` (2026-10-14): 29 modules, 963 exported names. Long lists are cut at 18 names; the header of each file has the full list.

- `aslGateway/batchPool` (`src/batchPool.asl`, 17): `PoolConfig`, `PoolRequest`, `PoolBatch`, `PoolState`, `PoolError`, `PoolEvent`, `PoolAction`, `PoolStep`, `defaultPoolConfig`, `makePoolConfig`, `defaultPoolState`, `poolStep`, `poolStateQueued`, `poolStateInFlightCount`, `poolActionReplyCount`, `poolActionDispatchCount`, `poolActionScaleDownCount`.
- `aslGateway/breaker` (`src/breaker.asl`, 47): `ProviderStatus`, `BreakerState`, `BreakerEvent`, `BreakerDecision`, `BreakerStepResult`, `defaultCooldownSec`, `providerCooldownSec`, `makeBreakerState`, `defaultBreakerState`, `touchSeen`, `breakerDownFor`, `breaker_down_for`, `breakerMarkDown`, `breaker_mark_down`, `breakerClear`, `breaker_clear`, `breakerNote503`, `breaker_note_503`, and 29 more.
- `aslGateway/browser` (`src/browser.asl`, 10): `BrowserActionFrame`, `BrowserActionReceipt`, `BrowserSessionConfig`, `validateActionOp`, `formatBrowserAction`, `formatBrowserReceipt`, `createSuccessReceipt`, `createErrorReceipt`, `isActionTerminal?`, `validateActionSequence`.
- `aslGateway/browserGateway` (`src/browserGateway.asl`, 19): `BrowserInferenceTarget`, `BrowserTurnVerdict`, `BrowserTargetKind`, `BrowserTabSummary`, `BrowserTargetDescriptor`, `targetToString`, `inspectBrowserTurn`, `convertJsonToAsnToolcall`, `formatBrowserWirePayload`, `targetStealthSteel`, `targetExtensionChrome`, `targetExtensionSafari`, `targetCdpDirect`, `makeBrowserTabSummary`, `makeBrowserTargetDescriptor`, `browserTargetKindToString`, `parseBrowserTargetKind`, `formatBrowserTargetAsn`, and 1 more.
- `aslGateway/budget` (`src/budget.asl`, 31): `BudgetScope`, `Period`, `BudgetLine`, `Approval`, `Charge`, `Bucket`, `Ledger`, `Action`, `Decision`, `BudgetError`, `Candidate`, `scopeEndpoint`, `scopeProvider`, `scopeUnit`, `scopeGlobal`, `periodHour`, `periodDay`, `periodUnit`, and 13 more.
- `aslGateway/chat` (`src/chat.asl`, 48): `ChatRequest`, `gatewayOriginHeader`, `ChatWorld`, `ChatEffect`, `effRealpath`, `effIsDir`, `effClock`, `effBreakerDown`, `effBreakerDownAll`, `effBreakerEvent`, `effUsageNote`, `effUsageFallback`, `effTelemetry`, `effNoteIntent`, `effLog`, `effBucket`, `effHttp`, `effPoolHttp`, and 30 more.
- `aslGateway/cliDispatch` (`src/cliDispatch.asl`, 43): `CliUsage`, `CliParseResult`, `CliVersionInfo`, `CliPromptDir`, `DispatchOptions`, `CliProvider`, `cliProviders`, `cliProviderNamed`, `cliProviderBin!`, `cliProviderHealth!`, `defaultDispatchOptions`, `resolve_cli_bin!`, `resolveCliBin!`, `resolveCliBinFromLocations!`, `cli_versions!`, `cliVersions!`, `cli_message_text`, `cliMessageText`, and 25 more.
- `aslGateway/cockpit` (`src/cockpit.asl`, 79): `AsnVal`, `asnAtom`, `asnText`, `asnList`, `CockpitEnv`, `GatewayStatus`, `ProfileHealth`, `PoolStats`, `UsageRow`, `UsageSnapshot`, `CockpitState`, `KnownRed`, `KnownRedRow`, `GatesRecord`, `CalibrationRow`, `Calibration`, `TaskRow`, `TasksData`, and 61 more.
- `aslGateway/config` (`src/config.asl`, 85): `AsnScalar`, `scalarBool`, `scalarInt`, `scalarFloat`, `scalarStr`, `scalarToString`, `GatewayParams`, `emptyGatewayParams`, `mergeParams`, `GatewayRoute`, `GatewayProfile`, `GatewayModel`, `GatewayProvider`, `GatewayPool`, `GatewayUpstream`, `GatewayEntry`, `GatewayResolvedEntry`, `entryResolved`, and 67 more.
- `aslGateway/dispatch` (`src/dispatch.asl`, 38): `Slot`, `Serverless`, `Wiring`, `RouteHint`, `DecisionRow`, `Plan`, `planSend`, `planReject`, `planWait`, `LifecycleSpec`, `LifecycleFamily`, `StartOutcome`, `startOk`, `startRefused`, `SlotReady`, `readyNow`, `readyLater`, `readyGone`, and 20 more.
- `aslGateway/fleet` (`src/fleet.asl`, 20): `AdmissionMode`, `Lifecycle`, `Endpoint`, `State`, `FleetError`, `Event`, `Admission`, `ScaleDecision`, `RejectReason`, `Sample`, `Ring`, `makeRing`, `emptyState`, `transition`, `admit`, `decide`, `spillover`, `expectedWarmCost`, and 2 more.
- `aslGateway/gateway` (`src/gateway.asl`, 7): `GatewayConfig`, `GatewayResponse`, `makeGatewayConfig`, `rateLimitCheck`, `rateLimitCheckWithTime`, `quarantineThinkingTags`, `dispatchGatewayRequest`.
- `aslGateway/getRoutes` (`src/getRoutes.asl`, 28): `PoolRow`, `CliRow`, `BreakerRow`, `SessionRow`, `TargetRow`, `ActionQueue`, `HealthInputs`, `GetState`, `SearchRequest`, `GetOutcome`, `getRespond`, `getCockpit`, `getSearch`, `getFail`, `roleCascades`, `cockpitPath?`, `pyIntParse`, `pathRstrip`, and 10 more.
- `aslGateway/htmlEntities` (`src/htmlEntities.asl`, 2): `entityBucket`, `invalidCharrefTable`.
- `aslGateway/lmk` (`src/lmk.asl`, 7): `LmkKeySource`, `LmkProfile`, `LmkHierarchyInput`, `makeLmkProfile`, `maskApiKey`, `resolveLmkProfile`, `formatLmkProfileAsn`.
- `aslGateway/localTime` (`src/localTime.asl`, 15): `Zone`, `PosixRule`, `RuleDate`, `DstRule`, `utcZone`, `zoneLoad!`, `zoneFromTzif`, `zoneFromPosix`, `posixParse`, `localOffset`, `daysFromCivil`, `civilFromDays`, `floorSeconds`, `formatLocal`, `formatUtcTouch`.
- `aslGateway/media` (`src/media.asl`, 11): `MediaGenRequest`, `MediaGenReceipt`, `MediaQuotaLedger`, `validateMediaKind`, `validateAspectRatio`, `calculateMediaDimensions`, `formatMediaRequest`, `formatMediaReceipt`, `createMediaReceipt`, `isMediaTerminal?`, `checkQuotaAvailability`.
- `aslGateway/omniApi` (`src/omniApi.asl`, 21): `Word64`, `TargetTab`, `BrowserSession`, `BrowserTarget`, `BrowserExtension`, `SyncStore`, `TargetStore`, `ExtensionStore`, `OmniState`, `OmniReply`, `emptyOmniState`, `omniDispatch`, `omniGet`, `omniPost`, `pyStrHash`, `pyIntStr`, `reQuoted`, `reBare`, and 3 more.
- `aslGateway/plugin` (`src/plugin.asl`, 63): `PluginApi`, `Batching`, `ScaleModel`, `PriceModel`, `PluginCapabilities`, `PluginRequest`, `PluginReply`, `PluginFailure`, `LifecycleRequest`, `EndpointState`, `LifecycleStatus`, `Lifecycle`, `Plugin`, `openaiChat`, `anthropicMessages`, `cliAgent`, `custom`, `continuous`, and 45 more.
- `aslGateway/poolDispatch` (`src/poolDispatch.asl`, 18): `PoolMember`, `PoolFailure`, `poolTimedOut`, `poolRejected`, `poolUpstream`, `PoolReply`, `PoolRegistry`, `PoolOutput`, `emptyPoolRegistry`, `poolWithPlugins`, `poolLaneKey`, `poolSubmit!`, `poolAdvance!`, `poolWatch`, `poolActive?`, `poolScaleDowns`, `poolCallCount`, `failureText`.
- `aslGateway/pyText` (`src/pyText.asl`, 62): `PyErr`, `pyErr`, `pyErrText`, `byteStr`, `cpEncode`, `treeJoin`, `joinSep`, `sliceB`, `findFrom`, `findFromCi`, `lowerAsciiByte`, `cpCount`, `cpPrefix`, `cpSlice`, `cpLenAt`, `cpList`, `isPySpace`, `pyStrip`, and 44 more.
- `aslGateway/research` (`src/research.asl`, 36): `asnAtom`, `asnRead`, `asnProps`, `asnScalar`, `asnText`, `asnRepr`, `classifySourceKind`, `extractOutermostSexpr`, `stripTagsAndWhitespace`, `extractHtmlTables`, `extractHtmlCodeBlocks`, `isSpaShell`, `isWafChallenge`, `fetchReq`, `fetchResult`, `fetchSinglePage!`, `parallelCrawlDistill!`, `researchPrompt`, and 18 more.
- `aslGateway/router` (`src/router.asl`, 16): `Candidate`, `Rule`, `Profile`, `Request`, `ModelCalibration`, `EndpointState`, `ScoreParts`, `Decision`, `RouteDecision`, `RouterError`, `route`, `parseRules`, `score`, `replay`, `mergeSampling`, `matches`.
- `aslGateway/search` (`src/search.asl`, 57): `Bucket`, `HubState`, `newHubState`, `mkHub`, `hubWithNow`, `hubSleep!`, `hubNote`, `hubCliCall`, `hubStderr`, `hubWithBreaker`, `hubWithBuckets`, `HttpReq`, `HttpResult`, `httpResp`, `httpFail`, `curlConfig`, `curlChildEnv`, `parseCurlOutput`, and 39 more.
- `aslGateway/server` (`src/server.asl`, 15): `GatewayTurnVerdict`, `Launch`, `GatewayLoop`, `linkOpen!`, `linkSend!`, `extractThinkBlocks`, `detectEshViolation`, `inspectCompletionTurn`, `handleSyncIngest`, `handleBrowserDispatch`, `handleMediaDispatch`, `gatewayHostPath!`, `main!`, `main`, `mainWith`.
- `aslGateway/sync` (`src/sync.asl`, 14): `ProjectSync`, `ResearchSync`, `ChannelSync`, `AssetSync`, `SyncReceipt`, `computeContentHash`, `formatProjectSync`, `formatResearchSync`, `formatChannelSync`, `formatAssetSync`, `formatSyncReceipt`, `createSyncReceipt`, `reconcileSync`, `isProjectComplete?`.
- `aslGateway/upstream` (`src/upstream.asl`, 91): `UpstreamSettings`, `UpstreamEndpoint`, `TokenBucket`, `BucketStep`, `bucketAcquired`, `bucketRefused`, `bucketWait`, `BucketRegistry`, `RoleTokenPolicy`, `UpstreamRequest`, `UpstreamResponse`, `UpstreamFailure`, `toolAbsent`, `transportFailure`, `httpFailure`, `protocolFailure`, `joinAll`, `replaceAll`, and 73 more.
- `aslGateway/usage` (`src/usage.asl`, 29): `GatewayStatus`, `pyTruthy?`, `pyStr`, `pyRound3`, `jsonDedup`, `usageInit`, `usageTokens`, `usageNote`, `usageFallback`, `usageHttpError`, `usageException`, `usageAgyFallback`, `usageAsn`, `usageRestoreParse`, `usageRestoreApply`, `usageRestore!`, `wordRanges`, `nfkcBadNetloc`, and 11 more.
- `aslGateway/wire` (`src/wire.asl`, 34): `formatWireHeaders`, `isToolCall?`, `isDeclarativeAsn?`, `extractToolName`, `formatToolCallFrame`, `demuxRawAsnTurn`, `findBalancedParen`, `asnEscape`, `asn_escape`, `isBalancedAsnForm?`, `isBalancedAsnForm`, `is_balanced_asn_form`, `asnNumber`, `asn_number`, `asnNumberOpt`, `wantsAsn?`, `wantsAsn`, `wants_asn`, and 16 more.

## Tests

Measured 2026-10-14 with the stage-0 host, run from the directory that contains the `asl/` checkout:

```sh
asl/host/out/asl-host test asl/packages/asl-gateway/tests/<file>.asl
```

20 of 36 test files exit 0 (1949 assertions and refutations pass in those files).

| File | Result | Detail |
|---|---|---|
| `batchPoolTest.asl` | pass | 30 assertions |
| `breakerTest.asl` | pass | 86 assertions, 23 refutations |
| `browserGatewayTest.asl` | **fail** | load error: its imports reach `src/server.asl` or `src/cliDispatch.asl`, which import `asl/packages/asl-cli/src/system` by path; the host resolves only the declared name `asl-cli/system` |
| `browserTargetTest.asl` | **fail** | load error: its imports reach `src/server.asl` or `src/cliDispatch.asl`, which import `asl/packages/asl-cli/src/system` by path; the host resolves only the declared name `asl-cli/system` |
| `browserTest.asl` | pass | 28 assertions |
| `budgetTest.asl` | pass | 62 assertions |
| `chatParityTest.asl` | **fail** | load error: its imports reach `src/server.asl` or `src/cliDispatch.asl`, which import `asl/packages/asl-cli/src/system` by path; the host resolves only the declared name `asl-cli/system` |
| `cliDispatchTest.asl` | **fail** | load error: its imports reach `src/server.asl` or `src/cliDispatch.asl`, which import `asl/packages/asl-cli/src/system` by path; the host resolves only the declared name `asl-cli/system` |
| `cliPromptFailureTest.asl` | **fail** | load error: its imports reach `src/server.asl` or `src/cliDispatch.asl`, which import `asl/packages/asl-cli/src/system` by path; the host resolves only the declared name `asl-cli/system` |
| `cockpitHandlerTest.asl` | pass | 305 assertions |
| `cockpitTest.asl` | **fail** | 5 of 103 replay cases fail; all 5 are permission-denied cases (`krPermission`, `gatesPermission`, `tasksListPermission`, `tasksFilePermission`, `memDecisionsPermission`), and this run was as root, which ignores file permissions |
| `configTest.asl` | pass | 82 assertions, 44 refutations |
| `dispatchTest.asl` | **fail** | load error: its imports reach `src/server.asl` or `src/cliDispatch.asl`, which import `asl/packages/asl-cli/src/system` by path; the host resolves only the declared name `asl-cli/system` |
| `fleetTest.asl` | pass | 52 assertions |
| `gatewayCliTest.asl` | **fail** | first check fails: it expects `PATH=<its temp dir> command -v python3` to exit 1, and on this machine it did not |
| `gatewayTest.asl` | **fail** | load error: its imports reach `src/server.asl` or `src/cliDispatch.asl`, which import `asl/packages/asl-cli/src/system` by path; the host resolves only the declared name `asl-cli/system` |
| `getRoutesTest.asl` | pass | 280 assertions |
| `leonWireAcceptanceTest.asl` | **fail** | load error: its imports reach `src/server.asl` or `src/cliDispatch.asl`, which import `asl/packages/asl-cli/src/system` by path; the host resolves only the declared name `asl-cli/system` |
| `lmkTest.asl` | pass | 18 assertions |
| `localTimeTest.asl` | pass | 11 assertions |
| `mediaTest.asl` | pass | 30 assertions |
| `noConfigTest.asl` | **fail** | starts `src/server.asl serve`, which fails to load (path import `asl/packages/asl-cli/src/system` in `src/server.asl` and `src/cliDispatch.asl`) |
| `ollamaProviderAcceptanceTest.asl` | pass | 8 assertions |
| `omniApiParityTest.asl` | pass | 254 assertions |
| `omniProtocolTest.asl` | **fail** | load error: its imports reach `src/server.asl` or `src/cliDispatch.asl`, which import `asl/packages/asl-cli/src/system` by path; the host resolves only the declared name `asl-cli/system` |
| `pluginTest.asl` | **fail** | load error: its imports reach `src/server.asl` or `src/cliDispatch.asl`, which import `asl/packages/asl-cli/src/system` by path; the host resolves only the declared name `asl-cli/system` |
| `poolDispatchTest.asl` | **fail** | starts `src/server.asl`, which fails to load (path import `asl/packages/asl-cli/src/system` in `src/server.asl` and `src/cliDispatch.asl`) |
| `profileAcceptanceTest.asl` | pass | 35 assertions |
| `profileParityTest.asl` | pass | 335 assertions |
| `routerTest.asl` | pass | 53 assertions |
| `searchResearchParityTest.asl` | pass | 70 assertions |
| `serverTest.asl` | **fail** | load error: its imports reach `src/server.asl` or `src/cliDispatch.asl`, which import `asl/packages/asl-cli/src/system` by path; the host resolves only the declared name `asl-cli/system` |
| `syncTest.asl` | pass | 23 assertions |
| `upstreamParityTest.asl` | **fail** | 520 of 521 fixture cases match; `zsh_unreadable` fails because, run as root, the "unreadable" `.zshenv` is readable |
| `wireParityTest.asl` | pass | 88 assertions, 9 refutations |
| `wireTest.asl` | pass | 23 assertions |
