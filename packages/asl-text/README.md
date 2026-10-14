# asl-text

ASL text utilities: HTML entity decoding and boilerplate stripping, text extraction from several formats, sliding-window chunking, clause, table and code-block extraction, ASN rendering of documents and chunks, string escaping for ASN, JSON and shell, and an emoji scanner. All functions are pure; none reads or writes files.

- `text.asl` (`asl-text/text`): `ExtractedDoc`, `ContextChunk`, `decodeHtmlEntities`, `cleanHtml`, `extractHtml`, `extractMarkdown`, `extractPlaintext`, `extractJsonKv`, `extractXmlAtom`, `extractContext`, `chunkText`, `chunkDoc`, `docToAsn`, `chunkToAsn`, `formatChunkMarkdown`, `formatContextRag`, `formatDocsRag`, `distillHtml`, `internUrls`, `sanitizeUrlTracking`, `estimateTokens`.
- `escape.asl` (`asl-text/escape`): `escapeAsnStr`, `unescapeAsnStr`, `escapeJsonStr`, `unescapeJsonStr`, `escapeShArg`, `isShSafeArg`, `escapeShCompact`.
- `string.asl` (`asl-text/string`): `starts?`, `ends?`, `has?`, `split`, `concat`, `join` and their `txt`-prefixed aliases.
- `emojiGuard.asl` (`asl-text/emojiGuard`): `hasRawEmoji?`, `scanLineEmoji`, `scanFileEmoji` (takes a file name and its lines; it does not read the file), `auditAsnEmojis`.

`manifest.asn` has no `:modules` list and declares no dependencies. All 4 files in `src/` pass `asl/host/out/asl-host check` (2026-10-14).

## Example

Checked on the host on 2026-10-14 (outside this repository, name the package in the importing project's `.asl.config.asn`: `(:dependencies ((asl-text :path "/path/to/asl/packages/asl-text")))`):

```asl
(module example/textUsage :x [runTests] :i [(asl-text/escape :a esc) (asl-text/text :a tx)])

fn runTests -> Bool
  (do (assert (= (esc/escapeShArg "it's") "'it'\\''s'") "single quotes are closed, escaped and reopened")
      (assert (= (tx/decodeHtmlEntities "a &amp; b") "a & b") "entities are decoded")
      true)

## Modules and exports

From the `:x` list in each module header under `src/` (2026-10-14): 4 modules, 77 exported names. Long lists are cut at 18 names; the header of each file has the full list.

- `asl-text/emojiGuard` (`src/emojiGuard.asl`, 6): `EmojiViolation`, `EmojiScanResult`, `hasRawEmoji?`, `scanLineEmoji`, `scanFileEmoji`, `auditAsnEmojis`.
- `asl-text/escape` (`src/escape.asl`, 8): `UnescapeState`, `escapeAsnStr`, `unescapeAsnStr`, `escapeJsonStr`, `unescapeJsonStr`, `escapeShArg`, `isShSafeArg`, `escapeShCompact`.
- `asl-text/string` (`src/string.asl`, 14): `starts?`, `ends?`, `has?`, `split`, `concat`, `join`, `txtStarts?`, `txtEnds?`, `txtHas?`, `txtSplit`, `txt/starts?`, `txt/ends?`, `txt/has?`, `txt/split`.
- `asl-text/text` (`src/text.asl`, 49): `ExtractedDoc`, `ContextChunk`, `ContextualClause`, `TableData`, `CodeBlockData`, `DistilledSection`, `DistilledDoc`, `SourceIndexResult`, `InternResult`, `decodeHtmlEntities`, `stripEnclosed`, `cleanHtml`, `extractHtml`, `extractMarkdown`, `extractPlaintext`, `extractJsonKv`, `extractXmlAtom`, `extractContext`, and 31 more.

## Tests

Measured 2026-10-14 with the stage-0 host, run from the directory that contains the `asl/` checkout:

```sh
asl/host/out/asl-host test asl/packages/asl-text/tests/<file>.asl
```

4 of 4 test files exit 0 (140 assertions and refutations pass in those files).

| File | Result | Detail |
|---|---|---|
| `emojiGuardTest.asl` | pass | 9 assertions, 8 refutations |
| `escapeTest.asl` | pass | 16 assertions, 2 refutations |
| `modularAliasesTest.asl` | pass | 20 assertions, 6 refutations |
| `textTest.asl` | pass | 69 assertions, 10 refutations |
