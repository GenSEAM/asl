(module asl-text/tests/escapeTest
  :d "Unit tests for pure AgentScript canonical string escaping engine."
  :x [runTests]
  :i [(escape :a esc)])

(df testEscapeAsn [] -> Bool
  :d "Verifies ASN string literal escaping."
  (let [(raw "line 1\nline 2\t\"quoted\" \\slash\\")
        (escaped (esc/escapeAsnStr raw))]
    (assert (string-contains? escaped "\\n") "Must escape newline")
    (assert (string-contains? escaped "\\t") "Must escape tab")
    (assert (string-contains? escaped "\\\"") "Must escape double quote")
    (assert (string-contains? escaped "\\\\") "Must escape backslash")
    (assert (= (esc/unescapeAsnStr escaped) raw) "ASN escape roundtrip must preserve raw string")
    true))

(df testEscapeJson [] -> Bool
  :d "Verifies RFC 8259 JSON string literal escaping."
  (let [(raw "key: \"value\"\nnew: \\path\\")
        (escaped (esc/escapeJsonStr raw))]
    (assert (string-contains? escaped "\\\"") "Must escape double quotes in JSON")
    (assert (string-contains? escaped "\\n") "Must escape newlines in JSON")
    (assert (string-contains? escaped "\\\\") "Must escape backslashes in JSON")
    (assert (= (esc/unescapeJsonStr escaped) raw) "JSON escape roundtrip must preserve raw string")
    true))

(df testEscapeShArg [] -> Bool
  :d "Verifies POSIX shell argument escaping."
  (let [(emptyArg (esc/escapeShArg ""))
        (simpleArg (esc/escapeShArg "status"))
        (complexArg (esc/escapeShArg "don't stop"))]
    (assert (= emptyArg "''") "Empty arg must be double single-quotes")
    (assert (= simpleArg "'status'") "Simple arg must be wrapped in single-quotes")
    (assert (string-contains? complexArg "'\\''") "Embedded single quote must be safely escaped")
    true))

(df testUnescapeOrderOfOperations [] -> Bool
  :d "Verifies that escaped backslash followed by n is not prematurely unescaped to newline."
  (let [(escaped "\\\\n")
        (unescapedAsn (esc/unescapeAsnStr escaped))
        (unescapedJson (esc/unescapeJsonStr escaped))]
    (refute (string-contains? unescapedAsn "\n") "ASN unescaping must not produce newline from \\\\n")
    (assert (string-contains? unescapedAsn "\\n") "ASN unescaping must preserve \\n")
    (assert (= unescapedAsn "\\n") "ASN unescaped string must equal literal \\n")
    (refute (string-contains? unescapedJson "\n") "JSON unescaping must not produce newline from \\\\n")
    (assert (string-contains? unescapedJson "\\n") "JSON unescaping must preserve \\n")
    (assert (= unescapedJson "\\n") "JSON unescaped string must equal literal \\n")
    true))

(df runTests [] -> Bool
  :d "Runs all asl-text escape unit tests."
  (and (testEscapeAsn)
       (and (testEscapeJson)
            (and (testEscapeShArg)
                 (testUnescapeOrderOfOperations)))))

