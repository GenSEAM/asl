(module aslAgentBus/asnlRing
  :x [AsnlPointer AsnlRingBuffer makeRingBuffer makeAsnlPointer isPointerValid? isRingEmpty? isRingFull? ringPush ringPushPointer ringPop ringPeek ringDrain formatRingStats]
  :i [(ndAsn :a nd)])

(schema AsnlPointer
  (:f bufferId Str)
  (:f offset I64)
  (:f length I64)
  (:f hash Str)
  (:f epoch I64))

(schema AsnlRingBuffer
  (:f capacity I64)
  (:f frames (List nd/NDASNFrame))
  (:f headSeq I64)
  (:f tailSeq I64)
  (:f dropped I64)
  (:f currentEpoch I64))

fn makeRingBuffer capacity: I64 -> AsnlRingBuffer
  (let [(cap (if (<= capacity 0) 64 capacity))]
    (AsnlRingBuffer :capacity cap :frames (list) :headSeq 0 :tailSeq 0 :dropped 0 :currentEpoch 1))

fn makeAsnlPointer bufferId: Str offset: I64 length: I64 hash: Str epoch: I64 -> AsnlPointer
  (AsnlPointer :bufferId bufferId :offset offset :length length :hash hash :epoch epoch)

fn isPointerValid? ring: AsnlRingBuffer ptr: AsnlPointer -> Bool
  (and (= ptr.epoch ring.currentEpoch)
       (and (>= ptr.offset 0)
            (> ptr.length 0)))

fn isRingEmpty? ring: AsnlRingBuffer -> Bool
  (listEmpty? ring.frames)

fn isRingFull? ring: AsnlRingBuffer -> Bool
  (>= (listLength ring.frames) ring.capacity)

fn ringPush ring: AsnlRingBuffer frame: nd/NDASNFrame -> AsnlRingBuffer
  (let [(curFrames ring.frames)
        (curLen (listLength curFrames))
        (cap ring.capacity)
        (curTail ring.tailSeq)
        (curHead ring.headSeq)
        (curDrop ring.dropped)
        (curEpoch ring.currentEpoch)
        (stamped (nd/NDASNFrame :topic frame.topic
                                :seq (+ curTail 1)
                                :ts frame.ts
                                :payload frame.payload
                                :meta frame.meta))]
    (if (< curLen cap)
      (AsnlRingBuffer :capacity cap
                      :frames (listAppend curFrames (list stamped))
                      :headSeq curHead
                      :tailSeq (+ curTail 1)
                      :dropped curDrop
                      :currentEpoch curEpoch)
      (let [(evictedTail (optionOr (listTail curFrames) (list)))]
        (AsnlRingBuffer :capacity cap
                        :frames (listAppend evictedTail (list stamped))
                        :headSeq (+ curHead 1)
                        :tailSeq (+ curTail 1)
                        :dropped (+ curDrop 1)
                        :currentEpoch (+ curEpoch 1)))))

fn ringPushPointer ring: AsnlRingBuffer topic: Str ptr: AsnlPointer ts: I64 -> AsnlRingBuffer
  (let [(payload (str "(:ptr :buf \"" ptr.bufferId
                      "\" :offset " (stringFromInt64 ptr.offset)
                      " :len " (stringFromInt64 ptr.length)
                      " :hash \"" ptr.hash
                      "\" :epoch " (stringFromInt64 ptr.epoch) "\")"))
        (frame (nd/ndAsnFrame topic ring.tailSeq ts payload (mapEmpty)))]
    (ringPush ring frame))

fn ringPop ring: AsnlRingBuffer -> (Pair (Option nd/NDASNFrame) AsnlRingBuffer)
  (let [(curFrames ring.frames)]
    (if (listEmpty? curFrames)
      (pair (none) ring)
      (let [(h (listHead curFrames))
            (t (optionOr (listTail curFrames) (list)))
            (nextHead (+ ring.headSeq 1))
            (upd (with ring :frames t :headSeq nextHead))]
        (pair h upd))))

fn ringPeek ring: AsnlRingBuffer -> (Option nd/NDASNFrame)
  (listHead ring.frames)

fn ringDrain ring: AsnlRingBuffer -> (Pair (List nd/NDASNFrame) AsnlRingBuffer)
  (let [(drained ring.frames)
        (count (listLength drained))
        (emptyRing (with ring :frames (list) :headSeq (+ ring.headSeq count)))]
    (pair drained emptyRing))

fn formatRingStats ring: AsnlRingBuffer -> Str
  (str "(:asnl-ring :capacity " (stringFromInt64 ring.capacity)
       " :size " (stringFromInt64 (listLength ring.frames))
       " :head " (stringFromInt64 ring.headSeq)
       " :tail " (stringFromInt64 ring.tailSeq)
       " :dropped " (stringFromInt64 ring.dropped)
       " :epoch " (stringFromInt64 ring.currentEpoch) ")")
