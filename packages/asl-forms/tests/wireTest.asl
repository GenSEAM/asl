(module asl-forms/tests/wireTest :x [runTests] :i [(asl-forms/wire :a w)])

fn ws root: String -> w/Workspace
  (w/Workspace :root root :roots (list root) :ops (list "read" "tree"))

fn testWireError -> Bool
  (do
    (assert (= (w/wireError "ERR_PARSE" "Empty input; nothing executed" "") "(:batch :status :failed :error ERR_PARSE :message \"Empty input; nothing executed\")") "no hint for ERR_PARSE")
    (assert (= (w/wireError "ERR_UNBALANCED" "x" " :depth 1") "(:batch :status :failed :error ERR_UNBALANCED :depth 1 :message \"x\" :hint \"a paren, bracket or string in the input does not close; nothing ran\")") "hint follows the message")
    true)

fn testCamel -> Bool
  (do
    (assert (= (w/wireCamel ":error-code") ":errorCode") "dash words join camel case")
    (assert (= (w/wireCamel ":a--b") ":aB") "empty parts drop")
    (assert (= (w/wireCamel ":x-") ":x-") "a trailing dash is left alone")
    (assert (= (w/toolOps "(:op :read x) (:op :tree) (:op :read-y)") (list "read" "tree")) "tools.asn op names, letters only, sorted and unique")
    true)

fn testStepReceipts! -> Bool
  (do
    (assert (= (w/wireReceipt! (ws "/r") "  (:step :id 3 :op \"read\" :status \"rejected\" :error-code \":ERR_BINARY\" :file \"x\" :kind \"png\")" true "read")
               "(:read :status :rejected :error ERR_BINARY :file \"x\" :kind \"png\" :hint \"binary files are never returned as text; inspect them with a native tool such as file, otool or xxd\" :see \"(:help :op read)\")")
            "a rejected step: head, status, error, hint, see")
    (assert (= (w/wireReceipt! (ws "/r") "  (:step :id 1 :op \"tree-walk\" :status \"ok\" :my-key \"/r/a/b\" :content \"/r/c\")" false "")
               "(:treeWalk :myKey \"a/b\" :content \"/r/c\")")
            "roots are relativised except in :content")
    (assert (= (w/wireReceipt! (ws "/r") "  (:step :id 1 :op \"x\" :message \"unterminated)" false "echo")
               "(:echo :raw \"(:step :id 1 :op \\\"x\\\" :message \\\"unterminated)\")")
            "text that is not ASN travels as :raw")
    true)

fn testFileNearest! -> Bool
  (let [(root (resultOr (realPath "asl/packages/asl-forms/tests/fixtures/ws") ""))]
    (assert (= (w/wireReceipt! (ws root) "  (:step :id 1 :op \"read\" :status \"rejected\" :error-code \":ERR_FILE_NOT_FOUND\" :message \"File not found: sub/unique.tx\")" true "read")
               "(:read :status :rejected :error ERR_FILE_NOT_FOUND :message \"File not found: sub/unique.tx\" :nearest (\"sub/unique.txt\" \"sub/dup.txt\") :hint \"paths resolve against the workspace root; :nearest, when present, names entries beside the missing one\" :see \"(:help :op read)\")")
            "a missing file names close siblings")
    true)

fn ! runTests -> Bool
  (do
    (assert (testWireError) "testWireError")
    (assert (testCamel) "testCamel")
    (assert (testStepReceipts!) "testStepReceipts")
    (assert (testFileNearest!) "testFileNearest")
    true)
