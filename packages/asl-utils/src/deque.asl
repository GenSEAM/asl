(module asl-utils/deque :x [Deque empty pushFront pushBack popFront popBack toList] :i [])

(schema Deque (:f front (List Int64)) (:f back (List Int64)))

fn empty -> Deque
  (Deque :front (list) :back (list))

fn check d: Deque -> Deque
  (if (listEmpty? d.front)
    (if (listEmpty? d.back)
      d
      (let [(r (listReverse d.back)) (h (max 1 (/ (listLength r) 2)))]
        (Deque :front (listTake r h) :back (listReverse (listDrop r h)))))
    (if (and (listEmpty? d.back) (> (listLength d.front) 1))
      (let [(r (listReverse d.front)) (h (max 1 (/ (listLength r) 2)))]
        (Deque :front (listReverse (listDrop r h)) :back (listTake r h)))
      d))

fn pushFront d: Deque x: Int64 -> Deque
  (check (with d :front (cons x d.front)))

fn pushBack d: Deque x: Int64 -> Deque
  (check (with d :back (cons x d.back)))

fn popFront d: Deque -> (Option (Pair Int64 Deque))
  (match (listHead d.front)
    ((some x) (some (pair x (check (with d :front (optionOr (listTail d.front) (list)))))))
    ((none) (none)))

fn popBack d: Deque -> (Option (Pair Int64 Deque))
  (match (listHead d.back)
    ((some x) (some (pair x (check (with d :back (optionOr (listTail d.back) (list)))))))
    ((none) (match (listHead d.front)
      ((some x) (some (pair x (empty))))
      ((none) (none)))))

fn toList d: Deque -> (List Int64)
  (listAppend d.front (listReverse d.back))
