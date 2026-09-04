# Phase 1 Plan: Decoupled ASL Context Engine & Multi-Format RAG Extractor (`packages/asl-context`)

## Goal
Implement a standalone, pure AgentScript package `packages/asl-context` that decouples context extraction, HTML boilerplate stripping, multi-format parsing, chunking, and RAG context compression from `asl-search`. Zero Python runtime dependencies.

## Acceptance Criterion
`.venv/bin/python checker/gate.py && .venv/bin/python ./agentscript test packages/asl-context/tests/context_test.asl`

## Work Items

### Item 1: Package Manifest & Scaffolding
- **Files**: `packages/asl-context/asl.json`, `packages/asl-context/README.md`
- **Specification**:
  - Name: `@genseam/asl-context`
  - Entry: `src/context.asl`
  - Targets: `wasm`, `ts`, `py`
  - Documentation of schemas and exported APIs
- **Failing Gate**: `test -f packages/asl-context/asl.json`

### Item 2: Core Data Types & HTML Boilerplate Stripper
- **File**: `packages/asl-context/src/context.asl`
- **Specification**:
  - `ExtractedDoc`: `title: Str`, `content: Str`, `format: Str`, `source: Str`, `char-count: I64`
  - `ContextChunk`: `id: Str`, `content: Str`, `index: I64`, `char-count: I64`, `source: Str`
  - `decode-html-entities`: replaces `&amp;`, `&lt;`, `&gt;`, `&quot;`, `&#39;`, `&apos;`, `&nbsp;`
  - `strip-enclosed`: recursively removes substrings enclosed between open and close delimiters
  - `strip-tag-blocks`: removes entire blocks (`<script>`, `<style>`, `<nav>`, `<header>`, `<footer>`)
  - `strip-html-comments`: removes `<!-- ... -->`
  - `strip-html-tags`: converts block tag boundaries to spaces/newlines, removes `<...>`
  - `normalize-whitespace`: collapses consecutive spaces and blank lines
  - `clean-html`: composite pipeline returning clean article text
- **Failing Gate**: `.venv/bin/python -c "from checker.gate import check_file, package_roots; from pathlib import Path; p = Path('packages/asl-context/src/context.asl'); assert p.is_file()"`

### Item 3: Multi-Format Extractors
- **File**: `packages/asl-context/src/context.asl`
- **Specification**:
  - `extract-html`: extracts title and article text from HTML source
  - `extract-markdown`: strips markdown syntax, code fences, link URLs, keeping clean text
  - `extract-plaintext`: normalizes raw text paragraphs and control characters
  - `extract-json-kv`: extracts primary content from common JSON fields (`content`, `text`, `title`, `snippet`, `body`)
  - `extract-xml-atom`: extracts title and summary/content from Atom/RSS/XML feeds
  - `extract-context`: polymorphic format dispatcher based on format string
- **Failing Gate**: `.venv/bin/python -c "from checker.gate import check_file, package_roots; from pathlib import Path; p = Path('packages/asl-context/src/context.asl'); assert not check_file(p, package_roots(p))"`

### Item 4: Sliding-Window Chunking & RAG Context Compression
- **File**: `packages/asl-context/src/context.asl`
- **Specification**:
  - `chunk-text`: sliding-window chunker with safe `(max 1 (- max-chars overlap-chars))` step
  - `chunk-doc`: chunks `ExtractedDoc` into `(List ContextChunk)`
  - `format-chunk-markdown`: renders `[Chunk i](source): content`
  - `format-context-rag`: consolidated markdown prompt context block with token estimation
  - `format-docs-rag`: formats multiple extracted docs into indexed prompt context
- **Failing Gate**: `.venv/bin/python -c "from checker.gate import check_file, package_roots; from pathlib import Path; p = Path('packages/asl-context/src/context.asl'); diags = check_file(p, package_roots(p)); assert diags == []"`

### Item 5: Comprehensive Unit Test Suite
- **File**: `packages/asl-context/tests/context_test.asl`
- **Specification**:
  - `test-decode-entities`: tests entity unescaping
  - `test-html-cleaner`: tests script/style removal and text extraction
  - `test-multi-format`: tests markdown, json, xml extractors
  - `test-chunking`: tests sliding window chunk step and boundaries
  - `test-rag-format`: tests consolidated prompt context markdown
  - `run-tests`: runs all test cases and returns `Bool`
- **Failing Gate**: `.venv/bin/python ./agentscript test packages/asl-context/tests/context_test.asl`

