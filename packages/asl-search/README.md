# asl-search (package `aslSearch`)

ASL functions that build search URLs and curl argument vectors for several providers, clean and merge results, and format them as numbered Markdown context. They produce commands and text; running the request is left to the caller.

Module names in the source use the prefix `aslWebApiSearch/` (for example `aslWebApiSearch/engine`); `manifest.asn` lists them as `asl-search/...`.

## Modules (`asl/packages/asl-search/src`)
- `engine.asl`: `buildSearchUrl`, `makeCurlCommand`, `buildProviderCurlCmd`, `cleanUrl` (drops `utm_*`, `ref`, `fbclid`, `gclid`), `mergeSearchResults`, `formatResultMarkdown`, `formatRagContext`, `isProxyHealthy`, `selectHealthyProxies`, `generateBipolarQuery`. Engines: DuckDuckGo, Wikipedia, GitHub, arXiv, HackerNews, Brave, Google, Tavily.
- `config.asl`: `resolveSearchConfig`, `getEngineKey`, `isEngineConfigured?` (keys from the environment and `.asl.config.asn`).
- `router.asl`, `quota.asl`, `transport.asl`: engine cascade with quota failover, quota headers, transport choice by runtime.
- `hybrid.asl`: reciprocal-rank merge and URL deduplication. `ecosystems.asl`: package registry URLs. `research.asl`: research plans, query lists and report formatting.

## Example
```asl
(module example/searchUrl :x [arxivUrl strippedUrl] :i [(aslWebApiSearch/engine :a eng)])

fn arxivUrl -> Str
  (eng/buildSearchUrl "arxiv" "reasoning models" 5)

fn strippedUrl -> Str
  (eng/cleanUrl "https://github.com/GenSEAM/asl?utm_source=x&ref=news")
```
On the stage-0 host (2026-09-24), `arxivUrl` returns `https://export.arxiv.org/api/query?search_query=all:reasoning%20models&start=0&max_results=5` and `strippedUrl` returns `https://github.com/GenSEAM/asl`. The import resolves from a file inside the workspace (a `.asl.config.asn` above it).

## Tests (2026-09-24)
`./bin/asl test asl/packages/asl-search/tests/searchTest.asl` exits 0 (21 assertions, 9 refutations), and `asl/host/out/asl-host test` on the same file exits 0 with the same counts.
