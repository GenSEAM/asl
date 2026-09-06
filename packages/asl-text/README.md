# @genseam/asl-text (Pure AgentScript Text & Extraction Engine)

High-performance text extraction, HTML/DOM parsing and boilerplate stripping, entity decoding, multi-format normalization, sliding-window chunking, and canonical ASN structuring in pure AgentScript (ASL).

## Features
- **Zero Foreign Runtime:** 100% written in pure AgentScript (`.asl`). Compiles to WebAssembly, TypeScript, and Rust.
- **HTML Boilerplate Stripping:** Recursively removes `<script>`, `<style>`, `<nav>`, `<header>`, `<footer>`, comments (`<!-- ... -->`), and non-content tags.
- **Entity Unescaping:** Fast unescaping of HTML entities (`&amp;`, `&lt;`, `&gt;`, `&quot;`, `&#39;`, `&apos;`, `&nbsp;`).
- **Multi-Format Extraction:** Clean, normalized text extraction from HTML, Markdown, Plaintext, JSON Key-Value payloads, and XML/Atom feeds.
- **Sliding-Window Chunking:** Safe window stepping with bounded overlap for document chunking.
- **Canonical ASN Structuring:** Encodes extracted documents and chunks into compact ASN S-expressions (`(:doc ...)`, `(:chunk ...)`).
- **RAG Prompt Context Compression:** Token-efficient markdown context generation for direct LLM injection.

## Module Exports (`asl-text/text`)
- `ExtractedDoc`, `ContextChunk`
- `decode-html-entities [(text Str)] -> Str`
- `clean-html [(html Str)] -> Str`
- `extract-html [(raw-html Str) (source Str)] -> ExtractedDoc`
- `extract-markdown [(raw-md Str) (source Str)] -> ExtractedDoc`
- `extract-plaintext [(raw-txt Str) (source Str)] -> ExtractedDoc`
- `extract-json-kv [(raw-json Str) (source Str)] -> ExtractedDoc`
- `extract-xml-atom [(raw-xml Str) (source Str)] -> ExtractedDoc`
- `extract-context [(raw-content Str) (format Str) (source Str)] -> ExtractedDoc`
- `chunk-text [(text Str) (max-chars I64) (overlap-chars I64) (source Str)] -> (List ContextChunk)`
- `chunk-doc [(doc ExtractedDoc) (max-chars I64) (overlap-chars I64)] -> (List ContextChunk)`
- `doc-to-asn [(doc ExtractedDoc)] -> Str`
- `chunk-to-asn [(chunk ContextChunk)] -> Str`
- `format-chunk-markdown [(chunk ContextChunk)] -> Str`
- `format-context-rag [(query Str) (chunks (List ContextChunk))] -> Str`
- `format-docs-rag [(query Str) (docs (List ExtractedDoc))] -> Str`

## License
MIT
