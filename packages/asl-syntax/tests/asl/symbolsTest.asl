(module asl-syntax/tests/asl/symbolsTest
  :x [runTests]
  :i [(asl-syntax/asl/symbols :a asym)
      (asl-syntax/core/symbols :a sym)
      (asl-syntax/core/outline :a out)
      (asl-syntax/core/source :a src)])

fn testParenSymbols -> Bool
  (let [(code "(module foo/bar :d \"doc\" :x [add])\n\n(schema Point\n  (:f x Int64)\n  (:f y Int64))\n\n(enum Color\n  (red)\n  (green)\n  (blue))\n\n(defn add a: Int64 b: Int64 -> Int64\n  (+ a b))\n\n(:task :id myTask :status :done)\n\n(:op :read :params [foo])\n")
        (syms (asym/extractSymbols code))]
    (assert (= (listLength syms) 5) "extracted 5 symbols")
    (let [(s1 (optionOr (listGet syms 0) (asym/makeAslSymbol "" "" 0 0 0 0 0 "")))
          (s2 (optionOr (listGet syms 1) (asym/makeAslSymbol "" "" 0 0 0 0 0 "")))
          (s3 (optionOr (listGet syms 2) (asym/makeAslSymbol "" "" 0 0 0 0 0 "")))
          (s4 (optionOr (listGet syms 3) (asym/makeAslSymbol "" "" 0 0 0 0 0 "")))
          (s5 (optionOr (listGet syms 4) (asym/makeAslSymbol "" "" 0 0 0 0 0 "")))]
      (assert (= (asym/aslSymbolKind s1) "schema") "s1 kind is schema")
      (assert (= (asym/aslSymbolName s1) "Point") "s1 name is Point")
      (assert (= (asym/aslSymbolStartLine s1) 3) "s1 startLine is 3")
      (assert (= (asym/aslSymbolEndLine s1) 5) "s1 endLine is 5")

      (assert (= (asym/aslSymbolKind s2) "enum") "s2 kind is enum")
      (assert (= (asym/aslSymbolName s2) "Color") "s2 name is Color")
      (assert (= (asym/aslSymbolStartLine s2) 7) "s2 startLine is 7")
      (assert (= (asym/aslSymbolEndLine s2) 10) "s2 endLine is 10")

      (assert (= (asym/aslSymbolKind s3) "defn") "s3 kind is defn")
      (assert (= (asym/aslSymbolName s3) "add") "s3 name is add")
      (assert (= (asym/aslSymbolStartLine s3) 12) "s3 startLine is 12")
      (assert (= (asym/aslSymbolEndLine s3) 13) "s3 endLine is 13")

      (assert (= (asym/aslSymbolKind s4) "task") "s4 kind is task")
      (assert (= (asym/aslSymbolName s4) "myTask") "s4 name is myTask")

      (assert (= (asym/aslSymbolKind s5) "op") "s5 kind is op")
      (assert (= (asym/aslSymbolName s5) "read") "s5 name is read"))
    true)

fn testIndentedSymbols -> Bool
  (let [(code "fn myFunc a: Int64 -> Bool\n  (if (> a 0)\n    true\n    false)\n\nfn secondFunc -> Int64\n  42\n")
        (syms (asym/extractSymbols code))]
    (assert (= (listLength syms) 2) "extracted 2 indented functions")
    (let [(s1 (optionOr (listGet syms 0) (asym/makeAslSymbol "" "" 0 0 0 0 0 "")))
          (s2 (optionOr (listGet syms 1) (asym/makeAslSymbol "" "" 0 0 0 0 0 "")))]
      (assert (= (asym/aslSymbolKind s1) "fn") "s1 is fn")
      (assert (= (asym/aslSymbolName s1) "myFunc") "s1 name is myFunc")
      (assert (= (asym/aslSymbolStart s1) 0) "s1 start offset is 0")
      (assert (= (asym/aslSymbolStartLine s1) 1) "s1 start line is 1")
      (assert (= (asym/aslSymbolEndLine s1) 4) "s1 end line is 4")

      (assert (= (asym/aslSymbolKind s2) "fn") "s2 is fn")
      (assert (= (asym/aslSymbolName s2) "secondFunc") "s2 name is secondFunc")
      (assert (= (asym/aslSymbolStartLine s2) 6) "s2 start line is 6")
      (assert (= (asym/aslSymbolEndLine s2) 7) "s2 end line is 7"))
    true)

fn testDottedLookup -> Bool
  (let [(code "(:plan :id foreignSyntax\n  (:unit :id K0 :status :done)\n  (:unit :id A5 :status :inProgress))\n\n(:plan :id parserSyntax\n  (:unit :id A5 :status :done))\n")
        (syms (asym/extractSymbols code))
        (q1 (asym/findSymbolDotted syms "foreignSyntax"))
        (q2 (asym/findSymbolDotted syms ":foreignSyntax.A5"))
        (q3 (asym/findSymbolDotted syms "parserSyntax.A5"))
        (q4 (asym/findSymbolDotted syms "foreignSyntax.nonExistent"))]
    (assert (some? q1) "finds plan foreignSyntax")
    (assert (some? q2) "finds foreignSyntax.A5")
    (assert (some? q3) "finds parserSyntax.A5")
    (assert (not (some? q4)) "rejects foreignSyntax.nonExistent")
    (mt q2
      ((some s)
       (do
         (assert (= (asym/aslSymbolName s) "A5") "q2 name is A5")
         (assert (= (asym/aslSymbolContainer s) "foreignSyntax") "q2 container is foreignSyntax")))
      ((none) (assert false "expected some q2")))
    (mt q3
      ((some s)
       (do
         (assert (= (asym/aslSymbolName s) "A5") "q3 name is A5")
         (assert (= (asym/aslSymbolContainer s) "parserSyntax") "q3 container is parserSyntax")))
      ((none) (assert false "expected some q3")))
    true)

fn testNearestSymbols -> Bool
  (let [(code "fn calculateTotal amount: Int64 -> Int64\n  amount\n\nfn calculateTax amount: Int64 -> Int64\n  0\n\nfn printReport -> Bool\n  true\n")
        (syms (asym/extractSymbols code))
        (n1 (asym/nearestSymbols "calcTotal" syms 2))]
    (assert (listContains? n1 "calculateTotal") "nearest includes calculateTotal")
    (assert (<= (listLength n1) 2) "nearest returns <= 2")
    true)

fn testOutlineReceipt -> Bool
  (let [(code "fn greet name: String -> String\n  (str \"Hello, \" name)\n")
        (receipt (asym/aslOutlineReceipt "greet.asl" "asl" code))]
    (assert (stringContains? receipt "(:outline :status :ok :file \"greet.asl\"") "receipt status ok")
    (assert (stringContains? receipt ":name \"greet\"") "receipt contains symbol name")
    (assert (stringContains? receipt ":kind \"fn\"") "receipt contains kind fn")
    (assert (stringContains? receipt ":start 1 :end 2") "receipt contains line range 1 to 2")
    true)

fn testBlankIdSkipped -> Bool
  (let [(names (map asym/aslSymbolName (asym/extractSymbols "(:inside :id \" \" :want true)\n(:inside :id \"\" :want true)\n(:inside :id \"ok\" :want true)\n")))]
    (do
      (assert (= names (list "ok")) (str "only the non-blank id is a symbol, got " (stringJoin names ",")))
      true))

fn ! runTests -> Bool
  (and (testBlankIdSkipped)
  (and (testParenSymbols)
  (and (testIndentedSymbols)
  (and (testDottedLookup)
  (and (testNearestSymbols)
       (testOutlineReceipt))))))
