(module asl-codec/asnlTest
  :d "Unit verification test suite for ASNL Streaming Protocol"
  :x [testBalancedForms
      testEscapingAndQuotes
      testCorruptLines
      testLineEncoding
      testLineDecoding
      testStreamParsing
      testTranspilation
      runTests]
  :i [(asl-codec/asnl :a asnl)])

(df testBalancedForms [] -> Bool
  :d "Verifies validation of diverse balanced ASNL records and vectors."
  (do
    (assert (asnl/asnlValidateLine "(:event :type \"tick\" :ts 100)") "valid event line")
    (assert (asnl/asnlValidateLine "[:a :b :c]") "valid vector line")
    (assert (asnl/asnlValidateLine "(:user :name \"alice\" :active true :count 42)") "valid user record")
    (assert (asnl/asnlValidateLine "(:nested (:inner [1 2 3]))") "valid nested form")
    (assert (not (asnl/asnlValidateLine "(:unclosed (paren")) "reject unclosed paren")
    true))

(df testEscapingAndQuotes [] -> Bool
  :d "Verifies quote escaping and delimiter isolation inside string literals."
  (do
    (assert (asnl/asnlValidateLine "(:msg \"hello \\\"world\\\"\")") "escaped quotes valid")
    (assert (asnl/asnlValidateLine "(:code \"(balanced (inside) string)\")") "parens inside string valid")
    (assert (asnl/asnlValidateLine "(:brackets \"[inside] [string]\")") "brackets inside string valid")
    (assert (not (asnl/asnlValidateLine "(:unclosed \"string)")) "reject unclosed string")
    true))

(df testCorruptLines [] -> Bool
  :d "Verifies strict rejection of malformed or corrupt ASNL lines."
  (do
    (assert (asnl/asnlValidateLine "(:valid 1)") "valid baseline line")
    (assert (not (asnl/asnlValidateLine "(:unclosed (paren")) "reject unclosed paren")
    (assert (not (asnl/asnlValidateLine "(:unclosed \"string)")) "reject unclosed string")
    (assert (not (asnl/asnlValidateLine "(:extra))")) "reject extra paren")
    (assert (not (asnl/asnlValidateLine "[:unclosed vector")) "reject unclosed vector")
    (assert (not (asnl/asnlValidateLine "")) "reject empty string")
    (assert (not (asnl/asnlValidateLine "   ")) "reject whitespace string")
    true))

(df testLineEncoding [] -> Bool
  :d "Verifies serialization and compaction of multi-line forms into single-line ASNL."
  (do
    (assert (= (asnl/asnlEncodeLine "(:a 1)") "(:a 1)") "encode single line")
    (assert (= (asnl/asnlEncodeLine "(:event\n  :type \"tick\"\n  :ts 100)") "(:event :type \"tick\" :ts 100)") "encode multiline")
    (assert (asnl/asnlValidateLine (asnl/asnlEncodeLine "(:multi\n  :line\n  [1 2 3])")) "encoded form is valid")
    (assert (not (string-contains? (asnl/asnlEncodeLine "(:a\n  :b\n  1)") "\n")) "encoded line has no newlines")
    true))

(df testLineDecoding [] -> Bool
  :d "Verifies line decoding behavior on valid and corrupt inputs."
  (do
    (assert (= (asnl/asnlDecodeLine "  (:event :type \"tick\")  ") "(:event :type \"tick\")") "decode trimmed line")
    (assert (= (asnl/asnlDecodeLine "(:corrupt (unclosed") "") "decode corrupt line returns empty")
    (assert (not (= (asnl/asnlDecodeLine "(:valid 1)") "")) "valid line decode not empty")
    true))

(df testStreamParsing [] -> Bool
  :d "Verifies incremental streaming parser skips empty and corrupt lines."
  (do
    (assert (= (list-length (asnl/asnlDecodeStream "(:e1 1)\n(:e2 2)\n(:e3 3)")) 3) "parse 3 events")
    (assert (= (list-length (asnl/asnlDecodeStream "(:e1 1)\n\n  \n(:e2 2)\n")) 2) "skip blank lines")
    (assert (= (list-length (asnl/asnlDecodeStream "(:e1 1)\n(:corrupt (unclosed\n(:e2 2)")) 2) "skip corrupt line")
    (assert (not (= (list-length (asnl/asnlDecodeStream "(:e1 1)\n(:e2 2)")) 0)) "valid stream not empty")
    true))

(df testTranspilation [] -> Bool
  :d "Verifies bidirectional JSONL <-> ASNL streaming transpilation."
  (let [(r1 (asnl/jsonlToAsnl "{\"type\": \"tick\", \"ts\": 100}\n{\"type\": \"tock\", \"ts\": 101}"))
        (r2 (asnl/asnlToJsonl "(:type \"tick\" :ts 100)\n(:type \"tock\" :ts 101)"))
        (rBad (asnl/asnlToJsonl "(:invalid (unbalanced"))]
    (assert (.-success r1) "jsonl to asnl success")
    (assert (string-contains? (.-output r1) ":type \"tick\"") "contains tick")
    (assert (>= (.-savingsPercent r1) 40.0) "savings >= 40%")
    (assert (.-success r2) "asnl to jsonl success")
    (assert (string-contains? (.-output r2) "\"type\": \"tick\"") "contains json type")
    (assert (not (.-success rBad)) "reject unbalanced asnl transpilation")
    true))

(df runTests [] -> Bool
  :d "Executes all ASNL verification assertions."
  (do
    (assert (testBalancedForms) "balanced forms")
    (assert (testEscapingAndQuotes) "escaping and quotes")
    (assert (testCorruptLines) "corrupt lines")
    (assert (testLineEncoding) "line encoding")
    (assert (testLineDecoding) "line decoding")
    (assert (testStreamParsing) "stream parsing")
    (assert (testTranspilation) "transpilation")
    true))
