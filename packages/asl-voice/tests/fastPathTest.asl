(module aslVoice/tests/fastPathTest :x [runTests testValidAsnInput testInvalidAsnInput testSymbolLexicon testFastPathTranspilation] :i [(voice/fastPath :a fp)])

fn testValidAsnInput -> Bool
  (let [(r1 (fp/isValidAsnInput? "(:task :id t1)")) (r2 (fp/isValidAsnInput? "   (module foo :x [bar])  ")) (r3 (fp/isValidAsnInput? "((nested) (expr))"))] (assert r1 "Standard ASN task expression must be valid") (assert r2 "Trimmed module expression must be valid") (assert (not (= r3 false)) "Nested expression must not be invalid") true)

fn testInvalidAsnInput -> Bool
  (let [(r1 (fp/isValidAsnInput? "unstructured text without parens")) (r2 (fp/isValidAsnInput? "(unclosed expression")) (r3 (fp/isValidAsnInput? ")(bad paren order)(")) (r4 (fp/isValidAsnInput? ""))] (assert (not r1) "Plain text must not be valid ASN") (assert (not r2) "Unclosed parens must not be valid ASN") (assert (not r3) "Inverted parens must not be valid ASN") (assert (= r4 false) "Empty string must be false") true)

fn testSymbolLexicon -> Bool
  (let [(lex (fp/buildSymbolLexicon)) (len (listLength lex)) (hasSw (listContains? lex "stringStartsWith?")) (hasMem (listContains? lex "asl-mem")) (hasClaim (listContains? lex "task-claim")) (hasBogus (listContains? lex "non-existent-symbol"))] (assert (> len 15) "Lexicon must contain at least 15 symbols") (assert hasSw "Lexicon must contain stringStartsWith?") (assert hasMem "Lexicon must contain asl-mem") (assert hasClaim "Lexicon must contain task-claim") (assert (not hasBogus) "Lexicon must not contain arbitrary symbols") true)

fn testFastPathTranspilation -> Bool
  (let [(asnIn "(:task :id t1 :priority :high)") (asnRes (fp/transpileFastPath asnIn)) (rawRes (fp/transpileFastPath "please transpile this prompt")) (jsonRes (fp/transpileFastPath "{\"action\": \"claim\"}"))] (assert (= asnRes asnIn) "Valid ASN must pass through unchanged") (assert (= rawRes "") "Unstructured prompt must return empty string on fast path") (assert (stringStartsWith? jsonRes "(:json") "JSON input must wrap in json form") (assert (not (= (stringLength asnRes) 0)) "ASN fast path result must not be empty") true)

fn runTests -> Bool
  (do (assert (testValidAsnInput) "test-valid-asn-input must pass") (assert (testInvalidAsnInput) "test-invalid-asn-input must pass") (assert (testSymbolLexicon) "test-symbol-lexicon must pass") (assert (testFastPathTranspilation) "test-fast-path-transpilation must pass") true)
