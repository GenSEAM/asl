(module asl/agentLoop/tests/txnOrderTest
  :x [runTests]
  :i [(asl/agentLoop/txn :a t)
      (asl/agentLoop/core :a c)])

; (:m :ref TXN-WRITE-ORDER :do "one txn with the test written before the src it imports is sent with the src first; an order that already holds, a cycle, and a txn that edits a file it also writes stay as written; a src whose module header is its test's gets a moduleHint naming the expected module; the path rule names asl/tools, package src and tests, and plain paths")
fn wr file: String content: String -> String
  (str "(:write :file \"" file "\" :content \"" (c/escapeAsn content) "\")")

fn srcText -> String
  "(module lib/foo\n  :x [f])\nfn f -> Int64\n  1\n"

fn testText -> String
  "(module lib/fooTest\n  :x [runTests]\n  :i [(lib/foo :a f)])\nfn ! runTests -> Bool\n  true\n"

fn badSrcText -> String
  "(module lib/fooTest\n  :x [f])\nfn f -> Int64\n  1\n"

fn ! sentOf! base: String form: String -> (Pair String String)
  (let [log (str base "/sent.log")
        _ (fileWrite log "")
        r (t/execTxn! form (list "lib") base (list) (fn [] "rid1") (fn [p] true)
            (fn [sent root] (do (fileWrite log sent) (t/aslRun 0 "(:txn :status :ok)" ""))))]
    (pair (resultOr (fileReadString log) "") (t/serReceipt r)))

fn before? s: String a: String b: String -> Bool
  (let [ia (optionOr (stringIndexOf s a) -1)
        ib (optionOr (stringIndexOf s b) -1)]
    (and (>= ia 0) (and (>= ib 0) (< ia ib))))

fn ! runTests -> Bool
  (let [tmp (resultOr (realPath "/tmp") "/tmp")
        base (str tmp "/aslTxnOrderTest." (stringFromInt64 (procSelf)))
        made (ok? (dirCreate base))
        tf "lib/tests/fooTest.asl"
        sf "lib/foo.asl"
        a (sentOf! base (str "(:txn :owns (\"lib\") " (wr tf (testText)) " " (wr sf (srcText)) ")"))
        b (sentOf! base (str "(:txn :owns (\"lib\") " (wr sf (srcText)) " " (wr tf (testText)) ")"))
        cyc (sentOf! base (str "(:txn :owns (\"lib\") " (wr "lib/a.asl" "(module lib/a\n  :x [f]\n  :i [(lib/b :a b)])\n") " " (wr "lib/b.asl" "(module lib/b\n  :x [g]\n  :i [(lib/a :a a)])\n") ")"))
        ed (sentOf! base (str "(:txn :owns (\"lib\") " (wr tf (testText)) " " (wr sf (srcText)) " (:edit :file \"" sf "\" :old \"1\" :new \"2\"))"))
        bad (sentOf! base (str "(:txn :owns (\"lib\") " (wr sf (badSrcText)) " " (wr tf (testText)) ")"))
        removed (ok? (pathRemove base))]
    (do (assert made "scratch dir made")
        (assert (before? (pairFirst a) "lib/foo.asl" "lib/tests/fooTest.asl") (str "test written first is sent after the src it imports: " (pairFirst a)))
        (assert (before? (pairFirst b) "lib/foo.asl" "lib/tests/fooTest.asl") (str "src first stays src first: " (pairFirst b)))
        (assert (before? (pairFirst cyc) "lib/a.asl" "lib/b.asl") (str "an import cycle keeps the written order: " (pairFirst cyc)))
        (assert (before? (pairFirst ed) "lib/tests/fooTest.asl" "lib/foo.asl") (str "a txn that edits a file it also writes is not reordered: " (pairFirst ed)))
        (assert (not (stringContains? (pairSecond a) "moduleHint")) (str "matching module names give no hint: " (pairSecond a)))
        (assert (and (stringContains? (pairSecond bad) "moduleHint") (stringContains? (pairSecond bad) "expected 'lib/foo'")) (str "a src carrying its test's module name gets the hint naming the expected module: " (pairSecond bad)))
        (assert (and (= (t/expectedModule "asl/tools/coord/x.asl") "asl-tools/coord/x") (and (= (t/expectedModule "asl/packages/asl-forms/src/edit.asl") "asl-forms/edit") (and (= (t/expectedModule "asl/packages/asl-checker/tests/undefinedExportTest.asl") "asl-checker/undefinedExportTest") (= (t/expectedModule "tools/remote/vps.asl") "tools/remote/vps")))) "the path rule matches the repository's own module headers")
        (assert (and (= (t/moduleOf "(module lib/foo\n  :x [f])") "lib/foo") (= (t/importsOf "(module m\n  :i [(lib/foo :a f) (lib/bar :a b)])") (list "lib/foo" "lib/bar"))) "moduleOf and importsOf read the header")
        (assert removed "scratch dir removed")
        true))
