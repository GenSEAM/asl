(module aslMem/ring :x [OverflowPolicy RingBuffer RingPushResult makeRingBuffer ringPush ringPeekRecent ringPeekOldest ringDrainAll ringIsFull? ringUtilization ringEvictedCount])

(enum OverflowPolicy (:c policyOverwriteOldest [] "Overwrites oldest entry when capacity is exceeded (circular FIFO)") (:c policySpill [] "Spills oldest batch to persistent storage callback or segment") (:c policyMiddleEvict [] "Retains head and tail windows, evicting the middle") (:c policyReject [] "Rejects new entries when buffer is at 100% capacity"))

(schema RingBuffer (:f capacity I64) (:f items (List Str)) (:f totalPushed I64) (:f evictedCount I64) (:f policy OverflowPolicy))

(schema RingPushResult (:f buffer RingBuffer) (:f wasEvicted Bool) (:f evictedItem (Option Str)) (:f rejected Bool))

fn makeRingBuffer cap: I64 pol: OverflowPolicy -> RingBuffer
  (RingBuffer :capacity (if (<= cap 0) 1 cap) :items (list) :totalPushed 0 :evictedCount 0 :policy pol)

fn ringIsFull? rb: RingBuffer -> Bool
  (>= (listLength rb.items) rb.capacity)

fn ringEvictedCount rb: RingBuffer -> I64
  rb.evictedCount

fn ringUtilization rb: RingBuffer -> I64
  (let [(cnt (listLength rb.items)) (cap rb.capacity)] (if (<= cap 0) 0 (/ (* cnt 100) cap)))

fn ringPeekOldest rb: RingBuffer -> (Option Str)
  (listHead rb.items)

fn ringPeekRecent rb: RingBuffer n: I64 -> (List Str)
  (let [(items rb.items) (len (listLength items))] (if (<= len n) items (let [(start (- len n))] (optionOr (listSlice items start len) (list)))))

fn ringDrainAll rb: RingBuffer -> (Pair RingBuffer (List Str))
  (let [(drained rb.items) (cleared (with rb :items (list)))] (pair cleared drained))

fn dropOldest items: (List Str) -> (List Str)
  (mt (listTail items) ((some tl) tl) ((none) (list)))

fn ringPush rb: RingBuffer item: Str -> RingPushResult
  (let [(cap rb.capacity) (currItems rb.items) (currLen (listLength currItems)) (newPushed (+ rb.totalPushed 1))] (if (< currLen cap) (let [(nextBuf (with rb :capacity cap :items (listAppend currItems (list item)) :totalPushed newPushed))] (RingPushResult :buffer nextBuf :wasEvicted false :evictedItem (none) :rejected false)) (mt rb.policy ((policyReject) (RingPushResult :buffer rb :wasEvicted false :evictedItem (none) :rejected true)) ((policyOverwriteOldest) (let [(oldest (listHead currItems)) (retained (dropOldest currItems)) (nextItems (listAppend retained (list item))) (nextBuf (with rb :capacity cap :items nextItems :totalPushed newPushed :evictedCount (+ rb.evictedCount 1)))] (RingPushResult :buffer nextBuf :wasEvicted true :evictedItem oldest :rejected false))) ((policySpill) (let [(spilled (listHead currItems)) (retained (dropOldest currItems)) (nextItems (listAppend retained (list item))) (nextBuf (with rb :capacity cap :items nextItems :totalPushed newPushed :evictedCount (+ rb.evictedCount 1)))] (RingPushResult :buffer nextBuf :wasEvicted true :evictedItem spilled :rejected false))) ((policyMiddleEvict) (let [(headSize (/ cap 4)) (headPart (if (> headSize 0) (optionOr (listSlice currItems 0 headSize) (list)) (list))) (tailStart (+ headSize 1)) (tailPart (optionOr (listSlice currItems tailStart currLen) (list))) (nextItems (listAppend (listAppend headPart tailPart) (list item))) (nextBuf (with rb :capacity cap :items nextItems :totalPushed newPushed :evictedCount (+ rb.evictedCount 1)))] (RingPushResult :buffer nextBuf :wasEvicted true :evictedItem (none) :rejected false))))))
