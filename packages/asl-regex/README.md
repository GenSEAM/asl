# asl-regex

Regular expressions in ASL with RE2-style linear-time matching: patterns compile to a Pike VM (a Thompson NFA with submatch tracking), so there is no backtracking and no catastrophic blow-up on patterns such as `(a*)*b`.

## Semantics

- **Byte-oriented over UTF-8**: matching, `start`/`end` offsets and character classes work on bytes of the UTF-8 text.
- **Supported constructs**:
  - Literals and escaped metacharacters
  - Wildcard `.` (any byte except `\n`, or any byte in dotall mode)
  - Character classes `[...]` and negated classes `[^...]` with ranges and escapes
  - Predefined classes `\d`, `\D`, `\w`, `\W`, `\s`, `\S`, standalone and inside classes
  - Anchors `^`, `$` (line anchors in multiline mode), `\b`, `\B`
  - Alternation `|`; capturing `(...)` and non-capturing `(?:...)` groups
  - Greedy `*`, `+`, `?`, `{m}`, `{m,}`, `{m,n}` and lazy `*?`, `+?`, `??`, `{m,}?`, `{m,n}?`
  - Escapes `\n`, `\r`, `\t`, `\f`, `\v`, `\0`, `\\`

## API (`asl-regex/regex`, `src/regex.asl`)

- `regex-compile! : String -> (Result Regex String)`
- `regex-compile-flags! : String Bool Bool Bool -> (Result Regex String)` (multiline, dotall, ignoreCase)
- `regex-search! : Regex String -> (Option Match)`
- `regex-match-full! : Regex String -> (Option Match)`
- `regex-match? : Regex String -> Bool`
- `regex-find-all! : Regex String -> (List Match)`
- `regex-replace-all! : Regex String String -> String`
- `regex-group : Match Int64 -> (Option String)`
- `Match` has `start`, `end`, `text` and `groups : (List (Option String))`.

## Example

Checked on the host on 2026-10-14 (the importing project names the package in its `.asl.config.asn`: `(:dependencies ((asl-regex :path "/path/to/asl/packages/asl-regex")))`):

```asl
(module example/regexUsage :x [runTests] :i [(asl-regex/regex :a rx)])

fn runTests -> Bool
  (mt (rx/regex-compile! "\\b(\\w+?)@(?:[a-z]+\\.)+[a-z]{2,3}\\b")
    ((err e) (do (assert false e) false))
    ((ok re)
      (mt (rx/regex-search! re "mail ann@example.org now")
        ((none) (do (assert false "no match") false))
        ((some m) (do (assert (= m.text "ann@example.org") "whole match")
                      (assert (= (rx/regex-group m 1) (some "ann")) "group 1")
                      (assert (= (rx/regex-replace-all! re "a@b.cc d@e.ff" "X") "X X") "replace")
                      true)))))
```

The module exports nothing else; `manifest.asn` lists it as the only module and declares no dependencies. `src/regex.asl` passes `asl/host/out/asl-host check` (2026-10-14).

## Modules and exports

From the `:x` list in each module header under `src/` (2026-10-14): 1 module, 10 exported names. Long lists are cut at 18 names; the header of each file has the full list.

- `asl-regex/regex` (`src/regex.asl`, 10): `Match`, `Regex`, `regex-compile!`, `regex-compile-flags!`, `regex-search!`, `regex-match-full!`, `regex-find-all!`, `regex-replace-all!`, `regex-group`, `regex-match?`.

## Tests

Measured 2026-10-14 with the stage-0 host, run from the directory that contains the `asl/` checkout:

```sh
asl/host/out/asl-host test asl/packages/asl-regex/tests/<file>.asl
```

0 of 1 test files exit 0 (0 assertions and refutations pass in those files).

| File | Result | Detail |
|---|---|---|
| `regexTest.asl` | **fail** | 500 assertions pass, then `testSuiteNameOverGitLsFiles!` runs `git ls-files` in the working directory; it needs the parent monorepo (a git checkout at the working directory) |
