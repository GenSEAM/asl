(module asl-codec/asnl-test
  :d "Unit verification test suite for ASNL Streaming Protocol"
  :x [test-balanced-forms
      test-escaping-and-quotes
      test-corrupt-lines
      test-line-encoding
      test-line-decoding
      test-stream-parsing
      test-transpilation
      run-tests]
  :i [(asnl :a asnl)])

(df test-balanced-forms [] -> Bool
  :d "Verifies validation of diverse balanced ASNL records and vectors."
  (do
    (assert (asnl/asnl-validate-line "(:event :type \"tick\" :ts 100)") "valid event line")
    (assert (asnl/asnl-validate-line "[:a :b :c]") "valid vector line")
    (assert (asnl/asnl-validate-line "(:user :name \"alice\" :active true :count 42)") "valid user record")
    (assert (asnl/asnl-validate-line "(:nested (:inner [1 2 3]))") "valid nested form")
    (assert (not (asnl/asnl-validate-line "(:unclosed (paren")) "reject unclosed paren")
    true))

(df test-escaping-and-quotes [] -> Bool
  :d "Verifies quote escaping and delimiter isolation inside string literals."
  (do
    (assert (asnl/asnl-validate-line "(:msg \"hello \\\"world\\\"\")") "escaped quotes valid")
    (assert (asnl/asnl-validate-line "(:code \"(balanced (inside) string)\")") "parens inside string valid")
    (assert (asnl/asnl-validate-line "(:brackets \"[inside] [string]\")") "brackets inside string valid")
    (assert (not (asnl/asnl-validate-line "(:unclosed \"string)")) "reject unclosed string")
    true))

(df test-corrupt-lines [] -> Bool
  :d "Verifies strict rejection of malformed or corrupt ASNL lines."
  (do
    (assert (asnl/asnl-validate-line "(:valid 1)") "valid baseline line")
    (assert (not (asnl/asnl-validate-line "(:unclosed (paren")) "reject unclosed paren")
    (assert (not (asnl/asnl-validate-line "(:unclosed \"string)")) "reject unclosed string")
    (assert (not (asnl/asnl-validate-line "(:extra))")) "reject extra paren")
    (assert (not (asnl/asnl-validate-line "[:unclosed vector")) "reject unclosed vector")
    (assert (not (asnl/asnl-validate-line "")) "reject empty string")
    (assert (not (asnl/asnl-validate-line "   ")) "reject whitespace string")
    true))

(df test-line-encoding [] -> Bool
  :d "Verifies serialization and compaction of multi-line forms into single-line ASNL."
  (do
    (assert (= (asnl/asnl-encode-line "(:a 1)") "(:a 1)") "encode single line")
    (assert (= (asnl/asnl-encode-line "(:event\n  :type \"tick\"\n  :ts 100)") "(:event :type \"tick\" :ts 100)") "encode multiline")
    (assert (asnl/asnl-validate-line (asnl/asnl-encode-line "(:multi\n  :line\n  [1 2 3])")) "encoded form is valid")
    (assert (not (string-contains? (asnl/asnl-encode-line "(:a\n  :b\n  1)") "\n")) "encoded line has no newlines")
    true))

(df test-line-decoding [] -> Bool
  :d "Verifies line decoding behavior on valid and corrupt inputs."
  (do
    (assert (= (asnl/asnl-decode-line "  (:event :type \"tick\")  ") "(:event :type \"tick\")") "decode trimmed line")
    (assert (= (asnl/asnl-decode-line "(:corrupt (unclosed") "") "decode corrupt line returns empty")
    (assert (not (= (asnl/asnl-decode-line "(:valid 1)") "")) "valid line decode not empty")
    true))

(df test-stream-parsing [] -> Bool
  :d "Verifies incremental streaming parser skips empty and corrupt lines."
  (do
    (assert (= (list-length (asnl/asnl-decode-stream "(:e1 1)\n(:e2 2)\n(:e3 3)")) 3) "parse 3 events")
    (assert (= (list-length (asnl/asnl-decode-stream "(:e1 1)\n\n  \n(:e2 2)\n")) 2) "skip blank lines")
    (assert (= (list-length (asnl/asnl-decode-stream "(:e1 1)\n(:corrupt (unclosed\n(:e2 2)")) 2) "skip corrupt line")
    (assert (not (= (list-length (asnl/asnl-decode-stream "(:e1 1)\n(:e2 2)")) 0)) "valid stream not empty")
    true))

(df test-transpilation [] -> Bool
  :d "Verifies bidirectional JSONL <-> ASNL streaming transpilation."
  (let [(r1 (asnl/jsonl-to-asnl "{\"type\": \"tick\", \"ts\": 100}\n{\"type\": \"tock\", \"ts\": 101}"))
        (r2 (asnl/asnl-to-jsonl "(:type \"tick\" :ts 100)\n(:type \"tock\" :ts 101)"))
        (r-bad (asnl/asnl-to-jsonl "(:invalid (unbalanced"))]
    (assert (.-success r1) "jsonl to asnl success")
    (assert (string-contains? (.-output r1) ":type \"tick\"") "contains tick")
    (assert (>= (.-savings-percent r1) 40.0) "savings >= 40%")
    (assert (.-success r2) "asnl to jsonl success")
    (assert (string-contains? (.-output r2) "\"type\": \"tick\"") "contains json type")
    (assert (not (.-success r-bad)) "reject unbalanced asnl transpilation")
    true))

(df run-tests [] -> Bool
  :d "Executes all ASNL verification assertions."
  (do
    (assert (test-balanced-forms) "balanced forms")
    (assert (test-escaping-and-quotes) "escaping and quotes")
    (assert (test-corrupt-lines) "corrupt lines")
    (assert (test-line-encoding) "line encoding")
    (assert (test-line-decoding) "line decoding")
    (assert (test-stream-parsing) "stream parsing")
    (assert (test-transpilation) "transpilation")
    true))
