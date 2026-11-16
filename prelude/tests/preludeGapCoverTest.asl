(module asl/prelude/tests/preludeGapCoverTest
  :x [runTests]
  :i [])

fn ! testCheckedDiv -> Bool
  (do
    (assert (= (checkedDiv 6 3) (some 2)) "checkedDiv normal: 6/3 is some 2")
    (assert (= (checkedDiv 7 3) (some 2)) "checkedDiv non-exact division: 7/3 is some 2")
    (assert (= (checkedDiv -7 3) (some -3)) "checkedDiv negative dividend floors: -7/3 is some -3")
    (assert (= (checkedDiv 7 -3) (some -3)) "checkedDiv negative divisor floors: 7/-3 is some -3")
    (assert (= (checkedDiv -7 -3) (some 2)) "checkedDiv both negative floors: -7/-3 is some 2")
    (assert (= (checkedDiv 0 5) (some 0)) "checkedDiv zero dividend: 0/5 is some 0")
    (assert (= (checkedDiv 1 0) none) "checkedDiv by zero gives none, not a trap")
    (assert (= (checkedDiv -9223372036854775808 -1) none) "checkedDiv Int64 overflow boundary (-min/-1) gives none")
    true)

fn ! testCheckedMod -> Bool
  (do
    (assert (= (checkedMod 7 3) (some 1)) "checkedMod normal: 7 mod 3 is some 1")
    (assert (= (checkedMod 6 3) (some 0)) "checkedMod exact division: 6 mod 3 is some 0")
    (assert (= (checkedMod -7 3) (some 2)) "checkedMod negative dividend follows divisor sign: -7 mod 3 is some 2")
    (assert (= (checkedMod 7 -3) (some -2)) "checkedMod negative divisor: 7 mod -3 is some -2")
    (assert (= (checkedMod 0 5) (some 0)) "checkedMod zero dividend: 0 mod 5 is some 0")
    (assert (= (checkedMod 1 0) none) "checkedMod by zero gives none, not a trap")
    true)

fn ! testListMin -> Bool
  (do
    (assert (= (listMin (list)) none) "listMin of an empty list is none")
    (assert (= (listMin (list 4)) (some 4)) "listMin of a single-element list is that element")
    (assert (= (listMin (list 3 1 2)) (some 1)) "listMin picks the smallest element")
    (assert (= (listMin (list 3 3 3)) (some 3)) "listMin with duplicates returns the duplicated value")
    (assert (= (listMin (list -5 2 -9 0)) (some -9)) "listMin with negatives picks the most negative")
    true)

fn ! testListMax -> Bool
  (do
    (assert (= (listMax (list)) none) "listMax of an empty list is none")
    (assert (= (listMax (list 4)) (some 4)) "listMax of a single-element list is that element")
    (assert (= (listMax (list 3 1 2)) (some 3)) "listMax picks the largest element")
    (assert (= (listMax (list 3 3 3)) (some 3)) "listMax with duplicates returns the duplicated value")
    (assert (= (listMax (list -5 2 -9 0)) (some 2)) "listMax with negatives picks the largest")
    true)

fn ! testOptionToResult -> Bool
  (do
    (assert (= (optionToResult (some 5) "missing") (ok 5)) "optionToResult of some is ok with the value")
    (assert (= (optionToResult none "missing") (err "missing")) "optionToResult of none is err with the error value")
    true)

fn ! runTests -> Bool
  (do
    (assert (testCheckedDiv) "checkedDiv: normal, negative operands, zero dividend, division by zero, Int64 overflow boundary")
    (assert (testCheckedMod) "checkedMod: normal, exact division, negative operands, zero dividend, division by zero")
    (assert (testListMin) "listMin: empty, single, normal, duplicates, negatives")
    (assert (testListMax) "listMax: empty, single, normal, duplicates, negatives")
    (assert (testOptionToResult) "optionToResult: some and none")
    true)
