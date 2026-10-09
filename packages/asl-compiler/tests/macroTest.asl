(module asl-compiler/tests/macroTest
  :x [testLetPair testIfLet testWhenLet testCond testCase testLetStar testPipe runTests RunTests]
  :i [(asl-compiler/macro :a mac)])

fn testLetPair -> Bool
  (let [(expanded (mac/expandLetPair "key" "val" "getPair" "(+ val 1)"))]
    (do
      (assert (stringContains? expanded "let [(__pair getPair)") "let-pair binds temporary pair")
      (refute (not (stringContains? expanded "let [(__pair getPair)")) "refutes missing temp pair")
      (assert (stringContains? expanded "(key (pairFirst __pair))") "let-pair extracts first")
      (assert (stringContains? expanded "(val (pairSecond __pair))") "let-pair extracts second")
      (assert (stringContains? expanded "(+ val 1)") "let-pair embeds body")
      true))

fn testIfLet -> Bool
  (let [(expanded (mac/expandIfLet "item" "fetchItem" "(process item)" "fallback"))]
    (do
      (assert (stringContains? expanded "mt fetchItem") "if-let matches on option expression")
      (refute (not (stringContains? expanded "mt fetchItem")) "refutes missing mt match")
      (assert (stringContains? expanded "((some item) (process item))") "if-let binds some branch")
      (assert (stringContains? expanded "((none) fallback)") "if-let binds none fallback branch")
      true))

fn testWhenLet -> Bool
  (let [(expanded (mac/expandWhenLet "cfg" "loadConfig" "(start cfg)"))]
    (do
      (assert (stringContains? expanded "mt loadConfig") "when-let desugars through mt")
      (refute (not (stringContains? expanded "mt loadConfig")) "refutes missing mt in when-let")
      (assert (stringContains? expanded "((some cfg) (start cfg))") "when-let executes body on some")
      (assert (stringContains? expanded "((none) (none))") "when-let yields none on missing")
      true))

fn testCond -> Bool
  (let [(clauses (list (pair "(= x 1)" "\"one\"") (pair "(= x 2)" "\"two\"")))
        (expanded (mac/expandCond clauses "\"other\""))]
    (do
      (assert (stringContains? expanded "(if (= x 1) \"one\"") "first cond clause converted to if")
      (refute (not (stringContains? expanded "(if (= x 1) \"one\"")) "refute missing first cond clause")
      (assert (stringContains? expanded "(if (= x 2) \"two\" \"other\")") "nested fallback cond clause converted")
      true))

fn testCase -> Bool
  (let [(arms (list (pair "\"a\"" "10") (pair "\"b\"" "20")))
        (expanded (mac/expandCase "code" arms "0"))]
    (do
      (assert (stringContains? expanded "let [(__case_target code)]") "case binds target expression")
      (refute (not (stringContains? expanded "let [(__case_target code)]")) "refute missing case target binding")
      (assert (stringContains? expanded "(= __case_target \"a\") 10") "first case arm matches")
      (assert (stringContains? expanded "(= __case_target \"b\") 20 0") "second case arm matches with fallback")
      true))

fn testLetStar -> Bool
  (let [(bindings (list (pair "x" "1") (pair "y" "(+ x 2)")))
        (expanded (mac/expandLetStar bindings "(* x y)"))]
    (do
      (assert (stringContains? expanded "(let [(x 1)]") "let* binds first variable sequentially")
      (assert (stringContains? expanded "(let [(y (+ x 2))]") "let* binds second variable in inner scope")
      (assert (stringContains? expanded "(* x y)") "let* embeds innermost body")
      (refute (!= (mac/expandLetStar (list) "42") "42") "empty let* returns body directly")
      true))

fn testPipe -> Bool
  (let [(forms (list "(add 2)" "(mul 3)"))
        (expanded (mac/expandPipe "10" forms))]
    (do
      (assert (stringContains? expanded "mul") "pipeline embeds outer mul")
      (assert (stringContains? expanded "add") "pipeline embeds inner add")
      (refute (!= (mac/expandPipe "42" (list)) "42") "empty pipe returns initial value directly")
      true))

fn runTests -> Bool
  (do
    (assert (testLetPair) "testLetPair")
    (assert (testIfLet) "testIfLet")
    (assert (testWhenLet) "testWhenLet")
    (assert (testCond) "testCond")
    (assert (testCase) "testCase")
    (assert (testLetStar) "testLetStar")
    (assert (testPipe) "testPipe")
    true)

fn RunTests -> Bool
  (runTests)
