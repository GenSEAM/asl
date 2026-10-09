(module asl-runtime/collections
  :x [listTake listDrop listZip listFlatten listChunk listPartition listAny? listAll? listFind alistGet PureSet makeSet setEmpty setFromList setContains? setInsert setAdd setRemove setUnion setIntersect setIntersection setDiff setDifference setToList setSize PureMap makeMap mapPut mapGet mapContains? mapRemove mapKeys mapValues mapSize PureQueue makeQueue queuePush queuePop queuePeek queueEmpty? queueSize CircularRingBuffer ringInit ringPush ringPop ringPeek ringEmpty? ringFull? ringPushOverwrite]
  :i [])

fn colContains? xs: (List Str) target: Str -> Bool
  (fold (fn [(acc Bool) (x Str)] -> Bool (or acc (= x target))) false xs)

fn takeHelper remaining: Int64 xs: (List Str) acc: (List Str) -> (List Str)
  (if (or (<= remaining 0) (listEmpty? xs))
    (listReverse acc)
    (let [(hd (optionOr (listHead xs) ""))
          (tl (optionOr (listTail xs) (list)))]
      (takeHelper (- remaining 1) tl (cons hd acc))))

fn listTake n: Int64 xs: (List Str) -> (List Str)
  (takeHelper n xs (list))

fn dropHelper remaining: Int64 xs: (List Str) -> (List Str)
  (if (or (<= remaining 0) (listEmpty? xs))
    xs
    (let [(tl (optionOr (listTail xs) (list)))]
      (dropHelper (- remaining 1) tl)))

fn listDrop n: Int64 xs: (List Str) -> (List Str)
  (dropHelper n xs)

fn zipHelper xs: (List Str) ys: (List Str) acc: (List (Pair Str Str)) -> (List (Pair Str Str))
  (if (or (listEmpty? xs) (listEmpty? ys))
    (listReverse acc)
    (let [(hx (optionOr (listHead xs) ""))
          (tx (optionOr (listTail xs) (list)))
          (hy (optionOr (listHead ys) ""))
          (ty (optionOr (listTail ys) (list)))]
      (zipHelper tx ty (cons (pair hx hy) acc))))

fn listZip xs: (List Str) ys: (List Str) -> (List (Pair Str Str))
  (zipHelper xs ys (list))

fn listFlatten xss: (List (List Str)) -> (List Str)
  (let [(revItems (fold (fn [(acc (List Str)) (sub (List Str))] -> (List Str)
                          (fold (fn [(inner (List Str)) (item Str)] -> (List Str)
                                  (cons item inner))
                                acc sub))
                        (list)
                        xss))]
    (listReverse revItems))

fn chunkHelper size: Int64 xs: (List Str) acc: (List (List Str)) -> (List (List Str))
  (if (or (<= size 0) (listEmpty? xs))
    (listReverse acc)
    (let [(chunk (listTake size xs))
          (rest (listDrop size xs))]
      (chunkHelper size rest (cons chunk acc))))

fn listChunk chunkSize: Int64 xs: (List Str) -> (List (List Str))
  (chunkHelper chunkSize xs (list))

fn partitionHelper pred: (fn [Str] -> Bool) xs: (List Str) matchAcc: (List Str) restAcc: (List Str) -> (Pair (List Str) (List Str))
  (if (listEmpty? xs)
    (pair (listReverse matchAcc) (listReverse restAcc))
    (let [(hd (optionOr (listHead xs) ""))
          (tl (optionOr (listTail xs) (list)))]
      (if (pred hd)
        (partitionHelper pred tl (cons hd matchAcc) restAcc)
        (partitionHelper pred tl matchAcc (cons hd restAcc)))))

fn listPartition pred: (fn [Str] -> Bool) xs: (List Str) -> (Pair (List Str) (List Str))
  (partitionHelper pred xs (list) (list))

fn listAny? predicate: (fn [Str] -> Bool) xs: (List Str) -> Bool
  (fold (fn [(acc Bool) (item Str)] -> Bool
          (or acc (predicate item)))
        false
        xs)

fn listAll? predicate: (fn [Str] -> Bool) xs: (List Str) -> Bool
  (fold (fn [(acc Bool) (item Str)] -> Bool
          (and acc (predicate item)))
        true
        xs)

fn findHelper xs: (List Str) pred: (fn [Str] -> Bool) -> (Option Str)
  (if (listEmpty? xs)
    (none)
    (let [(hd (optionOr (listHead xs) ""))
          (tl (optionOr (listTail xs) (list)))]
      (if (pred hd)
        (some hd)
        (findHelper tl pred))))

fn listFind pred: (fn [Str] -> Bool) xs: (List Str) -> (Option Str)
  (findHelper xs pred)

fn alistGet key: Str alist: (List (Pair Str Str)) -> (Option Str)
  (fold (fn [(acc (Option Str)) (entry (pair Str Str))] -> (Option Str)
          (if (and (none? acc) (= (pairFirst entry) key))
            (some (pairSecond entry))
            acc))
        (none)
        alist)

(schema PureSet
  (:f elements (List Str)))

fn setEmpty -> PureSet
  (PureSet :elements (list))

fn setContains? s: PureSet item: Str -> Bool
  (colContains? s.elements item)

fn setInsert s: PureSet item: Str -> PureSet
  (if (setContains? s item)
    s
    (PureSet :elements (cons item s.elements)))

fn setFromList elements: (List Str) -> PureSet
  (fold (fn [(acc PureSet) (x Str)] -> PureSet (setInsert acc x)) (setEmpty) (listReverse elements))

fn makeSet elements: (List Str) -> PureSet
  (setFromList elements)

fn setAdd s: PureSet item: Str -> PureSet
  (setInsert s item)

fn setRemove s: PureSet item: Str -> PureSet
  (PureSet :elements (filter (fn [(x Str)] -> Bool (!= x item)) s.elements))

fn setUnion s1: PureSet s2: PureSet -> PureSet
  (fold (fn [(acc PureSet) (x Str)] -> PureSet (setInsert acc x)) s1 s2.elements)

fn setIntersect s1: PureSet s2: PureSet -> PureSet
  (PureSet :elements (filter (fn [(x Str)] -> Bool (setContains? s2 x)) s1.elements))

fn setIntersection s1: PureSet s2: PureSet -> PureSet
  (setIntersect s1 s2)

fn setDiff s1: PureSet s2: PureSet -> PureSet
  (PureSet :elements (filter (fn [(x Str)] -> Bool (not (setContains? s2 x))) s1.elements))

fn setDifference s1: PureSet s2: PureSet -> PureSet
  (setDiff s1 s2)

fn setToList s: PureSet -> (List Str)
  s.elements

fn setSize s: PureSet -> Int64
  (listLength s.elements)

(schema PureMap
  (:f entries (List (pair Str Str))))

fn makeMap -> PureMap
  (PureMap :entries (list))

fn mapPut m: PureMap key: Str val: Str -> PureMap
  (let [(filtered (filter (fn [(p (pair Str Str))] -> Bool (!= (pairFirst p) key)) m.entries))
        (newEntry (pair key val))]
    (PureMap :entries (cons newEntry filtered)))

fn mapGet m: PureMap key: Str -> (Option Str)
  (alistGet key m.entries)

fn mapContains? m: PureMap key: Str -> Bool
  (some? (mapGet m key))

fn mapRemove m: PureMap key: Str -> PureMap
  (PureMap :entries (filter (fn [(p (pair Str Str))] -> Bool (!= (pairFirst p) key)) m.entries))

fn mapKeys m: PureMap -> (List Str)
  (map (fn [(p (pair Str Str))] -> Str (pairFirst p)) m.entries)

fn mapValues m: PureMap -> (List Str)
  (map (fn [(p (pair Str Str))] -> Str (pairSecond p)) m.entries)

fn mapSize m: PureMap -> Int64
  (listLength m.entries)

(schema PureQueue
  (:f inbox (List Str))
  (:f outbox (List Str))
  (:f length Int64))

fn makeQueue -> PureQueue
  (PureQueue :inbox (list) :outbox (list) :length 0)

fn queuePush q: PureQueue item: Str -> PureQueue
  (with q :inbox (cons item q.inbox) :length (+ q.length 1))

fn queuePop q: PureQueue -> (Pair (Option Str) PureQueue)
  (if (listEmpty? q.outbox)
    (if (listEmpty? q.inbox)
      (pair (none) q)
      (let [(rev (listReverse q.inbox))
            (hd (listHead rev))
            (tl (optionOr (listTail rev) (list)))]
        (pair hd (PureQueue :inbox (list) :outbox tl :length (- q.length 1)))))
    (let [(hd (listHead q.outbox))
          (tl (optionOr (listTail q.outbox) (list)))]
      (pair hd (with q :outbox tl :length (- q.length 1)))))

fn queuePeek q: PureQueue -> (Option Str)
  (if (not (listEmpty? q.outbox))
    (listHead q.outbox)
    (if (not (listEmpty? q.inbox))
      (listHead (listReverse q.inbox))
      (none)))

fn queueEmpty? q: PureQueue -> Bool
  (= q.length 0)

fn queueSize q: PureQueue -> Int64
  q.length

(schema CircularRingBuffer
  (:f capacity Int64)
  (:f count Int64)
  (:f head Int64)
  (:f tail Int64)
  (:f buffer (List Str)))

fn makeInitialRingSlots n: Int64 acc: (List Str) -> (List Str)
  (if (<= n 0)
    acc
    (makeInitialRingSlots (- n 1) (cons "" acc)))

fn listSetSlotHelper xs: (List Str) targetIdx: Int64 newItem: Str curIdx: Int64 -> (List Str)
  (mt (listHead xs)
    ((none) (list))
    ((some h)
      (let [(val (if (= curIdx targetIdx) newItem h))
            (rest (optionOr (listTail xs) (list)))]
        (cons val (listSetSlotHelper rest targetIdx newItem (+ curIdx 1))))))

fn listSetSlot xs: (List Str) targetIdx: Int64 newItem: Str -> (List Str)
  (listSetSlotHelper xs targetIdx newItem 0)


fn ringInit capacity: Int64 -> CircularRingBuffer
  (CircularRingBuffer :capacity capacity :count 0 :head 0 :tail 0 :buffer (makeInitialRingSlots capacity (list)))

fn ringEmpty? rb: CircularRingBuffer -> Bool
  (= rb.count 0)

fn ringFull? rb: CircularRingBuffer -> Bool
  (>= rb.count rb.capacity)

fn ringPush rb: CircularRingBuffer item: Str -> CircularRingBuffer
  (if (ringFull? rb)
    rb
    (let [(updatedBuf (listSetSlot rb.buffer rb.tail item))
          (nextTail (mod (+ rb.tail 1) rb.capacity))
          (nextCount (+ rb.count 1))]
      (with rb :count nextCount :tail nextTail :buffer updatedBuf)))

fn ringPushOverwrite rb: CircularRingBuffer item: Str -> CircularRingBuffer
  (if (ringFull? rb)
    (let [(updatedBuf (listSetSlot rb.buffer rb.tail item))
          (nextTail (mod (+ rb.tail 1) rb.capacity))
          (nextHead (mod (+ rb.head 1) rb.capacity))]
      (with rb :count rb.capacity :head nextHead :tail nextTail :buffer updatedBuf))
    (ringPush rb item))

fn ringPop rb: CircularRingBuffer -> (Pair (Option Str) CircularRingBuffer)
  (if (ringEmpty? rb)
    (pair (none) rb)
    (let [(val (listGet rb.buffer rb.head))
          (clearedBuf (listSetSlot rb.buffer rb.head ""))
          (nextHead (mod (+ rb.head 1) rb.capacity))
          (nextCount (- rb.count 1))]
      (pair val (with rb :count nextCount :head nextHead :buffer clearedBuf))))

fn ringPeek rb: CircularRingBuffer -> (Option Str)
  (if (ringEmpty? rb)
    (none)
    (listGet rb.buffer rb.head))
