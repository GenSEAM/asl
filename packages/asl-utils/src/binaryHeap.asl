(module asl-utils/binaryHeap
  :x [push pop peek fromList toSortedList]
  :i [])

fn get h: (List Int64) i: Int64 -> Int64
  (optionOr (listGet h i) 0)

fn parent i: Int64 -> Int64
  (/ (- i 1) 2)

fn setAt h: (List Int64) i: Int64 v: Int64 -> (List Int64)
  (listAppend (listTake h i) (cons v (listDrop h (+ i 1))))

fn swapAt h: (List Int64) i: Int64 j: Int64 -> (List Int64)
  (setAt (setAt h i (get h j)) j (get h i))

fn siftUp cmp: (fn [Int64 Int64] -> Int64) h: (List Int64) i: Int64 -> (List Int64)
  (if (<= i 0)
    h
    (let [(p (parent i))]
      (if (< (cmp (get h i) (get h p)) 0)
        (siftUp cmp (swapAt h i p) p)
        h)))

fn smallerChild cmp: (fn [Int64 Int64] -> Int64) h: (List Int64) i: Int64 -> Int64
  (let [(l (+ 1 (* 2 i)))
        (r (+ 2 (* 2 i)))]
    (if (>= r (listLength h))
      l
      (if (< (cmp (get h l) (get h r)) 0) l r)))

fn siftDown cmp: (fn [Int64 Int64] -> Int64) h: (List Int64) i: Int64 -> (List Int64)
  (let [(l (+ 1 (* 2 i)))]
    (if (>= l (listLength h))
      h
      (let [(c (smallerChild cmp h i))]
        (if (< (cmp (get h c) (get h i)) 0)
          (siftDown cmp (swapAt h i c) c)
          h))))

fn peek h: (List Int64) -> (Option Int64)
  (listHead h)

fn push cmp: (fn [Int64 Int64] -> Int64) h: (List Int64) x: Int64 -> (List Int64)
  (let [(h2 (listAppend h (list x)))]
    (siftUp cmp h2 (- (listLength h2) 1)))

fn pop cmp: (fn [Int64 Int64] -> Int64) h: (List Int64) -> (Pair (Option Int64) (List Int64))
  (let [(n (listLength h))]
    (if (= n 0)
      (pair (none) h)
      (if (= n 1)
        (pair (listHead h) (list))
        (let [(h2 (setAt (listTake h (- n 1)) 0 (get h (- n 1))))]
          (pair (listHead h) (siftDown cmp h2 0))))))

fn fromList cmp: (fn [Int64 Int64] -> Int64) xs: (List Int64) -> (List Int64)
  (fold (fn [(acc (List Int64)) (x Int64)] -> (List Int64) (push cmp acc x)) (list) xs)

fn toSortedList cmp: (fn [Int64 Int64] -> Int64) h: (List Int64) -> (List Int64)
  (let [(p (pop cmp h))
        (m (pairFirst p))]
    (if (none? m)
      (list)
      (cons (optionOr m 0) (toSortedList cmp (pairSecond p)))))
