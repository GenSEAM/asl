# asl-text

ASL text utilities: HTML entity decoding and boilerplate stripping, text extraction from several formats, sliding-window chunking, ASN rendering of documents and chunks, string escaping, and an emoji scanner.

## Modules (`asl/packages/asl-text/src`)
- `text.asl` (`asl-text/text`): `ExtractedDoc`, `ContextChunk`, `decodeHtmlEntities`, `cleanHtml`, `extractHtml`, `extractMarkdown`, `extractPlaintext`, `extractJsonKv`, `extractXmlAtom`, `extractContext`, `chunkText`, `chunkDoc`, `docToAsn`, `chunkToAsn`, `formatChunkMarkdown`, `formatContextRag`, `formatDocsRag`; also clause, table and code-block extraction, `distillHtml`, `internUrls`, `sanitizeUrlTracking`, `estimateTokens`.
- `escape.asl` (`asl-text/escape`): `escapeAsnStr`, `unescapeAsnStr`, `escapeJsonStr`, `unescapeJsonStr`, `escapeShArg`, `isShSafeArg`, `escapeShCompact`.
- `string.asl` (`asl-text/string`): `starts?`, `ends?`, `has?`, `split`, `concat`, `join` and aliases.
- `emojiGuard.asl` (`asl-text/emojiGuard`): `hasRawEmoji?`, `scanLineEmoji`, `scanFileEmoji`, `auditAsnEmojis`.

## Status
- Target: compile to Wasm or C99. Today `./bin/asl build` returns `ERR_UNIMPLEMENTED` ("produces no artifact until R1").
- Tests (2026-09-24): `./bin/asl test asl/packages/asl-text/tests/textTest.asl` exits 0 (69 assertions, 10 refutations) on asl-core; `asl/host/out/asl-host test` on it exits 1 because `text.asl` calls `listTake`, which the host does not bind (`ERR_UNKNOWN_SYMBOL`).
