(module asl-utils/tests/binaryHeapTest
  :x [runTests]
  :i [(asl-utils/binaryHeap :a bh)])

fn cmpInt a: Int64 b: Int64 -> Int64
  (if (< a b) -1 (if (> a b) 1 0))

fn cmpRev a: Int64 b: Int64 -> Int64
  (cmpInt b a)

fn sortedBy xs: (List Int64) -> (List Int64)
  (listSortBy (fn [(x Int64)] -> Int64 x) xs)

fn drain cmp: (fn [Int64 Int64] -> Int64) h: (List Int64) -> (List Int64)
  (let [(p (bh/pop cmp h))
        (m (pairFirst p))]
    (if (none? m)
      (list)
      (cons (optionOr m 0) (drain cmp (pairSecond p)))))

fn testSort -> Bool
  (let [(xs (list 5 3 8 1 9 2 7 4 6 3 0 5))
        (ys (list 10 -3 7 7 0 2 -3 8 1))]
    (do (assert (= (bh/toSortedList cmpInt (bh/fromList cmpInt xs)) (sortedBy xs)) "heap sort matches listSortBy")
        (assert (= (bh/toSortedList cmpInt (bh/fromList cmpInt ys)) (sortedBy ys)) "duplicates and negatives sort")
        (assert (= (bh/toSortedList cmpInt (bh/fromList cmpInt (list))) (list)) "empty heap sorts to empty")
        (assert (= (drain cmpInt (bh/fromList cmpInt xs)) (sortedBy xs)) "repeated pop drains in order")
        (assert (= (bh/toSortedList cmpRev (bh/fromList cmpRev xs)) (listReverse (sortedBy xs))) "explicit compare reverses order")
        true))

fn testOps -> Bool
  (let [(h0 (bh/fromList cmpInt (list 3 1 2)))
        (p1 (bh/pop cmpInt h0))
        (h1 (bh/push cmpInt h0 0))]
    (do (assert (= (bh/peek h0) (some 1)) "peek returns the min")
        (assert (= (pairFirst p1) (some 1)) "pop returns the min")
        (assert (= (bh/peek (pairSecond p1)) (some 2)) "next min after pop")
        (assert (= (bh/peek h1) (some 0)) "push can lower the min")
        (assert (= (bh/peek (bh/fromList cmpInt (list))) (none)) "peek on empty is none")
        (assert (= (pairFirst (bh/pop cmpInt (bh/fromList cmpInt (list)))) (none)) "pop on empty is none")
        (assert (= (bh/peek (pairSecond (bh/pop cmpInt (bh/fromList cmpInt (list 4))))) (none)) "popping a singleton empties the heap")
        (assert (= (bh/peek h0) (some 1)) "push and pop leave the original heap unchanged")
        true))

fn runTests -> Bool
  (and (testSort) (testOps))
