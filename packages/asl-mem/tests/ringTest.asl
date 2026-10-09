(module aslMem/testRing :x [runTests] :i [(aslMem/ring :a r)])

fn runTests -> Bool
  (let [(rb0 (r/makeRingBuffer 3 (r/policyOverwriteOldest)))
        (res1 (r/ringPush rb0 "a"))
        (rb1 res1.buffer)
        (res2 (r/ringPush rb1 "b"))
        (rb2 res2.buffer)
        (res3 (r/ringPush rb2 "c"))
        (rb3 res3.buffer)]
    (assert (not (r/ringIsFull? rb1)) "Buffer with 1/3 items must not be full")
    (assert (r/ringIsFull? rb3) "Buffer with 3/3 items must be full")
    (assert (= (r/ringUtilization rb3) 100) "Full buffer utilization must be 100")
    (mt (r/ringPeekOldest rb3)
      ((some x) (assert (= x "a") "Oldest item before eviction must be a"))
      ((none) (assert false "Oldest item must be present")))
    (let [(res4 (r/ringPush rb3 "d"))
          (rb4 res4.buffer)]
      (assert res4.wasEvicted "Push to full overwrite buffer must evict")
      (assert (= (r/ringEvictedCount rb4) 1) "Evicted count must be 1")
      (mt res4.evictedItem
        ((some ev) (assert (= ev "a") "Evicted item must be a"))
        ((none) (assert false "Evicted item must be some a")))
      (mt (r/ringPeekOldest rb4)
        ((some x2) (assert (= x2 "b") "New oldest item must be b"))
        ((none) (assert false "New oldest item must be present")))
      (let [(drainPair (r/ringDrainAll rb4))
            (cleared (pairFirst drainPair))
            (drained (pairSecond drainPair))]
        (assert (= (listLength drained) 3) "Drained list must have 3 items")
        (assert (= (listLength cleared.items) 0) "Cleared buffer must be empty")
        (assert (not (r/ringIsFull? cleared)) "Cleared buffer must not be full")
        (let [(rbRej (r/makeRingBuffer 1 (r/policyReject)))
              (p1 (r/ringPush rbRej "first"))
              (p2 (r/ringPush p1.buffer "second"))]
          (assert (not p1.rejected) "First push must not be rejected")
          (assert p2.rejected "Second push to reject policy must be rejected")
          (assert (not p2.wasEvicted) "Reject policy must not evict")
          true))))
