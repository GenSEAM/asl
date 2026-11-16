(module asl-runtime/tests/sortCoverTest
  :x [runTests]
  :i [(asl-runtime/sort :a s)])

fn asc a: Str b: Str -> Bool
  (<= a b)

fn firstKeyLt a: Str b: Str -> Bool
  (<= (optionOr (stringSlice a 0 1) "") (optionOr (stringSlice b 0 1) ""))

fn runTests -> Bool
  (do
    (assert (= (s/rtStableSortBy (list "pear" "apple" "fig") asc) (list "apple" "fig" "pear")) "normal: three items sort ascending")
    (assert (= (optionOr (listGet (s/rtStableSortBy (list "pear" "apple" "fig") asc) 0) "") "apple") "normal: slot 0 is apple")
    (assert (= (optionOr (listGet (s/rtStableSortBy (list "pear" "apple" "fig") asc) 2) "") "pear") "normal: slot 2 is pear")
    (assert (= (s/rtStableSortBy (list) asc) (list)) "boundary zero: empty input stays empty")
    (assert (match (listGet (s/rtStableSortBy (list) asc) 0) ((none) true) ((some _) false)) "none path: empty result has no head")
    (assert (= (s/rtStableSortBy (list "only") asc) (list "only")) "boundary one: single element returned")
    (assert (= (listLength (s/rtStableSortBy (list "only") asc)) 1) "boundary one: length preserved")
    (assert (= (s/rtStableSortBy (list "b" "a" "b" "a" "c") asc) (list "a" "a" "b" "b" "c")) "dups: duplicates sort with values kept")
    (assert (= (optionOr (listGet (s/rtStableSortBy (list "b" "a" "b" "a" "c") asc) 4) "") "c") "dups: last slot is c")
    (assert (= (s/rtStableSortBy (list "h" "g" "f" "e" "d" "c" "b" "a") asc) (list "a" "b" "c" "d" "e" "f" "g" "h")) "max: eight items sort across merge levels")
    (assert (= (listLength (s/rtStableSortBy (list "h" "g" "f" "e" "d" "c" "b" "a") asc)) 8) "max: length preserved on 8 elements")
    (assert (= (optionOr (listGet (s/rtStableSortBy (list "h" "g" "f" "e" "d" "c" "b" "a") asc) 7) "") "h") "max: last slot is h")
    (assert (= (s/rtStableSortBy (list "b1" "a1" "b2" "a2") firstKeyLt) (list "a1" "a2" "b1" "b2")) "stability: equal keys keep input order")
    (assert (= (optionOr (listGet (s/rtStableSortBy (list "b1" "a1" "b2" "a2") firstKeyLt) 0) "") "a1") "stability: slot 0 is a1")
    (assert (= (optionOr (listGet (s/rtStableSortBy (list "b1" "a1" "b2" "a2") firstKeyLt) 3) "") "b2") "stability: slot 3 is b2")
    (assert (= (s/rtStableSortBy (list) firstKeyLt) (list)) "boundary zero: empty input with key comparator stays empty")
    (assert (match (listGet (s/rtStableSortBy (list "b" "a") asc) 5) ((none) true) ((some _) false)) "none path: out-of-range slot on sorted result is none")
    (assert (= (s/rtStableSortBy (list "m" "m" "m") asc) (list "m" "m" "m")) "boundary max-equal: all-equal keys keep values in order")
    (assert (= (optionOr (listGet (s/rtStableSortBy (list "m" "m" "m") asc) 1) "") "m") "boundary max-equal: middle slot is m")
    true)
