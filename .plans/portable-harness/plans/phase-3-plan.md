# Phase 3 Plan: Metasearch, CORS-Aware Fetcher & Live Data Actualization

## Goal
Build production-grade decentralized search aggregation, proxy rotation, HTML-to-markdown extraction, and freshness scoring in `packages/asl-search/`, integrated with the harness effect loop.

## Work Items

### Item 1: Multi-Query Search Aggregator & Proxy Health Rotator in ASL
- **File**: `packages/asl-search/src/engine.asl`
- **Specification**:
  - `SearchEngineConfig`: `endpoints: (List Str)`, `active-index: I64`, `timeout-ms: I64`, `min-score: F64`
  - `select-best-endpoint`: selects lowest-latency active proxy node from pool.
  - `merge-and-dedup`: combines search results from multiple queries, deduplicates by URL hash, sorts by relevance score.
- **Gate**: `.venv/bin/python checker/gate.py && .venv/bin/python tools/native_parser.py packages/asl-search/src/engine.asl`

### Item 2: Content Chunking, Markdown Extraction & Freshness Scoring in ASL
- **File**: `packages/asl-search/src/actualize.asl`
- **Specification**:
  - `dfs DocumentChunk`: `doc-id: Str`, `chunk-index: I64`, `text: Str`, `token-estimate: I64`
  - `dfs FreshnessProfile`: `published-at: I64`, `crawled-at: I64`, `age-hours: F64`, `freshness-weight: F64`
  - `compute-freshness-weight`: calculates exponential decay weight based on publication timestamp.
  - `chunk-markdown`: splits clean markdown text into windowed segments bounded by token ceiling.
- **Gate**: `.venv/bin/python checker/gate.py && .venv/bin/python tools/native_parser.py packages/asl-search/src/actualize.asl`

### Item 3: Tri-Modal Search & Fetch Bridge
- **File**: `packages/asl-harness/bridges/search_adapter.ts`
- **Specification**:
  - Implements SearXNG JSON-API queries.
  - Tri-modal fetch strategy:
    1. Extension mode: uses Chrome extension background script permissions to bypass CORS.
    2. CORS-proxy mode: falls back to configured CORS gateway.
    3. Direct Node fetch: performs native HTTP request with user-agent rotation.
  - Converts HTML responses to lightweight Markdown using native regex / Readability parser.
- **Gate**: `npx tsc --noEmit packages/asl-harness/bridges/search_adapter.ts`

### Item 4: Integration Test Suite
- **File**: `packages/asl-search/tests/test_search_actualize.ts`
- **Specification**:
  - Tests multi-query aggregation with synthetic SearXNG payloads.
  - Verifies URL deduplication, freshness scoring, and markdown chunking boundaries.
- **Gate**: `npx tsx packages/asl-search/tests/test_search_actualize.ts`
