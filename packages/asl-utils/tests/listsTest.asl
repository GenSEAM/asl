(module asl-utils/tests/listsTest
  :x [runTests]
  :i [(asl-utils/lists :a l)])

; (:m :ref LISTS-TEST :do "binarySearch finds first, middle and last and reports absent and empty; lowerBound lands on the first duplicate; windows of 3 over 5 items are 3 and a window longer than the list is empty; groupAdjacent groups by parity; dedupSorted collapses runs; a 100000-element list is searched without stack growth")

fn emptyInts -> (List Int64)
  (list)

fn iota i: Int64 n: Int64 acc: (List Int64) -> (List Int64)
  (if (>= i n) (listReverse acc) (iota (+ i 1) n (cons i acc)))

fn ! testBinarySearch -> Bool
  (let [(xs (list 1 3 5 7 9))]
    (do (assert (= (l/binarySearch xs 5) (some 2)) "binarySearch finds the middle element")
        (assert (= (l/binarySearch xs 1) (some 0)) "binarySearch finds the first element")
        (assert (= (l/binarySearch xs 9) (some 4)) "binarySearch finds the last element")
        (assert (= (l/binarySearch xs 4) (none)) "binarySearch reports an absent value")
        (assert (= (l/binarySearch (emptyInts) 1) (none)) "binarySearch on an empty list is none")
        true))

fn ! testLowerBound -> Bool
  (let [(xs (list 1 2 2 2 3))]
    (do (assert (= (l/lowerBound xs 2) 1) "lowerBound of duplicates is the first duplicate")
        (assert (= (l/lowerBound xs 0) 0) "lowerBound below every element is 0")
        (assert (= (l/lowerBound xs 3) 4) "lowerBound of the last element is its index")
        (assert (= (l/lowerBound xs 4) 5) "lowerBound above every element is the length")
        true))

fn ! testWindows -> Bool
  (let [(xs (list 1 2 3 4 5))]
    (do (assert (= (listLength (l/windows xs 3)) 3) "five items with n=3 give three windows")
        (assert (= (l/windows xs 3) (list (list 1 2 3) (list 2 3 4) (list 3 4 5))) "the windows are contiguous and in order")
        (assert (listEmpty? (l/windows xs 6)) "n greater than the length gives no windows")
        (assert (listEmpty? (l/windows xs 0)) "n=0 gives no windows")
        true))

fn ! testGroupAdjacent -> Bool
  (let [(xs (list 1 3 5 2 4 7))]
    (do (assert (= (l/groupAdjacent xs (fn [x] (mod x 2))) (list (list 1 3 5) (list 2 4) (list 7))) "groupAdjacent groups consecutive equal keys")
        (assert (listEmpty? (l/groupAdjacent (emptyInts) (fn [x] (mod x 2)))) "groupAdjacent of an empty list is empty")
        true))

fn ! testDedupSorted -> Bool
  (do (assert (= (l/dedupSorted (list 1 1 2 2 2 3)) (list 1 2 3)) "dedupSorted collapses runs")
      (assert (= (l/dedupSorted (list 4 4 4)) (list 4)) "dedupSorted of one run is one element")
      (assert (listEmpty? (l/dedupSorted (emptyInts))) "dedupSorted of an empty list is empty")
      true)

fn ! testLarge -> Bool
  (let [(big (iota 0 100000 (list)))]
    (do (assert (= (listLength big) 100000) "the large list has 100000 elements")
        (assert (= (l/binarySearch big 99999) (some 99999)) "binarySearch finds the last of 100000")
        (assert (= (l/binarySearch big 0) (some 0)) "binarySearch finds the first of 100000")
        (assert (= (l/binarySearch big 100000) (none)) "binarySearch reports absent past the end of 100000")
        true))

fn ! runTests -> Bool
  (do (assert (testBinarySearch) "binarySearch: found, absent, first, last, empty")
      (assert (testLowerBound) "lowerBound: duplicates and the ends")
      (assert (testWindows) "windows: 3 over 5 items, and n greater than the length")
      (assert (testGroupAdjacent) "groupAdjacent: by parity")
      (assert (testDedupSorted) "dedupSorted: runs collapse")
      (assert (testLarge) "binarySearch: 100000 elements")
      true)
