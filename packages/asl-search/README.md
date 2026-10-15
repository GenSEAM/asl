# asl-search (package `aslSearch`)

ASL functions that build search URLs and `curl` argument vectors for several providers, clean and merge results, and format them as numbered Markdown context; plus a Common Crawl client that runs `curl` and reads WARC records.

- `engine.asl`: `buildSearchUrl`, `makeCurlCommand`, `buildProviderCurlCmd`, `cleanUrl` (drops `utm_*`, `ref`, `fbclid`, `gclid`), `mergeSearchResults`, `formatResultMarkdown`, `formatRagContext`, `isProxyHealthy`, `selectHealthyProxies`, `generateBipolarQuery`. Engines: DuckDuckGo, Wikipedia, GitHub, arXiv, HackerNews, Brave, Google, Tavily. These build commands and text; running the request is left to the caller.
- `config.asl`: `resolveSearchConfig`, `getEngineKey`, `isEngineConfigured?` (keys from the environment and `.asl.config.asn`).
- `router.asl`, `quota.asl`, `transport.asl`: engine cascade with quota failover, quota headers, transport choice by runtime.
- `hybrid.asl`: reciprocal-rank merge and URL deduplication. `ecosystems.asl`: package registry URLs. `research.asl`: research plans, query lists and report formatting.
- `commonCrawl.asl`: `ccLatestCrawl!`, `ccLookup!` (CDX index), `ccFetch!` (ranged WARC fetch, gunzip through `asl-zip`, `ccParseWarc`), `ccQuoteInPage?`. These run `curl` and need network access.
- `commonCrawlCli.asl`: `main` with the commands `quote <url> <quote>` and `lookup <urlPattern> [limit]`, run as `asl/host/out/asl-host run asl/packages/asl-search/src/commonCrawlCli.asl lookup ...`.

Module names use the prefix `aslWebApiSearch/`, and `manifest.asn` lists the same 10 modules under that prefix (the package itself is named `aslSearch`). All 10 files in `src/` pass `asl/host/out/asl-host check` (2026-10-14).

## Example
```asl
(module example/searchUrl :x [arxivUrl strippedUrl] :i [(aslWebApiSearch/engine :a eng)])

fn arxivUrl -> Str
  (eng/buildSearchUrl "arxiv" "reasoning models" 5)

fn strippedUrl -> Str
  (eng/cleanUrl "https://github.com/GenSEAM/asl?utm_source=x&ref=news")
```
On the host (2026-10-14), `arxivUrl` returns `https://export.arxiv.org/api/query?search_query=all:reasoning%20models&start=0&max_results=5` and `strippedUrl` returns `https://github.com/GenSEAM/asl`. Outside this repository, name the package in the importing project's `.asl.config.asn`: `(:dependencies ((aslWebApiSearch :path "/path/to/asl/packages/asl-search")))`.

## Modules and exports

From the `:x` list in each module header under `src/` (2026-10-14): 10 modules, 94 exported names. Long lists are cut at 18 names; the header of each file has the full list.

- `aslWebApiSearch/commonCrawl` (`src/commonCrawl.asl`, 14): `CcCapture`, `CcRecord`, `ccByteTable`, `ccLatestCrawl!`, `ccLookup!`, `ccBuildLookupArgs`, `ccRunCurl!`, `rfc3986Encode`, `ccParseCdxLines`, `ccFetchRaw!`, `ccGunzip!`, `ccParseWarc`, `ccFetch!`, `ccQuoteInPage?`.
- `aslWebApiSearch/commonCrawlCli` (`src/commonCrawlCli.asl`, 14): `main`, `chooseNewestCapture`, `chooseNewestCaptureForUrl`, `filterExactUrl`, `formatQuoteReceipt`, `formatCaptureLine`, `formatCaptureError`, `escapeAsn`, `QuoteLookupPlan`, `quoteLookupPlan`, `selectQuoteCapture`, `parseLookupLimit`, `executeLookupCdx!`, `runLookup!`.
- `aslWebApiSearch/config` (`src/config.asl`, 5): `SearchConfig`, `resolveSearchConfig`, `getEngineKey`, `makeDefaultSearchConfig`, `isEngineConfigured?`.
- `aslWebApiSearch/ecosystems` (`src/ecosystems.asl`, 8): `PackageInfo`, `PackageEcosystem`, `DeepLinkTarget`, `buildEcosystemUrl`, `buildPackageCurlCmd`, `formatPackageMarkdown`, `formatEcosystemRag`, `createDeepTargets`.
- `aslWebApiSearch/engine` (`src/engine.asl`, 17): `ProxyState`, `ProxyNode`, `SearchEngine`, `SearchQuery`, `SearchResult`, `CurlCommand`, `BipolarQuery`, `isProxyHealthy`, `selectHealthyProxies`, `buildSearchUrl`, `makeCurlCommand`, `buildProviderCurlCmd`, `cleanUrl`, `mergeSearchResults`, `formatResultMarkdown`, `formatRagContext`, `generateBipolarQuery`.
- `aslWebApiSearch/hybrid` (`src/hybrid.asl`, 4): `calculateRrfScore`, `deduplicateSerpResults`, `mergeSerpStreams`, `rankSerpResults`.
- `aslWebApiSearch/quota` (`src/quota.asl`, 8): `EngineQuota`, `QuotaTier`, `QuotaTracker`, `inspectEngineQuota`, `parseQuotaHeaders`, `isQuotaAvailable?`, `trackRequest`, `makeQuotaTracker`.
- `aslWebApiSearch/research` (`src/research.asl`, 14): `ResearchPlan`, `SynthesizedFact`, `UnifiedResearchReport`, `makeResearchPlan`, `makeSynthesizedFact`, `makeResearchReport`, `formatResearchReport`, `formatFactAsn`, `formatResearchReportAsn`, `formatResearchTriageAsn`, `extractKeyFacts`, `buildResearchQueries`, `classifySourceKind`, `deriveVerificationStatus`.
- `aslWebApiSearch/router` (`src/router.asl`, 4): `SearchRoutingDecision`, `isOpenEngine?`, `selectEngineCascade`, `routeSearchQuery`.
- `aslWebApiSearch/transport` (`src/transport.asl`, 6): `RuntimeKind`, `TransportStrategy`, `resolveRuntimeStrategy`, `buildTransportFetchCmd`, `isCorsRestricted?`, `isOfflineTransport?`.

## Tests

Measured 2026-10-14 with the stage-0 host, run from the directory that contains the `asl/` checkout:

```sh
asl/host/out/asl-host test asl/packages/asl-search/tests/<file>.asl
```

5 of 7 test files exit 0 (315 assertions and refutations pass in those files).

| File | Result | Detail |
|---|---|---|
| `argvTest.asl` | **fail** | spawns `bin/asl test ...`, which does not exist |
| `commonCrawlCliTest.asl` | pass | 79 assertions, 18 refutations |
| `commonCrawlLiveTest.asl` | **fail** | needs network access to Common Crawl; here the proxy refused it (`CONNECT tunnel failed, response 403`) |
| `commonCrawlTest.asl` | pass | 52 assertions, 10 refutations |
| `quotaTest.asl` | pass | 66 assertions |
| `researchPipelineTest.asl` | pass | 59 assertions, 3 refutations |
| `searchTest.asl` | pass | 20 assertions, 8 refutations |
