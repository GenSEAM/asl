(module asl-vault/tests/adapterTest
  :x [runTests]
  :i [(asl-store/types :a ty) (asl-store/mem :a mem) (asl-store/kv :a kv) (asl-vault/model :a m) (asl-vault/vault :a vt)])

fn spec id: String body: String -> vt/IngestSpec
  (vt/IngestSpec :entryId id :kind "note" :layer "topic" :role "evidence" :scope (mapEmpty) :status "corroborated" :provenance "primary" :sourceHashes (list)
                 :title id :summary "" :bodyText body :source "" :licence "" :confidenceBp 9000 :ttlDays 30 :tags (list) :priorityBp 100 :validFrom 0 :replacesEntryId "")

fn tag op: ty/Op -> String
  (match op
    ((ty/opScan c _ _ _ _) (str "scan " c))
    (_ (str "kv " (kv/keyOfOp op).collection)))

; (:m :ref VS-VAULT :do "a recording adapter wraps memStep and keeps the collection of every op: the vault must reach storage only through Op rows and only inside its five collections")
fn recStep st: (Pair mem/MemState (List String)) op: ty/Op -> (Pair (Pair mem/MemState (List String)) ty/Reply)
  (let [(r (mem/memStep (pairFirst st) op))]
    (pair (pair (pairFirst r) (cons (tag op) (pairSecond st))) (pairSecond r)))

; (:m :ref VS-VAULT :do "a racing adapter lets another writer change an entry row between the vault's read and its CAS, which is exactly what the revision check must catch")
fn raceStep st: mem/MemState op: ty/Op -> (Pair mem/MemState ty/Reply)
  (match op
    ((ty/opCas k e v ttl now)
      (if (and (= k.collection "entries") (> e 0))
        (let [(cur (mem/memStep st (ty/opGet k now)))
              (bump (mem/memStep st (ty/opPut k (match (pairSecond cur) ((ty/rValue _ v _) v) (_ "")) 0 now)))]
          (mem/memStep (pairFirst bump) op))
        (mem/memStep st op)))
    (_ (mem/memStep st op)))

fn collectionsOk? tags: (List String) -> Bool
  (listAll? (fn [(t String)] -> Bool
    (listContains? (list "scan entries" "scan edges" "scan resolutions" "scan ids" "kv entries" "kv edges" "kv resolutions" "kv units" "kv bodies" "kv ids" "kv conflicts") t)) tags)

fn errHas? r: (Pair S (Result A String)) what: String -> Bool
  (match (pairSecond r) ((err e) (stringContains? e what)) ((ok _) false))

fn testGeneric -> Bool
  (let [(st0 (pair (mem/memEmpty) (list)))
        (a (vt/ingest st0 recStep 1000 (spec "ea" "alpha")))
        (b (vt/ingest (pairFirst a) recStep 1000 (spec "eb" "beta")))
        (s (vt/supersedeEntry (pairFirst b) recStep 2000 "ea" "eb"))
        (tags (pairSecond (pairFirst s)))]
    (do
      (assert (and (ok? (pairSecond a)) (and (ok? (pairSecond b)) (ok? (pairSecond s)))) "the vault runs unchanged over an adapter with its own state type")
      (assert (> (listLength tags) 10) "the recording adapter saw the vault's ops")
      (assert (collectionsOk? tags) "every op stays inside entries, edges, resolutions, ids, conflicts, units and bodies")
      (assert (listContains? tags "kv bodies") "bodies are written by content hash")
      true))

fn testConflict -> Bool
  (let [(st0 (mem/memEmpty))
        (a (vt/ingest st0 mem/memStep 1000 (spec "ea" "alpha")))
        (b (vt/ingest (pairFirst a) mem/memStep 1000 (spec "eb" "beta")))
        (s (vt/supersedeEntry (pairFirst b) raceStep 2000 "ea" "eb"))
        (edges (vt/loadEdges (pairFirst s) mem/memStep 3000))
        (stat (vt/setEntryStatus (pairFirst edges) raceStep 3000 "eb" "pinned"))
        (ea (vt/getEntry (pairFirst stat) mem/memStep 3000 "ea"))]
    (do
      (assert (errHas? s "ERR_VAULT_CONFLICT") "a supersede whose entry row changed under it is a conflict, not a lost update")
      (assert (match (pairSecond edges) ((ok es) (listEmpty? es)) ((err _) false)) "a conflicting supersede wrote no edge")
      (assert (errHas? stat "ERR_VAULT_CONFLICT") "a status change over a stale revision is a conflict")
      (assert (match (pairSecond ea) ((ok (some e)) (= e.status "corroborated")) (_ false)) "the refused supersede left the old entry live")
      true))

; (:m :ref VS-VAULT :do "a store error reply surfaces as ERR_VAULT_STORE with the code, never as an empty result")
fn failStep st: mem/MemState op: ty/Op -> (Pair mem/MemState ty/Reply)
  (pair st (ty/rErr "ioError" "disk gone"))

fn testStoreErrors -> Bool
  (let [(st0 (mem/memEmpty))
        (r (vt/ingest st0 failStep 1000 (spec "ea" "alpha")))
        (l (vt/loadEntries st0 failStep 1000))
        (bad (vt/ingest st0 mem/memStep 1000 (with (spec "ea" "alpha") :entryId "bad/id")))]
    (do
      (assert (errHas? r "ERR_VAULT_STORE: ioError") "an io error on ingest is reported with its code")
      (assert (errHas? l "ERR_VAULT_STORE") "an io error on a scan is reported")
      (assert (errHas? bad "ERR_VAULT_ARG") "an id that is not one key segment is refused before the store is touched")
      true))

fn runTests -> Bool
  (and (testGeneric) (and (testConflict) (testStoreErrors)))
