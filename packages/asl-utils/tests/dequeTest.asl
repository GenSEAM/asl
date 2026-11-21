(module asl-utils/tests/dequeTest :x [runTests] :i [(asl-utils/deque :a dq)])

fn testBasic -> Bool
  (let [(d0 (dq/empty))
        (d1 (dq/pushBack (dq/pushFront d0 1) 2))
        (d2 (dq/pushFront d1 0))]
    (do (assert (= (dq/toList d0) (list)) "empty deque lists empty")
        (assert (= (dq/toList d2) (list 0 1 2)) "front/back order")
        (assert (= (dq/toList d1) (list 1 2)) "persistence: d1 unchanged")
        (assert (none? (dq/popFront d0)) "popFront empty is none")
        (assert (none? (dq/popBack d0)) "popBack empty is none")
        true))

fn popVal o: (Option (Pair Int64 dq/Deque)) -> Int64
  (match o
    ((some p) (pairFirst p))
    ((none) -1))

fn restList o: (Option (Pair Int64 dq/Deque)) -> (List Int64)
  (match o
    ((some p) (dq/toList (pairSecond p)))
    ((none) (list)))

fn testPops -> Bool
  (let [(d (dq/pushBack (dq/pushBack (dq/pushFront (dq/empty) 1) 2) 3))
        (pf (dq/popFront d))
        (d2 (optionOr (optionMap (fn [(p (Pair Int64 dq/Deque))] -> dq/Deque (pairSecond p)) pf) (dq/empty)))
        (pb (dq/popBack d2))]
    (do (assert (= (popVal pf) 1) "popFront yields 1")
        (assert (= (restList pf) (list 2 3)) "popFront rest")
        (assert (= (popVal pb) 3) "popBack yields 3")
        (assert (= (restList pb) (list 2)) "popBack rest")
        (assert (= (dq/toList d) (list 1 2 3)) "persistence after pops")
        true))

fn genOps n: Int64 seed: Int64 -> (List Int64)
  (if (= n 0)
    (list)
    (let [(s (mod (+ (* seed 1103515245) 12345) 2147483648))]
      (cons s (genOps (- n 1) s))))

fn stepBoth s: (Pair dq/Deque (List Int64)) op: Int64 -> (Pair dq/Deque (List Int64))
  (let [(d (pairFirst s)) (xs (pairSecond s)) (k (mod op 4))]
    (if (= k 0)
      (pair (dq/pushFront d op) (cons op xs))
      (if (= k 1)
        (pair (dq/pushBack d op) (listAppend xs (list op)))
        (if (= k 2)
          (match (dq/popFront d)
            ((some p) (do (assert (= (pairFirst p) (optionOr (listHead xs) -1)) "popFront value matches model")
                          (pair (pairSecond p) (optionOr (listTail xs) (list)))))
            ((none) (do (assert (listEmpty? xs) "popFront none only when model empty")
                        s)))
          (match (dq/popBack d)
            ((some p) (do (assert (= (pairFirst p) (optionOr (listLast xs) -1)) "popBack value matches model")
                          (pair (pairSecond p) (listTake xs (- (listLength xs) 1)))))
            ((none) (do (assert (listEmpty? xs) "popBack none only when model empty")
                        s)))))))

fn stepChecked s: (Pair dq/Deque (List Int64)) op: Int64 -> (Pair dq/Deque (List Int64))
  (let [(s2 (stepBoth s op))]
    (do (assert (= (dq/toList (pairFirst s2)) (pairSecond s2)) "deque matches list model after each op")
        s2))

fn testModel -> Bool
  (let [(final (fold stepChecked (pair (dq/empty) (list)) (genOps 300 7)))]
    (do (assert (= (dq/toList (pairFirst final)) (pairSecond final)) "final state matches model")
        true))

fn runTests -> Bool
  (and (testBasic) (and (testPops) (testModel)))
