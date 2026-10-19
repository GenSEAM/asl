(module prelude/tests/preludeMissingBuiltinsTest :x [runTests] :i [])

fn ! testListFind -> Bool
  (do
    (assert (= (listFind (fn [(x Int64)] -> Bool (> x 2)) (list 1 2 3 4)) (some 3)) "listFind returns the first matching element")
    (assert (= (listFind (fn [(x Int64)] -> Bool (> x 10)) (list 1 2 3 4)) none) "listFind returns none when nothing matches")
    (assert (= (listFind (fn [(x Int64)] -> Bool (>= x 0)) (list)) none) "listFind of an empty list is none")
    (assert (= (listFind (fn [(x Int64)] -> Bool (= x 1)) (list 1 1 1)) (some 1)) "listFind returns the first of several matches")
    true)

fn ! testListCount -> Bool
  (do
    (assert (= (listCount (fn [(x Int64)] -> Bool (= (mod x 2) 0)) (list 1 2 3 4 5 6)) 3) "listCount counts matching elements")
    (assert (= (listCount (fn [(x Int64)] -> Bool (>= x 0)) (list)) 0) "listCount of an empty list is 0")
    (assert (= (listCount (fn [(x Int64)] -> Bool (< x 0)) (list 1 2 3)) 0) "listCount with no matches is 0")
    (assert (= (listCount (fn [(x Int64)] -> Bool (>= x 0)) (list 1 2 3)) 3) "listCount with every element matching equals the length")
    true)

fn ! testListFlatMap -> Bool
  (do
    (assert (= (listFlatMap (fn [(x Int64)] -> (List Int64) (list x x)) (list 1 2 3)) (list 1 1 2 2 3 3)) "listFlatMap concatenates each element's list in order")
    (assert (= (listFlatMap (fn [(x Int64)] -> (List Int64) (list)) (list 1 2 3)) (list)) "listFlatMap of an all-empty mapping is empty")
    (assert (= (listFlatMap (fn [(x Int64)] -> (List Int64) (list x)) (list)) (list)) "listFlatMap of an empty list is empty")
    (assert (= (listFlatMap (fn [(x Int64)] -> (List Int64) (if (= (mod x 2) 0) (list x) (list))) (list 1 2 3 4 5)) (list 2 4)) "listFlatMap can filter by returning an empty list per element")
    true)

fn ! testMapGetOr -> Bool
  (do
    (assert (= (mapGetOr (mapSet (mapEmpty) "a" 1) "a" 99) 1) "mapGetOr returns the stored value when the key is present")
    (assert (= (mapGetOr (mapSet (mapEmpty) "a" 1) "b" 99) 99) "mapGetOr returns the default when the key is absent")
    (assert (= (mapGetOr (mapEmpty) "a" 7) 7) "mapGetOr on an empty map returns the default")
    true)

fn ! runTests -> Bool
  (do
    (assert (testListFind) "listFind: first match, no match, empty list, first of duplicates")
    (assert (testListCount) "listCount: mixed matches, empty list, no matches, all matches")
    (assert (testListFlatMap) "listFlatMap: concatenation order, empty mappings, empty input, filtering via empty-list results")
    (assert (testMapGetOr) "mapGetOr: present key, absent key, empty map")
    true)
