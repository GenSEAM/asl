(module asl-runtime/tests/runtimeTest
  :x [testStableSort testFloatFormatting testRuntimeReExports runTests]
  :i [(asl-runtime :a rt)
      (asl-runtime/sort :a s)
      (asl-runtime/float :a fl)])

fn testStableSort -> Bool
  (let [(items (list "delta" "alpha" "gamma" "beta"))
        (sorted (s/rtStableSort items))]
    (do
      (assert (= (listLength sorted) 4) "sorted list length is 4")
      (assert (= (optionOr (listHead sorted) "") "alpha") "head is alpha")
      (assert (= (optionOr (listHead (optionOr (listTail sorted) (list))) "") "beta") "second is beta")
      true))

fn testFloatFormatting -> Bool
  (let [(fStr (fl/rtFormatF64 3.14159))]
    (do
      (assert (stringContains? fStr "3.14") "formatted float contains 3.14")
      true))

fn testRuntimeReExports -> Bool
  (let [(items (list "1" "2" "3" "4"))
        (taken (rt/listTake 2 items))]
    (do
      (assert (= (listLength taken) 2) "re-exported listTake takes 2 items")
      true))

fn ! runTests -> Bool
  (do
    (assert (testStableSort) "testStableSort")
    (assert (testFloatFormatting) "testFloatFormatting")
    (assert (testRuntimeReExports) "testRuntimeReExports")
    true)
