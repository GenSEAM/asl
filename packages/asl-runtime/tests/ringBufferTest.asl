(module asl-runtime/tests/ringBufferTest
  :x [testRingInit testPushBounded testPushOverwrite testRingPopPeek testRingDrain runTests]
  :i [(asl-runtime/ringBuffer :a ring)])

fn testRingInit -> Bool
  (let [(rb (ring/ringInit 64))]
    (assert (ring/ringEmpty? rb) "New ring buffer must be empty")
    (refute (ring/ringFull? rb) "New ring buffer must not be full")
    (assert (= rb.capacity 64) "Capacity must be 64")
    (assert (= rb.count 0) "Initial count must be 0")
    true)

fn testPushBounded -> Bool
  (let [(rb (ring/ringInit 4))
        (r1 (ring/pushBounded rb "item1"))
        (r2 (ring/pushBounded (optionOr r1 rb) "item2"))
        (r3 (ring/pushBounded (optionOr r2 rb) "item3"))
        (r4 (ring/pushBounded (optionOr r3 rb) "item4"))
        (overflow (ring/pushBounded (optionOr r4 rb) "item5"))]
    (assert (some? r1) "Push 1 must succeed")
    (assert (some? r4) "Push 4 must succeed")
    (assert (none? overflow) "Push 5 must fail with overflow on bounded ring")
    (refute (some? overflow) "Overflow push must be rejected")
    true)

fn testPushOverwrite -> Bool
  (let [(rb (ring/ringInit 2))
        (r1 (ring/pushOverwrite rb "a"))
        (r2 (ring/pushOverwrite r1 "b"))
        (r3 (ring/pushOverwrite r2 "c"))]
    (assert (= r3.count 2) "Count must not exceed capacity 2")
    (assert (= (ring/ringDropped r3) 1) "One item must be dropped on overwrite")
    (assert (= (optionOr (ring/ringPeek r3) "") "b") "Oldest remaining item must be b")
    (refute (= (optionOr (ring/ringPeek r3) "") "a") "Item a must have been dropped")
    true)

fn testRingPopPeek -> Bool
  (let [(rb (ring/ringInit 4))
        (r1 (ring/pushOverwrite rb "first"))
        (r2 (ring/pushOverwrite r1 "second"))
        (peekVal (ring/ringPeek r2))
        (popRes (ring/ringPop r2))]
    (assert (= (optionOr peekVal "") "first") "Peek must return first item")
    (assert (= (optionOr (pairFirst popRes) "") "first") "Pop must return first item")
    (assert (= (pairSecond popRes).count 1) "Count after pop must be 1")
    true)

fn testRingDrain -> Bool
  (let [(rb (ring/ringInit 8))
        (r1 (ring/pushOverwrite rb "msg1"))
        (r2 (ring/pushOverwrite r1 "msg2"))
        (r3 (ring/pushOverwrite r2 "msg3"))
        (drainRes (ring/ringDrain r3))]
    (assert (= (listLength (pairFirst drainRes)) 3) "Drain must extract all 3 items")
    (assert (ring/ringEmpty? (pairSecond drainRes)) "Ring after drain must be empty")
    (refute (ring/ringFull? (pairSecond drainRes)) "Ring after drain must not be full")
    true)

fn runTests -> Bool
  (do
    (assert (testRingInit) "Ring init test must pass")
    (assert (testPushBounded) "Push bounded test must pass")
    (assert (testPushOverwrite) "Push overwrite test must pass")
    (assert (testRingPopPeek) "Ring pop peek test must pass")
    (assert (testRingDrain) "Ring drain test must pass")
    true)
