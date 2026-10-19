(module prelude/tests/preludeListPassesTest :x [runTests] :i [])

fn ! testEnumerateCorrectness -> Bool
  (do
    (assert (= (enumerate (list)) (list)) "enumerate of an empty list is empty")
    (assert (= (enumerate (list "a")) (list (pair 0 "a"))) "enumerate of a single-element list pairs it with 0")
    (assert (= (enumerate (list "a" "b" "c")) (list (pair 0 "a") (pair 1 "b") (pair 2 "c"))) "enumerate pairs each element with its index in order")
    true)

fn ! testListLastCorrectness -> Bool
  (do
    (assert (= (listLast (list)) none) "listLast of an empty list is none")
    (assert (= (listLast (list 1)) (some 1)) "listLast of a single-element list is that element")
    (assert (= (listLast (list 1 2 3)) (some 3)) "listLast returns the final element")
    (assert (= (listLast (list "a" "b" "c" "d")) (some "d")) "listLast works over strings too")
    true)

fn ! runTests -> Bool
  (do
    (assert (testEnumerateCorrectness) "enumerate: empty, singleton, multi-element order")
    (assert (testListLastCorrectness) "listLast: empty, singleton, multi-element, strings")
    true)
