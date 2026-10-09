(module asl-runtime/ringBuffer
  :x [RingBuffer ringInit ringEmpty? ringFull? ringDropped pushBounded pushOverwrite ringPeek ringPop ringDrain]
  :i [])

(schema RingBuffer
  (:f capacity Int64)
  (:f count Int64)
  (:f dropped Int64)
  (:f items (List Str)))

fn ringInit capacity: Int64 -> RingBuffer
  (RingBuffer
    :capacity (if (<= capacity 0) 1 capacity)
    :count 0
    :dropped 0
    :items (list))

fn ringEmpty? rb: RingBuffer -> Bool
  (= rb.count 0)

fn ringFull? rb: RingBuffer -> Bool
  (>= rb.count rb.capacity)

fn ringDropped rb: RingBuffer -> Int64
  rb.dropped

fn pushBounded rb: RingBuffer item: Str -> (Option RingBuffer)
  (if (ringFull? rb)
    (none)
    (some (with rb :count (+ rb.count 1) :items (listAppend rb.items (list item)))))

fn pushOverwrite rb: RingBuffer item: Str -> RingBuffer
  (if (ringFull? rb)
    (let [(tailItems (optionOr (listTail rb.items) (list)))]
      (with rb :count rb.capacity :dropped (+ rb.dropped 1) :items (listAppend tailItems (list item))))
    (with rb :count (+ rb.count 1) :items (listAppend rb.items (list item))))

fn ringPeek rb: RingBuffer -> (Option Str)
  (if (ringEmpty? rb)
    (none)
    (listHead rb.items))

fn ringPop rb: RingBuffer -> (Pair (Option Str) RingBuffer)
  (if (ringEmpty? rb)
    (pair (none) rb)
    (let [(headItem (listHead rb.items))
          (tailItems (optionOr (listTail rb.items) (list)))]
      (pair headItem
            (with rb :count (- rb.count 1) :items tailItems))))

fn ringDrain rb: RingBuffer -> (Pair (List Str) RingBuffer)
  (let [(drained rb.items)]
    (pair drained
          (with rb :count 0 :items (list))))

