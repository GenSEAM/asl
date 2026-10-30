(module asl-runtime/tests/stableSortByTest :x [runTests] :i [(asl-runtime/sort :a s)])

; (:m :ref COVRATCHET :do "rtStableSortBy: order by a caller comparison, stability for equal keys, empty, one, sorted and reversed input")
fn firstByte x: Str -> Str
  (optionOr (stringSlice x 0 1) "")

fn byFirst a: Str b: Str -> Bool
  (<= (firstByte a) (firstByte b))

fn descending a: Str b: Str -> Bool
  (>= a b)

fn runTests -> Bool
  (do
    (assert (= (s/rtStableSortBy (list) byFirst) (list)) "empty stays empty")
    (assert (= (s/rtStableSortBy (list "a") byFirst) (list "a")) "one item stays")
    (assert (= (s/rtStableSortBy (list "b1" "a1" "b0" "a0" "c") byFirst) (list "a1" "a0" "b1" "b0" "c")) "equal keys keep their input order")
    (assert (= (s/rtStableSortBy (list "a" "b" "c") byFirst) (list "a" "b" "c")) "sorted input is unchanged")
    (assert (= (s/rtStableSortBy (list "c" "b" "a") byFirst) (list "a" "b" "c")) "reversed input is sorted")
    (assert (= (s/rtStableSortBy (list "a" "c" "b") descending) (list "c" "b" "a")) "a descending comparison reverses the order")
    (assert (= (s/rtStableSortBy (list "x" "x") byFirst) (list "x" "x")) "duplicates survive")
    (assert (= (listLength (s/rtStableSortBy (list "d" "a" "c" "b" "e" "a" "z" "y" "x") byFirst)) 9) "no item is lost or added")
    (assert (= (s/rtStableSortBy (list "d" "a" "c" "b" "e" "a" "z" "y" "x") byFirst) (list "a" "a" "b" "c" "d" "e" "x" "y" "z")) "nine items sort across several merge levels")
    true)
