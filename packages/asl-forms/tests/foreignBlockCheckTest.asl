(module asl-forms/tests/foreignBlockCheckTest
  :x [runTests]
  :i [(asl-forms/foreignBlock :a fb)
      (asl-syntax/asl/asn :a asn)])

fn verdictAt verdicts: (List fb/ForeignVerdict) index: Int64 -> fb/ForeignVerdict
  (optionOr (listGet verdicts index) (fb/ForeignVerdict :language "missing" :status "missing" :message "missing verdict"))

fn block tag: String body: String -> asn/AsnValue
  (asn/asnCase tag (list (asn/asnStr (str "\"" body "\""))))

fn flatTests -> Bool
  (let [(forms (list
                (block "f/js" "function g(){ return 1; }")
                (block "f/js" "function g( { return ")
                (block "f/css" "a { color: red; }")
                (block "f/css" "h1, h2")
                (block "f/py" "print(1)")
                (block "f/sh" "echo ok")
                (block "f/sql" "select 1")
                (block "f/llvm" "ret void")
                (block "f/c" "int main(void) { return 0; }")))
        (verdicts (fb/checkForeignBlocks (list (pair "asl-foreign/block" "f")) forms))
        (jsOk (verdictAt verdicts 0))
        (jsBad (verdictAt verdicts 1))
        (cssOk (verdictAt verdicts 2))
        (cssBad (verdictAt verdicts 3))
        (pySkipped (verdictAt verdicts 4))
        (shSkipped (verdictAt verdicts 5))
        (sqlSkipped (verdictAt verdicts 6))
        (llvmSkipped (verdictAt verdicts 7))
        (cSkipped (verdictAt verdicts 8))]
    (do
      (assert (= (listLength verdicts) 9) "find every tagged foreign block")
      (assert (= jsOk.status "ok") "valid js block is checked")
      (assert (= jsBad.status "error") "invalid js block is rejected")
      (assert (not (stringEmpty? jsBad.message)) "invalid js block includes checker message")
      (assert (= cssOk.status "ok") "valid css block is checked")
      (assert (= cssBad.status "error") "invalid css block is rejected")
      (assert (not (stringEmpty? cssBad.message)) "invalid css block includes checker message")
      (assert (= pySkipped.status "skipped") "python block has no ASL checker")
      (assert (= shSkipped.status "skipped") "shell block has no ASL checker")
      (assert (= sqlSkipped.status "skipped") "sql block has no ASL checker")
      (assert (= llvmSkipped.status "skipped") "llvm block has no ASL checker")
      (assert (= cSkipped.status "skipped") "c block has no ASL checker")
      true))

fn nestedTests -> Bool
  (let [(forms (list
                (asn/asnVec (list (block "f/js" "var a = 1;")))
                (asn/asnMap (list (asn/AsnEntry :key (block "f/css" "p { margin: 0; }") :val (block "f/css" "h1, h2") :paren true)))
                (asn/asnRec (list (asn/AsnField :key "page" :val (block "f/html" "<p>hi</p>"))))
                (asn/asnCtor "Page" (list (asn/AsnField :key "body" :val (block "f/html" "<p><b>hi</p>"))))
                (asn/asnRows "Script" (list (asn/asnVec (list (block "f/py" "print(1)")))))
                (asn/asnTable (list (asn/asnKw ":cmd")) (list (asn/asnVec (list (block "f/sh" "echo ok")))))
                (asn/asnPair (asn/asnStr "\"query\"") (block "f/sql" "select 1"))
                (asn/asnPair (block "f/css" "h1, h2") (asn/asnStr "\"value\""))
                (asn/asnCase "wrap" (list (asn/asnInt "1") (block "f/js" "let x: number = 1;")))
                (block "x/js" "function g( {")
                (block "js" "function g( {")
                (block "f/jsStr" "a'b")
                (block "f/ts" "let y: number = 1;")
                (block "f/json" "{}")))
        (verdicts (fb/checkForeignBlocks (list (pair "asl-foreign/block" "f")) forms))
        (vecJs (verdictAt verdicts 0))
        (mapKeyCss (verdictAt verdicts 1))
        (mapValCss (verdictAt verdicts 2))
        (recHtml (verdictAt verdicts 3))
        (ctorHtml (verdictAt verdicts 4))
        (rowsPy (verdictAt verdicts 5))
        (tableSh (verdictAt verdicts 6))
        (pairSql (verdictAt verdicts 7))
        (pairKeyCss (verdictAt verdicts 8))
        (caseArgJs (verdictAt verdicts 9))]
    (do
      (assert (= (listLength verdicts) 10) "nested blocks are found and untagged, escaper and non-block tags add no verdict")
      (assert (and (= vecJs.language "js") (= vecJs.status "ok")) "block inside a vector is checked")
      (assert (and (= mapKeyCss.language "css") (= mapKeyCss.status "ok")) "block in a map key is checked")
      (assert (and (= mapValCss.language "css") (= mapValCss.status "error")) "block in a map value is checked")
      (assert (and (= recHtml.language "html") (= recHtml.status "ok")) "valid html block in a record is checked")
      (assert (and (= ctorHtml.language "html") (= ctorHtml.status "error")) "invalid html block in a constructor is rejected")
      (assert (and (= rowsPy.language "py") (= rowsPy.status "skipped")) "block inside rows is found")
      (assert (and (= tableSh.language "sh") (= tableSh.status "skipped")) "block inside a table is found")
      (assert (and (= pairSql.language "sql") (= pairSql.status "skipped")) "block inside a pair's item is found")
      (assert (and (= pairKeyCss.language "css") (= pairKeyCss.status "error")) "block inside a pair's key is found and checked")
      (assert (and (= caseArgJs.language "js") (= caseArgJs.status "error")) "js block nested in a case argument rejects a typescript annotation")
      true))

fn aliasTests -> Bool
  (let [(forms (list
                (block "foreign/js" "function g( {")
                (block "f/js" "function g( {")))
        (imports (list (pair "asl-syntax/asl/asn" "f") (pair "asl-foreign/block" "foreign")))
        (aliased (fb/checkForeignBlocks imports forms))
        (aliasedJs (verdictAt aliased 0))]
    (do
      (assert (= (fb/foreignAliases imports) (list "foreign")) "only the asl-foreign/block import supplies a foreign alias")
      (assert (= (listLength aliased) 1) "a tag is foreign only under the alias bound to asl-foreign/block")
      (assert (and (= aliasedJs.language "js") (= aliasedJs.status "error")) "a block under a non-f alias is checked")
      (assert (listEmpty? (fb/checkForeignBlocks (list) forms)) "without an asl-foreign/block import no block is foreign")
      true))

fn shapeTests -> Bool
  (let [(columnForms (list (asn/asnTable (list (block "f/css" "h1, h2")) (list (asn/asnVec (list (asn/asnKw ":x")))))))
        (columnVerdicts (fb/checkForeignBlocks (list (pair "asl-foreign/block" "f")) columnForms))
        (columnCss (verdictAt columnVerdicts 0))
        (deepForms (list (block "f/js/x" "function g( {") (block "f/css/js" "h1, h2")))]
    (do
      (assert (= (listLength columnVerdicts) 1) "a block in a table column adds one verdict")
      (assert (and (= columnCss.language "css") (= columnCss.status "error")) "invalid css block in a table column is rejected")
      (assert (listEmpty? (fb/checkForeignBlocks (list (pair "asl-foreign/block" "f")) deepForms)) "a tag with more than alias and language is not a foreign block")
      true))

fn runTests -> Bool
  (and (flatTests) (and (nestedTests) (and (aliasTests) (shapeTests))))
