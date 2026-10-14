# asl-crawler (package `aslCrawler`)

ASL functions for fetching web pages: crawl jobs and pools that build `curl` argument lists (`crawler`), browser-like and Googlebot request header profiles (`stealth`), local Chrome/Brave/Edge/Chromium/Safari candidate paths for macOS and Linux and their CDP launch arguments (`browserDetector`), generated JavaScript for an in-page agent (`inBrowserAgent`), mouse and scroll trajectories (`kinetics`), automation action and receipt records (`automation`) and service session presets (`session`). Fetching goes through `asl-proc` (`fetchCurl!`, `fetchStealthBrowser!`, `runArgv!`); HTML distillation uses `asl-text`.

`src/crawler.asl` exports `main`. Run with no arguments it prints:

```text
Usage: crawler <crawl|tiktok|automate|agent|status|session> [args...]
  crawl <url> [--mode auto|extension|patchright|staticHttp|cloudProxy] [--distill asn|text|raw] [--inject-agent] [--target <id>|--browser <family>]
```

On 2026-10-14 `asl/host/out/asl-host run asl/packages/asl-crawler/src/crawler.asl status` printed `:extensionActive :unverified`, `:inBrowserAgentReady :unknown`, `:supportedModes [:patchright :staticHttp :cloudProxy :auto :extension]`, an empty `:unavailableModes` list, and a note that extension, target, automation and media-watch actions dispatch through the browser gateway.

`asl-forms/delegate.asl` (`crawlerSpawn`) runs `asl/packages/asl-crawler/src/crawler.asl` when that file exists and otherwise falls back to an `asl-crawler` executable in its bin directory. There is no `bin/asl-crawler` in this repository; three test files still call it or `bin/asl` (see Tests).

Module names use the prefix `aslCrawler/`; `manifest.asn` lists the same 7 modules. All 7 files in `src/` pass `asl/host/out/asl-host check` (2026-10-14).

## Example

Checked on the host on 2026-10-14 (the importing project names the package in its `.asl.config.asn`: `(:dependencies ((aslCrawler :path "/path/to/asl/packages/asl-crawler")))`):

```asl
(module example/crawlerUsage :x [runTests] :i [(aslCrawler/stealth :a st) (aslCrawler/crawler :a cr)])

fn runTests -> Bool
  (let [(args (cr/curlArgs (cr/crawlJob "https://example.com" (st/googlebotProfile))))]
    (do (assert (listContains? args "https://example.com") "the URL is one curl argument") true))

## Modules and exports

From the `:x` list in each module header under `src/` (2026-10-14): 7 modules, 125 exported names. Long lists are cut at 18 names; the header of each file has the full list.

- `aslCrawler/automation` (`src/automation.asl`, 17): `AutomationAction`, `AutomationReceipt`, `MediaMetadataReceipt`, `makeClickAction`, `makeTypeAction`, `makeScrollAction`, `makeNavigateAction`, `makeWatchMediaAction`, `makeTikTokExtractAction`, `formatActionAsn`, `makeAutomationReceipt`, `makeFailedReceipt`, `makeMediaMetadataReceipt`, `formatReceiptAsn`, `formatMediaMetadataAsn`, `simulateActionExecution`, `isValidActionOp?`.
- `aslCrawler/browserDetector` (`src/browserDetector.asl`, 14): `BrowserKind`, `BrowserCandidate`, `kindChrome`, `kindBrave`, `kindEdge`, `kindSafari`, `kindChromium`, `makeCandidate`, `macosBrowsers`, `linuxBrowsers`, `cdpArgs`, `getMacosCandidates`, `getLinuxCandidates`, `buildCdpLaunchArgs`.
- `aslCrawler/crawler` (`src/crawler.asl`, 43): `CrawlJob`, `CrawlResult`, `CrawlPool`, `crawlJob`, `makeCrawlJob`, `makePool`, `poolJobs`, `crawlOk`, `crawlErr`, `statusOk?`, `curlArgs`, `crawlDoc`, `crawlAsn`, `crawlDistilledAsn`, `isSpaShell?`, `makeSuccessResult`, `makeFailureResult`, `isSuccessfulStatus`, and 25 more.
- `aslCrawler/inBrowserAgent` (`src/inBrowserAgent.asl`, 8): `InBrowserAgentConfig`, `makeDefaultAgentConfig`, `generateStealthEvasionScript`, `generateDomDistillerScript`, `generateKineticExecutorScript`, `generateBehavioralNoiseScript`, `generateInBrowserAgentBootstrap`, `formatAgentStatusAsn`.
- `aslCrawler/kinetics` (`src/kinetics.asl`, 13): `Point`, `KineticsProfile`, `BehavioralNoiseConfig`, `makePoint`, `defaultKineticsProfile`, `makeDefaultNoiseConfig`, `evaluateBezier`, `computeFittsTime`, `computeScrollDecay`, `computeTremorJitter`, `generateKineticTrajectory`, `computeOvershootPoint`, `generateErraticTrajectory`.
- `aslCrawler/session` (`src/session.asl`, 10): `ServicePreset`, `SessionState`, `makeServicePreset`, `getServicePreset`, `makeSessionState`, `formatSessionAsn`, `isSessionValid?`, `BrowserSessionHandle`, `makeBrowserSessionHandle`, `formatBrowserSessionHandleAsn`.
- `aslCrawler/stealth` (`src/stealth.asl`, 20): `StealthKind`, `StealthProfile`, `stealthGooglebot`, `stealthChrome`, `stealthSafari`, `stealthMobile`, `googlebotProfile`, `chromeProfile`, `safariProfile`, `curlHeaders`, `makeGooglebotProfile`, `makeChromeProfile`, `makeSafariProfile`, `makeProfile`, `buildHeaders`, `formatCurlHeaderArgs`, `ExtensionRelayMessage`, `ExtensionRelayResponse`, and 2 more.

## Tests

Measured 2026-10-14 with the stage-0 host, run from the directory that contains the `asl/` checkout:

```sh
asl/host/out/asl-host test asl/packages/asl-crawler/tests/<file>.asl
```

6 of 9 test files exit 0 (222 assertions and refutations pass in those files).

| File | Result | Detail |
|---|---|---|
| `argvTest.asl` | **fail** | spawns `bin/asl`, which does not exist |
| `automationTest.asl` | pass | 46 assertions, 7 refutations |
| `cliTest.asl` | **fail** | runs `./bin/asl-crawler`, which does not exist |
| `crawlerCliRegressionTest.asl` | **fail** | runs `bin/asl crawler`, which does not exist |
| `crawlerTest.asl` | pass | 18 assertions, 13 refutations |
| `inBrowserAgentTest.asl` | pass | 43 assertions, 10 refutations |
| `kineticsTest.asl` | pass | 34 assertions, 4 refutations |
| `retiredPathsTest.asl` | pass | 9 assertions, 5 refutations |
| `stealthCrawlerTest.asl` | pass | 33 assertions |
