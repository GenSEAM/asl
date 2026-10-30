(module asl-intel/tests/sliceStrTest :x [runTests] :i [(asl-intel/text :a tx)])

; (:m :ref COVRATCHET :do "sliceStr clamps both bounds instead of failing; takeN stops at the list end")
fn runTests -> Bool
  (do
    (assert (= (tx/sliceStr "hello" 1 3) "el") "inner slice")
    (assert (= (tx/sliceStr "hello" 0 5) "hello") "whole string")
    (assert (= (tx/sliceStr "hello" -3 2) "he") "a negative start clamps to 0")
    (assert (= (tx/sliceStr "hello" 3 99) "lo") "an end past the string clamps to its length")
    (assert (= (tx/sliceStr "hello" 4 2) "") "start after end is empty")
    (assert (= (tx/sliceStr "hello" 2 2) "") "equal bounds are empty")
    (assert (= (tx/sliceStr "hello" 9 12) "") "both bounds past the end are empty")
    (assert (= (tx/sliceStr "" 0 3) "") "empty string")
    (assert (= (tx/takeN (list 1 2 3) 2) (list 1 2)) "takeN takes a prefix")
    (assert (= (tx/takeN (list 1 2) 5) (list 1 2)) "takeN past the end returns all")
    (assert (= (tx/takeN (list 1 2) 0) (list)) "takeN zero is empty")
    (assert (= (tx/takeN (list 1 2) -1) (list)) "takeN of a negative count is empty")
    (assert (= (tx/takeN (list) 3) (list)) "takeN of empty")
    true)
