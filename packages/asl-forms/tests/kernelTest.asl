(module asl-forms/tests/kernelTest :x [runTests] :i [(asl-forms/kernel :a k)])

fn wsRoot! -> String
  (resultOr (realPath "asl/packages/asl-forms/tests/fixtures/ws") "")

fn kw step: k/ParsedStep key: String -> String
  (optionOr (mapGet step.kwargs key) "<absent>")

fn testDyck -> Bool
  (do
    (assert (k/isBalanced "(:echo \"hello (world)\")") "a paren inside a string does not count")
    (assert (not (k/isBalanced "(:echo \"hello)")) "an unclosed string is unbalanced")
    (assert (= (k/countDyck1 "(:echo") 1) "one open paren leaves depth 1")
    (assert (= (k/countDyck1 ")(") -1) "a close before any open is -1")
    true)

fn testEscape -> Bool
  (let [(orig "a\"b\\c\nd")]
    (assert (= (k/escapeAsnVal orig) "a\\\"b\\\\c\\nd") "escape_asn_val escapes backslash, quote and newline")
    (assert (= (k/asnUnescape (k/escapeAsnVal orig)) orig) "asn_unescape inverts escape_asn_val")
    (assert (= (k/asnUnescape "\\q") "\\q") "an unknown escape keeps its backslash")
    (assert (= (k/asnUnescape "a\\rb") "a\\rb") "backslash-r is not an _ASN_ESCAPES key, so it keeps its backslash")
    true)

fn testParseGroupToken -> Bool
  (let [(step (k/parseStep "(:read :x (:a \"b)\" :c 1) :file \"f\" :depth :deep extra)"))]
    (assert (= step.op "read") "op is the head without its colon")
    (assert (= (kw step "x") "(:a \"b)\" :c 1)") "a group token keeps a quoted close paren inside")
    (assert (= (kw step "file") "f") "the key after a group token still parses")
    (assert (= (kw step "depth") "true") "a keyword followed by key and value is a flag")
    (assert (= (kw step "deep") "extra") "the following key takes its value")
    true)

fn testExtractSteps -> Bool
  (let [(steps (k/extractSteps "(:batch :seq true (:ping) (:echo \"a)b\") x)"))]
    (assert (= steps (list "(:ping)" "(:echo \"a)b\")")) "batch steps come out whole, strings respected")
    (assert (= (k/extractSteps ":ping") (list "(:ping)")) "a bare keyword payload is wrapped")
    true)

fn testBatchSeq -> Bool
  (do
    (assert (k/batchSeq "(:batch :seq true (:ping))") ":seq true")
    (assert (k/batchSeq "(:batch :seq :true (:ping))") ":seq :true")
    (assert (not (k/batchSeq "(:batch :seq trueish (:ping))")) ":seq needs the whole word true")
    (assert (not (k/batchSeq "(:batch (:echo \":seq true\"))")) "only the batch head counts")
    true)

fn testPaths -> Bool
  (do
    (assert (= (k/normalizePath "/a/../../b") "/b") "an absolute path does not climb above /")
    (assert (= (k/normalizePath "a/../../b") "../b") "a relative path keeps leading ..")
    (assert (= (k/dirName "/a/b/") "/a/b") "dirname of a trailing slash path")
    (assert (= (k/relPath "/x/y/z" "/x/q") "../y/z") "relpath climbs to the common prefix")
    true)

fn testContainment! -> Bool
  (let [(root (wsRoot!))]
    (assert (= (pairSecond (k/resolveInRoot! root "escape/main.asl")) "Path escapes workspace boundary: escape/main.asl") "a symlinked directory leaving the root is refused")
    (assert (= (pairFirst (k/resolveInRoot! root "sub/../missing/x.txt")) (str root "/missing/x.txt")) "a missing tail resolves under the real existing prefix")
    (assert (= (pairFirst (k/resolveEditTarget! root "unique.txt")) (str root "/sub/unique.txt")) "a unique bare name resolves by walking the root")
    (assert (= (pairSecond (k/resolveEditTarget! root "dup.txt")) "Ambiguous bare filename matches 2 files; pass a path relative to the workspace root") "two bare-name matches are ambiguous")
    true)

fn testBinaryKind -> Bool
  (do
    (assert (= (k/binaryKind "\x89PNG\r\n\x1a\nx") "png") "png magic")
    (assert (= (k/binaryKind "MZ\x00") "pe") "MZ with a NUL is pe")
    (assert (= (k/binaryKind "MZ text") "") "MZ alone is text")
    (assert (= (k/binaryKind (str (stringRepeat "a" 8192) "\x00")) "") "a NUL past the first 8 KB is text")
    true)

fn ! runTests -> Bool
  (do
    (assert (testDyck) "testDyck")
    (assert (testEscape) "testEscape")
    (assert (testParseGroupToken) "testParseGroupToken")
    (assert (testExtractSteps) "testExtractSteps")
    (assert (testBatchSeq) "testBatchSeq")
    (assert (testPaths) "testPaths")
    (assert (testContainment!) "testContainment")
    (assert (testBinaryKind) "testBinaryKind")
    true)
