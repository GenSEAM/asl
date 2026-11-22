(module asl-store/kv
  :x [Entry Outcome liveAt? expiryOf decide scanPage readPage commitCheck keyOfOp]
  :i [(asl-store/types :a ty)])

(schema Entry (:f rev Int64) (:f value String) (:f expiresAt Int64))

; (:m :ref VS-CORE :do "write is the row to store, remove asks the adapter to delete an expired row it met, reply is what the caller sees; adapters apply the outcome under their own lock and never decide anything themselves")
(schema Outcome (:f write (Option Entry)) (:f remove Bool) (:f reply ty/Reply))

; (:m :ref VS-CORE :do "a row expires at the first instant now >= expiresAt; expiresAt 0 never expires")
fn liveAt? e: Entry now: Int64 -> Bool
  (or (= e.expiresAt 0) (> e.expiresAt now))

fn expiryOf ttlMs: Int64 now: Int64 -> Int64
  (if (> ttlMs 0) (+ now ttlMs) 0)

fn liveOf cur: (Option Entry) now: Int64 -> (Option Entry)
  (match cur
    ((some e) (if (liveAt? e now) (some e) (none)))
    ((none) (none)))

fn expiredSeen? cur: (Option Entry) now: Int64 -> Bool
  (match cur ((some e) (not (liveAt? e now))) ((none) false))

fn revOf live: (Option Entry) -> Int64
  (match live ((some e) e.rev) ((none) 0))

fn putOutcome live: (Option Entry) value: String ttlMs: Int64 now: Int64 -> Outcome
  (let [(rev (+ (revOf live) 1))]
    (Outcome :write (some (Entry :rev rev :value value :expiresAt (expiryOf ttlMs now))) :remove false :reply (ty/rWritten rev)))

fn noWrite reply: ty/Reply remove: Bool -> Outcome
  (Outcome :write (none) :remove remove :reply reply)

; (:m :ref VS-CORE :do "cas expectRev 0 creates only when absent; a stale or missing row answers conflict with the current revision (0 when absent); del with expectRev 0 deletes whatever is there, with n it needs revision n")
fn decide cur: (Option Entry) op: ty/Op -> Outcome
  (match op
    ((ty/opGet _ now)
      (match (liveOf cur now)
        ((some e) (noWrite (ty/rValue e.rev e.value e.expiresAt) false))
        ((none) (noWrite (ty/rAbsent) (expiredSeen? cur now)))))
    ((ty/opPut _ v ttl now) (putOutcome (liveOf cur now) v ttl now))
    ((ty/opCas _ expect v ttl now)
      (let [(live (liveOf cur now))]
        (if (= expect (revOf live))
          (putOutcome live v ttl now)
          (noWrite (ty/rConflict (revOf live)) (expiredSeen? cur now)))))
    ((ty/opDel _ expect now)
      (let [(live (liveOf cur now))]
        (if (or (= expect 0) (= expect (revOf live)))
          (Outcome :write (none) :remove (some? cur) :reply (ty/rDeleted))
          (noWrite (ty/rConflict (revOf live)) (expiredSeen? cur now)))))
    (_ (noWrite (ty/rErr "opInvalid" "not a kv op") false)))

fn keyOfOp op: ty/Op -> ty/Key
  (match op
    ((ty/opGet k _) k)
    ((ty/opPut k _ _ _) k)
    ((ty/opCas k _ _ _ _) k)
    ((ty/opDel k _ _) k)
    (_ (ty/Key :collection "" :id "")))

fn rowLess a: ty/ScanRow b: ty/ScanRow -> Bool
  (< a.id b.id)

; (:m :ref VS-CORE :do "rows must already be live; the page is ordered by id bytes, holds ids with the prefix and after the cursor, at most the capped limit, and next is the last id when more remain, else empty")
fn scanPage rows: (List ty/ScanRow) prefix: String after: String limit: Int64 -> ty/Reply
  (let [(sorted (listSortBy (fn [(r ty/ScanRow)] -> String r.id) rows))
        (hits (filter (fn [(r ty/ScanRow)] -> Bool (and (stringStartsWith? r.id prefix) (or (stringEmpty? after) (> r.id after)))) sorted))
        (cap (ty/capLimit limit))
        (page (listTake hits cap))
        (more (> (listLength hits) cap))]
    (ty/rPage page (if more (match (listLast page) ((some r) r.id) ((none) "")) "")))

; (:m :ref VS-CORE :do "rows are every record of one stream in offset order; the page starts at fromOffset, holds at most the capped limit and next is the offset to read from after it")
fn readPage rows: (List ty/LogRow) from: Int64 limit: Int64 -> ty/Reply
  (let [(hits (filter (fn [(r ty/LogRow)] -> Bool (>= r.offset from)) rows))
        (page (listTake hits (ty/capLimit limit)))]
    (ty/rRecords page (match (listLast page) ((some r) (+ r.offset 1)) ((none) from))))

; (:m :ref VS-CORE :do "a consumer cursor only moves forward and never past the end of the stream")
fn commitCheck length: Int64 current: Int64 offset: Int64 -> (Option ty/Reply)
  (cond
    ((> offset length) (some (ty/rErr "offsetInvalid" "offset past the end of the stream")))
    ((< offset current) (some (ty/rErr "offsetInvalid" "offset before the committed cursor")))
    (else (none)))
