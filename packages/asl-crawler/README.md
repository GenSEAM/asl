# @genseam/asl-crawler (Parallel Stealth Web Crawler)

High-concurrency parallel stealth web crawling engine, GoogleBot/browser impersonator, and system browser detector in pure AgentScript (ASL).

## Key Capabilities
- **Parallel Crawl Pool**: In-memory concurrent request dispatcher (`make-pool`, `pool-jobs`).
- **Stealth Anti-Fingerprinting Profiles**: Realistic User-Agent, `Sec-CH-UA`, client hints, and navigation headers (`chrome-profile`, `safari-profile`).
- **GoogleBot Impersonator Mode**: Bypass restrictive paywalls and access search-optimized public pages (`googlebot-profile`).
- **System Browser Discovery**: Auto-detects locally installed Chrome, Brave, Chromium, Edge, and Safari on macOS and Linux (`macos-browsers`, `linux-browsers`).
- **CDP Headless Launch Vectors**: Generates injection-free process arguments for automated headless browser page scraping (`cdp-args`).
- **High-Performance Curl Vectors**: Compiles stealth HTTP requests into safe curl argument lists with automatic gzip/brotli compression (`curl-args`, `curl-headers`).
- **Zero Foreign Runtime**: 100% pure AgentScript (`.asl`).

## Usage
```asl
(module example/crawlerUsage
  :i [(asl-crawler/stealth :a st)
      (asl-crawler/crawler :a cr)])

;; 1. Construct GoogleBot crawl job
fn makeGoogleBotJob -> (List Str)
  (let [(profile (st/googlebot-profile))
        (job (cr/crawl-job "https://example.com" profile))
        (args (cr/curl-args job))]
    args)

;; 2. Parallel Crawl Pool
fn makeCrawlPool -> (List Any)
  (let [(pool (cr/make-pool 8 (st/chrome-profile)))
        (jobs (cr/pool-jobs pool (list "https://a.com" "https://b.com")))]
    jobs)
```

## Verification
```asn
;; Run pure ASL crawler test suite
(:test-crawler
  :do "./bin/asl test asl/packages/asl-crawler/tests/crawlerTest.asl"
  :summary "Execute parallel crawl pool, stealth profiling, and header synthesis assertions")
```

## CLI compatibility and delegation

The ASL CLI reports observed state rather than assuming a live browser session:
`status` emits `:inBrowserAgentReady :unknown`; `session <service>` emits
`:status :unverified` and exits 1 when no live session is verified. Crawl mode
`extension` is listed under `:unavailableModes`, reports that dispatch is
unavailable, and exits 2. There is no configured browser-gateway path in this
CLI. These are intentional behavior changes from the Python crawler's former
readiness/session claims and extension fallback.

Form delegation prefers `asl/packages/asl-crawler/src/crawler.asl` when that package entry exists.
`asl-forms/delegate.asl:crawlerSpawn` retains `bin/asl-crawler` as a compatibility
fallback only when the ASL package entry is missing; the legacy executable is
not fully removed.

The ASL `automate <path>` command does not execute files through a shell. ASN
actions and script contents report failure because browser-gateway dispatch is
not implemented in this CLI; there is no gateway configuration path. The prior
Python command delegated the file contents to a gateway.
