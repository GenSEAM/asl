# asl-gateway (package `aslGateway`)

ASL functions for an LLM gateway: credential resolution, a text inspection step for model output, wire headers, and record formats for sync, browser and media requests. They are pure functions; no module in the package opens a socket or serves HTTP.

## Modules (`asl/packages/asl-gateway/src`)
- `lmk.asl`: `resolveLmkProfile` picks key and base URL from, in order, UI override, local `.asl/gateway.asn`, global `~/.asl/gateway.asn`, environment, fallback; the fallback base URL is `http://127.0.0.1:8765/v1` and the model id comes from the input. `maskApiKey` masks keys; `formatLmkProfileAsn` renders a profile.
- `server.asl`: `inspectCompletionTurn` splits `<think>...</think>` text from the output (`extractThinkBlocks`) and rejects a turn when `detectEshViolation` finds a claim of a passing test or gate (words such as "test"/"gate"/"assert" with "pass"/"verif"/"clean") and the caller reports no verified execution. Also `handleSyncIngest`, `handleBrowserDispatch`, `handleMediaDispatch`.
- `wire.asl`: `formatWireHeaders` (`X-ASL-Wire-Protocol: asn/1.0`, `X-Tool-Call-Dialect: asn-sexpr`, `Accept: application/asn+sexpr, application/json`), `isToolCall?`, `isDeclarativeAsn?`, `extractToolName`, `demuxRawAsnTurn`.
- `gateway.asl`: config, token-bucket `rateLimitCheck`, `quarantineThinkingTags`, `dispatchGatewayRequest`.
- `browserGateway.asl`: browser inference and browser target descriptors, `inspectBrowserTurn`, `convertJsonToAsnToolcall`.
- `browser.asl`, `media.asl`, `sync.asl`, `omniIngress.asl`: action, media and sync record formats and receipts; ingress normalisation.

## Lifecycle families (serverless endpoints)
A `(:lifecycle :provider P :family F ...)` row in `~/.asl/gateway.asn` gives provider P's plugin a lifecycle; P's endpoints then start cold, and a request that no warm endpoint admits starts one through the spend gate (`plugin.asl` `pluginStart!`, budget `actionScaleUp`) and waits up to `coldStartMs`.
- `dispatch.asl` `LifecycleFamily`: `:name` (the row's `:family`) and `:make`, a fn of the row's props (`Map String rd/SExpr`), the provider's `UpstreamProvider` row, `UpstreamSettings` and env, returning `(Result LifecycleSpec String)`.
- `LifecycleSpec`: `:lifecycle` (`plugin.asl` `Lifecycle`: deploy, start, stop, status, each `LifecycleRequest -> (Result LifecycleStatus String)`), `:scale` (`serverless idleTimeoutSec coldStartMs`), `:startCost` (microUSD charged per allowed start), `:unit` (budget unit of that charge).
- `start` returns promptly with `warming` (the event loop is single-threaded); `status` is polled at most every 100 ms until `warm` or `down`, and not after the start's deadline. The family does not gate: the gateway gates and charges.
- Built in: `http` (`:start`, `:status`, optional `:stop` POST paths under the provider base, reply `{"state": ...}`). A provider package adds its family from a launcher outside this package: `server.asl` `mainWith args modulePath families`; asl-gateway never imports a provider package.

## Tests (2026-09-24)
Eleven files in `asl/packages/asl-gateway/tests/`. With `./bin/asl test` (lenient asl-core): `lmkTest.asl` 18, `wireTest.asl` 23, `serverTest.asl` 15, `browserGatewayTest.asl` 21 assertions, each exit 0. With `asl/host/out/asl-host test`: `lmkTest.asl` exit 0 (18 assertions); `wireTest.asl`, `serverTest.asl` and `browserGatewayTest.asl` exit 1 with 5, 8 and 12 load errors (for example `pairFirst` is not a host builtin).
