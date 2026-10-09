(module asl-parser/tailrecHeaderNormalizationTest
  :x [runTests]
  :i [(asl-parser/ast :a a)])

fn runTests -> Bool
  (do
    (assert (= (a/joinFnHeader "fn tailrec tailCond n: Int64 -> Int64") "fn tailCond n: Int64 -> Int64") "leading tailrec is removed for indent parsing")
    (assert (= (a/joinFnHeader "fn :tailrec tailCond n: Int64 -> Int64") "fn tailCond n: Int64 -> Int64") "leading :tailrec is removed for indent parsing")
    (assert (= (a/joinFnHeader "fn ordinary n: Int64 -> Int64\n  n\n") "fn ordinary n: Int64 -> Int64\n  n\n") "unchanged fn text is preserved byte-for-byte")
    true)
