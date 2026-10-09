(module asl-text/tests/escapeTest :x [runTests] :i [(escape :a esc)])

fn testEscapeAsn -> Bool
  (let [(raw "line 1\nline 2\t\"quoted\" \\slash\\") (escaped (esc/escapeAsnStr raw))] (assert (stringContains? escaped "\\n") "Must escape newline") (assert (stringContains? escaped "\\t") "Must escape tab") (assert (stringContains? escaped "\\\"") "Must escape double quote") (assert (stringContains? escaped "\\\\") "Must escape backslash") (assert (= (esc/unescapeAsnStr escaped) raw) "ASN escape roundtrip must preserve raw string") true)

fn testEscapeJson -> Bool
  (let [(raw "key: \"value\"\nnew: \\path\\") (escaped (esc/escapeJsonStr raw))] (assert (stringContains? escaped "\\\"") "Must escape double quotes in JSON") (assert (stringContains? escaped "\\n") "Must escape newlines in JSON") (assert (stringContains? escaped "\\\\") "Must escape backslashes in JSON") (assert (= (esc/unescapeJsonStr escaped) raw) "JSON escape roundtrip must preserve raw string") true)

fn testEscapeShArg -> Bool
  (let [(emptyArg (esc/escapeShArg "")) (simpleArg (esc/escapeShArg "status")) (complexArg (esc/escapeShArg "don't stop"))] (assert (= emptyArg "''") "Empty arg must be double single-quotes") (assert (= simpleArg "'status'") "Simple arg must be wrapped in single-quotes") (assert (stringContains? complexArg "'\\''") "Embedded single quote must be safely escaped") true)

fn testUnescapeOrderOfOperations -> Bool
  (let [(escaped "\\\\n") (unescapedAsn (esc/unescapeAsnStr escaped)) (unescapedJson (esc/unescapeJsonStr escaped))] (refute (stringContains? unescapedAsn "\n") "ASN unescaping must not produce newline from \\\\n") (assert (stringContains? unescapedAsn "\\n") "ASN unescaping must preserve \\n") (assert (= unescapedAsn "\\n") "ASN unescaped string must equal literal \\n") (refute (stringContains? unescapedJson "\n") "JSON unescaping must not produce newline from \\\\n") (assert (stringContains? unescapedJson "\\n") "JSON unescaping must preserve \\n") (assert (= unescapedJson "\\n") "JSON unescaped string must equal literal \\n") true)

fn runTests -> Bool
  (and (testEscapeAsn) (and (testEscapeJson) (and (testEscapeShArg) (testUnescapeOrderOfOperations))))
