(module asl-cli/tests/checkIndentDiagTest :x [runTests] :i [(asl/packages/asl-cli/src/verify :a verify)])

fn ! tempRoot -> String
  (str "/tmp/checkIndentDiagTest_" (stringFromInt64 (monotonicNs)))

fn ! receiptOf! dir: String name: String text: String -> String
  (let [(p (str dir "/" name))
        (_ (fileWrite p text))]
    (verify/balanceReceipt! p))

; (:m :do "the fn header line is not a form: one extra closer per body is the class most check failures come from")
fn testStrayAtBodyEnd dir: String r: String -> Bool
  (let [(path (str dir "/stray.asl"))]
    (do
      (assert (stringStartsWith? r (str "(:unbalanced :file \"" path "\" :line 5 :col 22 :ev \"unexpected )\"")) (str "the receipt names line and column, not a byte: " r))
      (assert (stringContains? r ":indent ((:delete \")\" :line 5 :col 22 :stray true))") (str "and the edit that repairs it: " r))
      (assert (stringContains? r ":by :indent :apply true)") (str "and the form that stages it: " r))
      (refute (stringContains? r ":byte") (str "no byte offset: " r))
      true))

fn testMissingCloserNamesOpener dir: String r: String -> Bool
  (let [(path (str dir "/missing.asl"))]
    (do
      (assert (stringContains? r ":ev \"unclosed (\"") (str "the checker's own verdict is kept: " r))
      (assert (stringContains? r "(:insert \")\" :line 5 :col 21 :opener (:line 4 :col 3 :head \"let\") :by (:line 7))") (str "the missing closer goes after line 5, opened by let on line 4, decided by line 7: " r))
      true))

fn testWrongKindNamesOpenerLine dir: String r: String -> Bool
  (let [(path (str dir "/bad.asn"))]
    (do
      (assert (stringContains? r ":line 1 :col 11 :ev \"] closes ( opened at 1:7\"") (str "the opener is named as line:col: " r))
      (assert (stringContains? r "(:replace \"]\" :with \")\" :line 1 :col 11") (str "the wrong kind is replaced: " r))
      true))

fn testBalancedHasNoReceipt dir: String r: String -> Bool
  (let [(path (str dir "/ok.asl"))]
    (do
      (assert (= r "") (str "a balanced file prints nothing: " r))
      true))

fn ! runTests -> Bool
  (let [(dir (tempRoot))
        (_ (dirCreate dir))
        (r1 (receiptOf! dir "stray.asl" "(module t/stray :x [f g] :i [])\n\nfn f x: Int64 -> Int64\n  (let [(y (+ x 1))]\n    (if (> y 2) y 0)))\n\nfn g x: Int64 -> Int64\n  (+ x 1)\n"))
        (r2 (receiptOf! dir "missing.asl" "(module t/missing :x [f g] :i [])\n\nfn f x: Int64 -> Int64\n  (let [(y (+ x 1))]\n    (if (> y 2) y 0)\n\nfn g x: Int64 -> Int64\n  (+ x 1)\n"))
        (r3 (receiptOf! dir "bad.asn" "(:bad (1 2]\n"))
        (r4 (receiptOf! dir "ok.asl" "(module t/ok :x [f] :i [])\n\nfn f x: Int64 -> Int64\n  (+ x 1)\n"))
        (_ (pathRemove dir))]
    (do
      (refute (fileExists? dir) "the scratch directory is removed before any assert can stop the test")
      (assert (testStrayAtBodyEnd dir r1) "testStrayAtBodyEnd")
      (assert (testMissingCloserNamesOpener dir r2) "testMissingCloserNamesOpener")
      (assert (testWrongKindNamesOpenerLine dir r3) "testWrongKindNamesOpenerLine")
      (assert (testBalancedHasNoReceipt dir r4) "testBalancedHasNoReceipt")
      true))
