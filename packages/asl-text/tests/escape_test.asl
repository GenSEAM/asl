(module asl-text/tests/escape-test
  :d "Unit tests for pure AgentScript canonical string escaping engine."
  :x [run-tests]
  :i [(escape :a esc)])

(df test-escape-asn [] -> Bool
  :d "Verifies ASN string literal escaping."
  (let [(raw "line 1\nline 2\t\"quoted\" \\slash\\")
        (escaped (esc/escape-asn-str raw))]
    (assert (string-contains? escaped "\\n") "Must escape newline")
    (assert (string-contains? escaped "\\t") "Must escape tab")
    (assert (string-contains? escaped "\\\"") "Must escape double quote")
    (assert (string-contains? escaped "\\\\") "Must escape backslash")
    (assert (= (esc/unescape-asn-str escaped) raw) "ASN escape roundtrip must preserve raw string")
    true))

(df test-escape-json [] -> Bool
  :d "Verifies RFC 8259 JSON string literal escaping."
  (let [(raw "key: \"value\"\nnew: \\path\\")
        (escaped (esc/escape-json-str raw))]
    (assert (string-contains? escaped "\\\"") "Must escape double quotes in JSON")
    (assert (string-contains? escaped "\\n") "Must escape newlines in JSON")
    (assert (string-contains? escaped "\\\\") "Must escape backslashes in JSON")
    (assert (= (esc/unescape-json-str escaped) raw) "JSON escape roundtrip must preserve raw string")
    true))

(df test-escape-sh-arg [] -> Bool
  :d "Verifies POSIX shell argument escaping."
  (let [(empty-arg (esc/escape-sh-arg ""))
        (simple-arg (esc/escape-sh-arg "status"))
        (complex-arg (esc/escape-sh-arg "don't stop"))]
    (assert (= empty-arg "''") "Empty arg must be double single-quotes")
    (assert (= simple-arg "'status'") "Simple arg must be wrapped in single-quotes")
    (assert (string-contains? complex-arg "'\\''") "Embedded single quote must be safely escaped")
    true))

(df run-tests [] -> Bool
  :d "Runs all asl-text escape unit tests."
  (and (test-escape-asn)
       (and (test-escape-json)
            (test-escape-sh-arg))))
