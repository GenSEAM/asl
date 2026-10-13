# asl-regex

Pure AgentScript regular-expression library featuring RE2-style linear-time matching via a Pike VM (Thompson NFA with submatch tracking) to guarantee immunity to ReDoS and catastrophic backtracking.

## Semantics

- **Linear-time matching**: Pike VM execution with submatch tracking, no backtracking.
- **Byte-oriented over UTF-8**: All matching, indexing (start, end), and character classes operate on byte positions over UTF-8 encoded text.
- **Supported constructs**:
  - Literals and escaped metacharacters
  - Wildcard `.` (matches any byte except newline `\n`, or any byte in dotall mode)
  - Character classes `[...]` and negated classes `[^...]` with ranges and escapes
  - Predefined classes: `\d`, `\D`, `\w`, `\W`, `\s`, `\S` (both standalone and inside classes)
  - Anchors: `^` (beginning of line/string), `$` (end of line/string), `\b` (word boundary), `\B` (non-word boundary)
  - Alternation: `|`
  - Capturing groups `(...)` and non-capturing groups `(?:...)`
  - Quantifiers: greedy `*`, `+`, `?`, `{m}`, `{m,}`, `{m,n}`; and lazy `*?`, `+?`, `??`, `{m,}?`, `{m,n}?`
  - Escapes: `\n`, `\r`, `\t`, `\f`, `\v`, `\0`, `\\`, etc.

## API

- `regex-compile : String -> (Result Regex String)`
- `regex-search : Regex String -> (Option Match)`
- `regex-match-full : Regex String -> (Option Match)`
- `regex-find-all : Regex String -> (List Match)`
- `regex-replace-all : Regex String String -> String`
