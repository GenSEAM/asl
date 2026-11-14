(module asl-checker/tests/hintsForeignPriorsTest
  :x [runTests]
  :i [(asl-forms/check :a chk)])

fn ! receiptOf! body: String -> String
  (chk/checkFileReceipt! 1 "check" "asl/packages/asl-checker/tests/hintsForeignPriorsTmp.asl" "x" (str "(module hintsForeignPriorsTmp :x [f])\n\nfn f xs: (List Int64) s: String -> Int64\n  " body "\n"))

fn ! hasHint! body: String word: String -> Bool
  (let [(r (receiptOf! body))]
    (and (stringContains? r ":hint \"") (stringContains? r word)))

fn ! runTests -> Bool
  (do
    (assert (hasHint! "(len xs)" "listLength") "len names listLength")
    (assert (hasHint! "(len s)" "stringLength") "len also names stringLength")
    (assert (hasHint! "(string_length s)" "stringLength") "string_length names stringLength")
    (assert (hasHint! "(string_length s)" "did you mean stringLength (canonical") "string_length is named by the table, not by edit distance")
    (assert (hasHint! "(nil)" "did you mean none") "nil names none")
    (assert (hasHint! "(defn g)" "fn name") "defn names the fn header line")
    (assert (hasHint! "(every xs)" "listAll?") "every names listAll?")
    (assert (hasHint! "(any xs)" "listAny?") "any names listAny?")
    (assert (hasHint! "(first xs)" "listHead") "first names listHead")
    (assert (hasHint! "(rest xs)" "listTail") "rest names listTail")
    (assert (hasHint! "(nth xs 0)" "listGet") "nth names listGet")
    (assert (hasHint! "(substr s 0 1)" "stringSlice") "substr names stringSlice")
    (assert (not (stringContains? (receiptOf! "(len xs)") "nearest known name")) "the prior table wins over the edit-distance guess")
    (assert (not (stringContains? (receiptOf! "(listLength xs)") ":hint")) "a canonical call has no hint")
    true)
