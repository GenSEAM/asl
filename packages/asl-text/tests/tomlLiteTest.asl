(module asl-text/tests/tomlLiteTest
  :x [runTests]
  :i [(asl-text/tomlLite :a tl)])

fn testClassify -> Bool
  (do (assert (= (tl/classify "\"hi\"") (ok "string")) "string kind")
      (assert (= (tl/classify "\"\"") (ok "string")) "empty string kind")
      (assert (= (tl/classify "42") (ok "int")) "int kind")
      (assert (= (tl/classify "-7") (ok "int")) "negative int kind")
      (assert (= (tl/classify "3.14") (ok "float")) "float kind")
      (assert (= (tl/classify "true") (ok "bool")) "bool kind")
      (assert (= (tl/classify "false") (ok "bool")) "false bool kind")
      (assert (= (tl/classify "[1, 2]") (ok "array")) "array kind")
      (assert (= (tl/classify "[]") (ok "array")) "empty array kind")
      (assert (= (tl/classify "[\"x,y\", \"z\"]") (ok "array")) "comma inside string element")
      (assert (= (tl/classify "[1,]") (ok "array")) "trailing comma allowed")
      (assert (= (tl/classify "\"abc\\\"") (err "unterminated string")) "escaped final quote unterminated")
      (assert (err? (tl/classify "[1,,2]")) "empty element rejected")
      (assert (err? (tl/classify "[[1]]")) "nested array rejected")
      (assert (err? (tl/classify "abc")) "bare word rejected")
      (assert (err? (tl/classify "1.2.3")) "double dot rejected")
      (assert (err? (tl/classify "\"a\"b\"")) "interior quote rejected")
      true)

fn testRow -> Bool
  (do (assert (= (tl/row "t" "k" "v" "int") "(:row :table \"t\" :key \"k\" :value \"v\" :kind \"int\")") "row format")
      (assert (stringContains? (tl/row "t" "k" "a\"b" "string") "a\\\"b") "quote escaped in row")
      (assert (stringContains? (tl/row "t" "k" "a\\b" "string") "a\\\\b") "backslash escaped in row")
      true)

fn testParse -> Bool
  (let [(rows (tl/parse "# comment\n\n[server]\nhost = \"web\"\nport = 8080\narr = [\"web\", \"db\"]\nbad = \"abc\\\"\n"))]
    (do (assert (= (listLength rows) 4) "four results")
        (assert (listAll? ok? (listTake rows 3)) "first three rows ok")
        (assert (stringContains? (resultOr (optionOr (listGet rows 0) (ok "")) "") ":table \"server\"") "table tracked")
        (assert (stringContains? (resultOr (optionOr (listGet rows 2) (ok "")) "") ":value \"[\\\"web\\\", \\\"db\\\"]\"") "array value escaped")
        (assert (match (listGet rows 3)
                  ((some r) (match r ((ok s) false) ((err e) (and (= e.line 7) (= e.msg "unterminated string")))))
                  ((none) false))
                "error carries line 7")
        true))

fn testLine -> Bool
  (do (assert (= (tl/parseLine 2 "" "x = 1") (ok "(:row :table \"\" :key \"x\" :value \"1\" :kind \"int\")")) "parseLine ok row")
      (assert (match (tl/parseLine 5 "t" "noequals") ((ok s) false) ((err e) (and (= e.line 5) (= e.msg "expected key = value")))) "missing equals error")
      (assert (match (tl/parseLine 3 "t" "bad key = 1") ((ok s) false) ((err e) (and (= e.line 3) (= e.msg "invalid key")))) "invalid key error")
      (assert (match (listHead (tl/parse "[bad")) ((some r) (match r ((ok s) false) ((err e) (and (= e.line 1) (= e.msg "invalid table"))))) ((none) false)) "unterminated table header error")
      (assert (match (listGet (tl/parse "x = 1\ny = z") 1) ((some r) (match r ((ok s) false) ((err e) (= e.line 2)))) ((none) false)) "second line error is line 2")
      true)

fn runTests -> Bool
  (and (testClassify) (testRow) (testParse) (testLine))
