(module asl-runtime/tests/collectionsTest
  :x [testTakeAndDrop testZipAndFlatten testChunk testAnyAndAll testAlistGet testListFind testPureSet testPureMap testPureQueue testPureSetCanonical testListPartition runTests RunTests]
  :i [(asl-runtime/collections :a col)])

fn testTakeAndDrop -> Bool
  (let [(items (list "a" "b" "c" "d"))
        (t2 (col/listTake 2 items))
        (t0 (col/listTake 0 items))
        (tAll (col/listTake 10 items))
        (d2 (col/listDrop 2 items))
        (d0 (col/listDrop 0 items))
        (dAll (col/listDrop 10 items))]
    (do
      (assert (= (listLength t2) 2) "listTake 2 has length 2")
      (refute (!= (listLength t2) 2) "listTake 2 refutes non-2 length")
      (assert (= (optionOr (listHead t2) "") "a") "listTake first item is a")
      (assert (= (listLength t0) 0) "listTake 0 is empty")
      (assert (= (listLength tAll) 4) "listTake 10 on 4 elements returns all 4")
      (assert (= (listLength d2) 2) "listDrop 2 leaves 2 items")
      (refute (!= (listLength d2) 2) "listDrop 2 refutes non-2 length")
      (assert (= (optionOr (listHead d2) "") "c") "listDrop first remaining is c")
      (assert (= (listLength d0) 4) "listDrop 0 keeps all items")
      (assert (= (listLength dAll) 0) "listDrop 10 leaves empty list")
      true))

fn testZipAndFlatten -> Bool
  (let [(xs (list "k1" "k2" "k3"))
        (ys (list "v1" "v2"))
        (zipped (col/listZip xs ys))
        (firstPair (optionOr (listHead zipped) (pair "" "")))
        (sub1 (list "a" "b"))
        (sub2 (list "c"))
        (sub3 (list "d" "e"))
        (flat (col/listFlatten (list sub1 sub2 sub3)))]
    (do
      (assert (= (listLength zipped) 2) "listZip truncates to shorter list length 2")
      (refute (!= (listLength zipped) 2) "listZip refutes divergence from 2")
      (assert (= (pairFirst firstPair) "k1") "first pair key is k1")
      (assert (= (pairSecond firstPair) "v1") "first pair val is v1")
      (assert (= (listLength flat) 5) "listFlatten produces 5 elements")
      (refute (!= (listLength flat) 5) "listFlatten refutes non-5 length")
      (assert (= (optionOr (listHead flat) "") "a") "flatten first item is a")
      true))

fn testChunk -> Bool
  (let [(items (list "1" "2" "3" "4" "5"))
        (chunks (col/listChunk 2 items))
        (c1 (optionOr (listHead chunks) (list)))
        (tail1 (optionOr (listTail chunks) (list)))
        (c2 (optionOr (listHead tail1) (list)))
        (tail2 (optionOr (listTail tail1) (list)))
        (c3 (optionOr (listHead tail2) (list)))]
    (do
      (assert (= (listLength chunks) 3) "listChunk 2 on 5 items produces 3 chunks")
      (refute (!= (listLength chunks) 3) "listChunk refutes non-3 chunk count")
      (assert (= (listLength c1) 2) "chunk 1 has length 2")
      (assert (= (listLength c2) 2) "chunk 2 has length 2")
      (assert (= (listLength c3) 1) "chunk 3 has length 1")
      (assert (= (optionOr (listHead c3) "") "5") "chunk 3 item is 5")
      true))

fn testAnyAndAll -> Bool
  (let [(items (list "alpha" "beta" "gamma"))
        (isBeta (fn [(s Str)] -> Bool (= s "beta")))
        (isDelta (fn [(s Str)] -> Bool (= s "delta")))
        (isNonEmpty (fn [(s Str)] -> Bool (> (stringLength s) 0)))
        (isShort (fn [(s Str)] -> Bool (< (stringLength s) 5)))]
    (do
      (assert (col/listAny? isBeta items) "listAny? finds beta")
      (refute (col/listAny? isDelta items) "listAny? refutes delta")
      (assert (col/listAll? isNonEmpty items) "listAll? verifies all strings non-empty")
      (refute (col/listAll? isShort items) "listAll? refutes all strings short")
      true))

fn testAlistGet -> Bool
  (let [(entries (list (pair "host" "localhost") (pair "port" "8080") (pair "user" "root")))
        (rHost (col/alistGet "host" entries))
        (rPort (col/alistGet "port" entries))
        (rMiss (col/alistGet "missing" entries))]
    (do
      (assert (= (optionOr rHost "") "localhost") "alistGet finds host")
      (refute (!= (optionOr rHost "") "localhost") "alistGet refutes wrong host")
      (assert (= (optionOr rPort "") "8080") "alistGet finds port")
      (assert (none? rMiss) "alistGet returns none for missing key")
      (refute (some? rMiss) "alistGet refutes some for missing key")
      true))

fn testPureSet -> Bool
  (let [(s0 (col/makeSet (list "apple" "banana")))
        (s1 (col/setAdd s0 "cherry"))
        (s2 (col/setAdd s1 "apple"))
        (s3 (col/setRemove s2 "banana"))
        (hasApple (col/setContains? s3 "apple"))
        (hasBanana (col/setContains? s3 "banana"))
        (hasCherry (col/setContains? s3 "cherry"))
        (elems (col/setToList s3))]
    (do
      (assert hasApple "set contains apple")
      (refute hasBanana "set does not contain removed banana")
      (assert hasCherry "set contains cherry")
      (assert (= (col/setSize s3) 2) "set size is 2")
      (assert (= (listLength elems) 2) "set elements list length is 2")
      true))

fn testPureMap -> Bool
  (let [(m0 (col/makeMap))
        (m1 (col/mapPut m0 "host" "127.0.0.1"))
        (m2 (col/mapPut m1 "port" "4000"))
        (m3 (col/mapPut m2 "host" "localhost"))
        (vHost (col/mapGet m3 "host"))
        (vPort (col/mapGet m3 "port"))
        (vMiss (col/mapGet m3 "unknown"))
        (m4 (col/mapRemove m3 "port"))
        (keys (col/mapKeys m4))]
    (do
      (assert (= (optionOr vHost "") "localhost") "mapGet overwritten host is localhost")
      (assert (= (optionOr vPort "") "4000") "mapGet port is 4000")
      (assert (none? vMiss) "mapGet unknown key is none")
      (assert (col/mapContains? m3 "host") "mapContains host is true")
      (refute (col/mapContains? m4 "port") "mapContains removed port is false")
      (assert (= (col/mapSize m4) 1) "mapSize after removal is 1")
      (assert (= (listLength keys) 1) "mapKeys count is 1")
      true))

fn testListFind -> Bool
  (let [(xs (list "apple" "banana" "cherry"))
        (found (col/listFind (fn [(s Str)] -> Bool (stringStartsWith? s "b")) xs))
        (notFound (col/listFind (fn [(s Str)] -> Bool (= s "orange")) xs))]
    (do
      (assert (= (optionOr found "") "banana") "listFind finds banana")
      (refute (!= (optionOr found "") "banana") "refute non-banana match")
      (assert (none? notFound) "listFind returns none when not found")
      true))

fn testPureQueue -> Bool
  (let [(q0 (col/makeQueue))
        (q1 (col/queuePush q0 "item1"))
        (q2 (col/queuePush q1 "item2"))
        (q3 (col/queuePush q2 "item3"))
        (peek3 (col/queuePeek q3))
        (popRes1 (col/queuePop q3))
        (p1 (pairFirst popRes1))
        (qAfter1 (pairSecond popRes1))
        (popRes2 (col/queuePop qAfter1))
        (p2 (pairFirst popRes2))
        (qAfter2 (pairSecond popRes2))
        (popRes3 (col/queuePop qAfter2))
        (p3 (pairFirst popRes3))
        (qAfter3 (pairSecond popRes3))
        (popEmpty (col/queuePop qAfter3))]
    (do
      (assert (col/queueEmpty? q0) "empty queue is empty")
      (assert (= (col/queueSize q3) 3) "queue size is 3 after 3 pushes")
      (refute (!= (col/queueSize q3) 3) "refute non-3 queue size")
      (assert (= (optionOr peek3 "") "item1") "queue peek returns item1")
      (assert (= (optionOr p1 "") "item1") "first pop is item1")
      (assert (= (optionOr p2 "") "item2") "second pop is item2")
      (assert (= (optionOr p3 "") "item3") "third pop is item3")
      (assert (col/queueEmpty? qAfter3) "queue is empty after popping all")
      (assert (none? (pairFirst popEmpty)) "pop on empty queue returns none")
      true))

fn testPureSetCanonical -> Bool
  (let [(sEmpty (col/setEmpty))
        (s1 (col/setFromList (list "a" "b" "a" "c")))
        (s2 (col/setFromList (list "b" "c" "d")))
        (sIns (col/setInsert s1 "z"))
        (sInter (col/setIntersect s1 s2))
        (sDiff (col/setDiff s1 s2))
        (interElems (col/setToList sInter))
        (diffElems (col/setToList sDiff))]
    (do
      (assert (= (col/setSize sEmpty) 0) "setEmpty has size 0")
      (refute (col/setContains? sEmpty "a") "setEmpty contains nothing")
      (assert (= (col/setSize s1) 3) "setFromList deduplicates to 3 elements")
      (assert (col/setContains? sIns "z") "setInsert adds element")
      (assert (= (col/setSize sInter) 2) "intersection has 2 elements: b and c")
      (assert (col/setContains? sInter "b") "intersection contains b")
      (assert (col/setContains? sInter "c") "intersection contains c")
      (refute (col/setContains? sInter "a") "intersection excludes a")
      (assert (= (col/setSize sDiff) 1) "setDiff s1 minus s2 has 1 element: a")
      (assert (col/setContains? sDiff "a") "setDiff contains a")
      (refute (col/setContains? sDiff "b") "setDiff excludes b")
      true))

fn testListPartition -> Bool
  (let [(xs (list "apple" "banana" "avocado" "cherry" "apricot"))
        (res (col/listPartition (fn [(s Str)] -> Bool (stringStartsWith? s "a")) xs))
        (matched (pairFirst res))
        (rest (pairSecond res))]
    (do
      (assert (= (listLength matched) 3) "matched partition has 3 elements")
      (assert (= (listLength rest) 2) "rest partition has 2 elements")
      (assert (= (optionOr (listHead matched) "") "apple") "first matched is apple")
      (assert (= (optionOr (listHead rest) "") "banana") "first rest is banana")
      (refute (col/listAny? (fn [(s Str)] -> Bool (not (stringStartsWith? s "a"))) matched) "all matched start with a")
      (refute (col/listAny? (fn [(s Str)] -> Bool (stringStartsWith? s "a")) rest) "no rest start with a")
      true))

fn testCircularRingBufferFifo -> Bool
  (let [(rb0 (col/ringInit 3))
        (rb1 (col/ringPush rb0 "m1"))
        (rb2 (col/ringPush rb1 "m2"))
        (res1 (col/ringPop rb2))
        (val1 (pairFirst res1))
        (rb3 (pairSecond res1))
        (rb4 (col/ringPush rb3 "m3"))
        (rb5 (col/ringPush rb4 "m4"))
        (isFull (col/ringFull? rb5))
        (rbBlocked (col/ringPush rb5 "overflow"))
        (rbOverwritten (col/ringPushOverwrite rb5 "m5"))
        (popA (col/ringPop rb5))
        (popB (col/ringPop (pairSecond popA)))
        (popC (col/ringPop (pairSecond popB)))]
    (assert (= rb2.count 2) "ring buffer count is 2 after two pushes")
    (assert (= (optionOr val1 "") "m1") "first popped item is m1")
    (assert (= rb3.count 1) "ring buffer count is 1 after pop")
    (assert isFull "ring buffer reaches full state at capacity 3")
    (assert (= rbBlocked.count 3) "standard push on full buffer does not overflow")
    (assert (= rbOverwritten.count 3) "overwrite push on full buffer maintains count 3")
    (assert (= (optionOr (pairFirst popA) "") "m2") "FIFO order preserved across circular wrap: m2")
    (assert (= (optionOr (pairFirst popB) "") "m3") "FIFO order preserved across circular wrap: m3")
    (assert (= (optionOr (pairFirst popC) "") "m4") "FIFO order preserved across circular wrap: m4")
    (assert (col/ringEmpty? (pairSecond popC)) "ring buffer empty after popping all elements")
    (refute (col/ringFull? (pairSecond popC)) "empty ring buffer refutes full state")
    true)

fn runTests -> Bool
  (do
    (assert (testTakeAndDrop) "testTakeAndDrop")
    (assert (testZipAndFlatten) "testZipAndFlatten")
    (assert (testChunk) "testChunk")
    (assert (testAnyAndAll) "testAnyAndAll")
    (assert (testAlistGet) "testAlistGet")
    (assert (testListFind) "testListFind")
    (assert (testPureSet) "testPureSet")
    (assert (testPureMap) "testPureMap")
    (assert (testPureQueue) "testPureQueue")
    (assert (testPureSetCanonical) "testPureSetCanonical")
    (assert (testListPartition) "testListPartition")
    (assert (testCircularRingBufferFifo) "testCircularRingBufferFifo")
    true)

fn RunTests -> Bool
  (runTests)
