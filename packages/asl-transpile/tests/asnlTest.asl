(module asl-transpile/asnlTest :x [testBalancedForms testEscapingAndQuotes testCorruptLines testLineEncoding testLineDecoding testStreamParsing testTranspilation runTests] :i [(asl-transpile/asnl :a asnl)])

fn testBalancedForms -> Bool
  (do (assert (asnl/asnlValidateLine "(:event :type \"tick\" :ts 100)") "valid event line") (assert (asnl/asnlValidateLine "[:a :b :c]") "valid vector line") (assert (asnl/asnlValidateLine "(:user :name \"alice\" :active true :count 42)") "valid user record") (assert (asnl/asnlValidateLine "(:nested (:inner [1 2 3]))") "valid nested form") (assert (not (asnl/asnlValidateLine "(:unclosed (paren")) "reject unclosed paren") true)

fn testEscapingAndQuotes -> Bool
  (do (assert (asnl/asnlValidateLine "(:msg \"hello \\\"world\\\"\")") "escaped quotes valid") (assert (asnl/asnlValidateLine "(:code \"(balanced (inside) string)\")") "parens inside string valid") (assert (asnl/asnlValidateLine "(:brackets \"[inside] [string]\")") "brackets inside string valid") (assert (not (asnl/asnlValidateLine "(:unclosed \"string)")) "reject unclosed string") true)

fn testCorruptLines -> Bool
  (do (assert (asnl/asnlValidateLine "(:valid 1)") "valid baseline line") (assert (not (asnl/asnlValidateLine "(:unclosed (paren")) "reject unclosed paren") (assert (not (asnl/asnlValidateLine "(:unclosed \"string)")) "reject unclosed string") (assert (not (asnl/asnlValidateLine "(:extra))")) "reject extra paren") (assert (not (asnl/asnlValidateLine "[:unclosed vector")) "reject unclosed vector") (assert (not (asnl/asnlValidateLine "")) "reject empty string") (assert (not (asnl/asnlValidateLine "   ")) "reject whitespace string") true)

fn testLineEncoding -> Bool
  (do (assert (= (asnl/asnlEncodeLine "(:a 1)") "(:a 1)") "encode single line") (assert (= (asnl/asnlEncodeLine "(:event\n  :type \"tick\"\n  :ts 100)") "(:event :type \"tick\" :ts 100)") "encode multiline") (assert (asnl/asnlValidateLine (asnl/asnlEncodeLine "(:multi\n  :line\n  [1 2 3])")) "encoded form is valid") (assert (not (stringContains? (asnl/asnlEncodeLine "(:a\n  :b\n  1)") "\n")) "encoded line has no newlines") true)

fn testLineDecoding -> Bool
  (do (assert (= (asnl/asnlDecodeLine "  (:event :type \"tick\")  ") "(:event :type \"tick\")") "decode trimmed line") (assert (= (asnl/asnlDecodeLine "(:corrupt (unclosed") "") "decode corrupt line returns empty") (assert (not (= (asnl/asnlDecodeLine "(:valid 1)") "")) "valid line decode not empty") true)

fn testStreamParsing -> Bool
  (do (assert (= (listLength (asnl/asnlDecodeStream "(:e1 1)\n(:e2 2)\n(:e3 3)")) 3) "parse 3 events") (assert (= (listLength (asnl/asnlDecodeStream "(:e1 1)\n\n  \n(:e2 2)\n")) 2) "skip blank lines") (assert (= (listLength (asnl/asnlDecodeStream "(:e1 1)\n(:corrupt (unclosed\n(:e2 2)")) 2) "skip corrupt line") (assert (not (= (listLength (asnl/asnlDecodeStream "(:e1 1)\n(:e2 2)")) 0)) "valid stream not empty") true)

fn testTranspilation -> Bool
  (let [(r1 (asnl/jsonlToAsnl "{\"type\": \"tick\", \"ts\": 100}\n{\"type\": \"tock\", \"ts\": 101}")) (r2 (asnl/asnlToJsonl "(:type \"tick\" :ts 100)\n(:type \"tock\" :ts 101)")) (rBad (asnl/asnlToJsonl "(:invalid (unbalanced"))] (assert r1.success "jsonl to asnl success") (assert (stringContains? r1.output ":type \"tick\"") "contains tick") (assert (>= r1.savingsPercent 40.0) "savings >= 40%") (assert r2.success "asnl to jsonl success") (assert (stringContains? r2.output "\"type\": \"tick\"") "contains json type") (assert (not rBad.success) "reject unbalanced asnl transpilation") true)

fn runTests -> Bool
  (do (assert (testBalancedForms) "balanced forms") (assert (testEscapingAndQuotes) "escaping and quotes") (assert (testCorruptLines) "corrupt lines") (assert (testLineEncoding) "line encoding") (assert (testLineDecoding) "line decoding") (assert (testStreamParsing) "stream parsing") (assert (testTranspilation) "transpilation") true)
