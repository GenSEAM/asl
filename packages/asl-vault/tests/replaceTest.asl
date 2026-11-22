(module asl-vault/tests/replaceTest
  :x [runTests]
  :i [(asl-store/types :a ty) (asl-store/mem :a mem) (asl-store/kv :a kv) (asl-vault/model :a m) (asl-vault/vault :a vt)])

fn spec id: String body: String -> vt/IngestSpec
  (vt/IngestSpec :entryId id :kind "note" :layer "topic" :role "evidence" :scope (mapEmpty) :status "corroborated" :provenance "primary" :sourceHashes (list)
                 :title id :summary "" :bodyText body :source "" :licence "" :confidenceBp 9000 :ttlDays 30 :tags (list) :priorityBp 100 :validFrom 0 :replacesEntryId "")

fn repl id: String old: String body: String -> vt/IngestSpec
  (with (spec id body) :replacesEntryId old)

fn pub -> (Map String String)
  (mapSet (mapEmpty) "visibility" "public")

fn priv -> (Map String String)
  (mapSet (mapEmpty) "visibility" "private")

fn errHas? r: (Pair S (Result A String)) what: String -> Bool
  (match (pairSecond r) ((err e) (stringContains? e what)) ((ok _) false))

fn okOf r: (Pair S (Result A String)) -> Bool
  (ok? (pairSecond r))

fn ids r: (Pair S (Result (List m/Entry) String)) -> String
  (match (pairSecond r) ((ok xs) (stringJoin (map (fn [(e m/Entry)] -> String e.entryId) xs) ",")) ((err e) e))

fn statusOf r: (Pair S (Result (Option m/Entry) String)) -> String
  (match (pairSecond r) ((ok (some e)) (str e.status ">" e.supersededBy)) ((ok (none)) "absent") ((err e) e))

fn edgeCount r: (Pair S (Result (List m/Edge) String)) -> Int64
  (match (pairSecond r) ((ok xs) (listLength xs)) ((err _) -1))

; (:m :ref VS-VAULT :do "the rows really stored in a collection, read straight from the adapter, so a test can tell a stored edge from one the readers merely imply")
fn stored st: mem/MemState c: String -> Int64
  (match (pairSecond (mem/memStep st (ty/opScan c "" "" 1000 1)))
    ((ty/rPage rows _) (listLength rows))
    (_ -1))

fn base -> mem/MemState
  (let [(a (vt/ingest (mem/memEmpty) mem/memStep 1000 (spec "A" "alpha")))
        (b (vt/ingest (pairFirst a) mem/memStep 1000 (spec "B" "beta")))]
    (pairFirst b))

; (:m :ref VS-VAULT :do "a crash right after the commit CAS: the replaced row is written, creating the new row or any edge fails")
fn claimOnlyStep st: mem/MemState op: ty/Op -> (Pair mem/MemState ty/Reply)
  (match op
    ((ty/opCas k e _ _ _)
      (if (or (= k.collection "edges") (and (= k.collection "entries") (= e 0)))
        (pair st (ty/rErr "ioError" "crash"))
        (mem/memStep st op)))
    (_ (mem/memStep st op)))

fn bumped st: mem/MemState k: ty/Key now: Int64 -> mem/MemState
  (let [(cur (mem/memStep st (ty/opGet k now)))]
    (pairFirst (mem/memStep st (ty/opPut k (match (pairSecond cur) ((ty/rValue _ v _) v) (_ "")) 0 now))))

fn claimCas? op: ty/Op -> Bool
  (match op ((ty/opCas k e _ _ _) (and (= k.collection "entries") (> e 0))) (_ false))

fn alwaysRace st: mem/MemState op: ty/Op -> (Pair mem/MemState ty/Reply)
  (if (claimCas? op) (mem/memStep (bumped st (kv/keyOfOp op) 1) op) (mem/memStep st op))

fn passThrough st: (Pair mem/MemState Bool) op: ty/Op -> (Pair (Pair mem/MemState Bool) ty/Reply)
  (let [(r (mem/memStep (pairFirst st) op))] (pair (pair (pairFirst r) (pairSecond st)) (pairSecond r)))

; (:m :ref VS-VAULT :do "state (store, fired): the first claim CAS is preceded by another writer's no-op update of that row, later ones are not, so exactly one re-read and retry is needed")
fn onceRace st: (Pair mem/MemState Bool) op: ty/Op -> (Pair (Pair mem/MemState Bool) ty/Reply)
  (if (and (not (pairSecond st)) (claimCas? op))
    (let [(r (mem/memStep (bumped (pairFirst st) (kv/keyOfOp op) 1) op))] (pair (pair (pairFirst r) true) (pairSecond r)))
    (passThrough st op))

; (:m :ref VS-VAULT :do "state (store, fired): before the first claim CAS a rival ingest replaces the same entry A under another id, the interleaving two concurrent replacements produce")
fn rivalFirst st: (Pair mem/MemState Bool) op: ty/Op -> (Pair (Pair mem/MemState Bool) ty/Reply)
  (if (and (not (pairSecond st)) (claimCas? op))
    (let [(rival (vt/ingest (pairFirst st) mem/memStep 1500 (repl "R" "A" "rival body")))
          (r (mem/memStep (pairFirst rival) op))]
      (pair (pair (pairFirst r) true) (pairSecond r)))
    (passThrough st op))

; (:m :ref VS-VAULT :do "state (store, fired): while the first creation of the new row N runs, a rival tries to replace A by M")
fn hijack st: (Pair mem/MemState Bool) op: ty/Op -> (Pair (Pair mem/MemState Bool) ty/Reply)
  (match op
    ((ty/opCas k e _ _ _)
      (if (and (not (pairSecond st)) (and (= k.collection "entries") (and (= k.id "N") (= e 0))))
        (let [(rival (vt/ingest (pairFirst st) mem/memStep 3500 (repl "M" "A" "mu")))
              (r (mem/memStep (pairFirst rival) op))]
          (pair (pair (pairFirst r) true) (pairSecond r)))
        (passThrough st op)))
    (_ (passThrough st op)))

; (:m :ref VS-VAULT :do "after a crash following the commit every reader agrees: the replacement exists, the replaced entry is superseded by it, scope, stats, edges, links and contradictions all use the same view; the sweep then stores row and edge exactly once, however often it runs")
fn testCrashAfterCommit -> Bool
  (let [(a (vt/ingest (mem/memEmpty) mem/memStep 1000 (with (spec "A" "alpha") :scope (pub))))
        (b (vt/ingest (pairFirst a) mem/memStep 1000 (with (spec "B" "beta") :scope (pub))))
        (c (vt/ingest (pairFirst b) claimOnlyStep 2000 (with (repl "N" "A" "nu") :scope (pub))))
        (s1 (pairFirst c))
        (n (vt/getEntry s1 mem/memStep 3000 "N"))
        (ga (vt/getEntry (pairFirst n) mem/memStep 3000 "A"))
        (act (vt/activeEntriesOf (pairFirst ga) mem/memStep 3000))
        (sc (vt/entriesInScope (pairFirst act) mem/memStep 3000 (pub)))
        (stats (vt/vaultStats (pairFirst sc) mem/memStep 3000))
        (edges (vt/loadEdges (pairFirst stats) mem/memStep 3000))
        (link (vt/linkEntries (pairFirst edges) mem/memStep 3100 "A" "B" "contradicts" 9000))
        (open (vt/openContradictionsOf (pairFirst link) mem/memStep 3200))
        (gb (vt/getEntry (pairFirst open) mem/memStep 3300 "B"))
        (ga2 (vt/getEntry (pairFirst gb) mem/memStep 3300 "A"))
        (sweep1 (vt/completePending (pairFirst ga2) mem/memStep 4000))
        (rows1 (stored (pairFirst sweep1) "entries"))
        (edges1 (stored (pairFirst sweep1) "edges"))
        (sweep2 (vt/completePending (pairFirst sweep1) mem/memStep 4100))
        (edges2 (stored (pairFirst sweep2) "edges"))
        (act2 (vt/activeEntriesOf (pairFirst sweep2) mem/memStep 4200))]
    (do
      (assert (errHas? c "ERR_VAULT_STORE") "the crash after the commit is reported")
      (assert (= (stored s1 "entries") 2) "the new row was not stored")
      (assert (= (stored s1 "edges") 0) "and no edge was stored")
      (assert (= (statusOf n) "corroborated>") "getEntry reads the new entry from the payload")
      (assert (= (statusOf ga) "superseded>N") "getEntry reads the replaced entry as superseded by it")
      (assert (= (ids act) "B,N") "activeEntries: replaced out, replacement in")
      (assert (= (ids sc) "B,N") "entriesInScope agrees")
      (assert (match (pairSecond stats) ((ok x) (and (= x.activeEntries 2) (and (= x.supersededCount 1) (= x.edgeCount 1)))) (_ false)) "stats agree: 2 active, 1 superseded, the implied edge counted")
      (assert (= (edgeCount edges) 1) "the refines edge is read although it was never stored")
      (assert (okOf link) "an inactive end can be linked")
      (assert (match (pairSecond open) ((ok xs) (listEmpty? xs)) (_ false)) "a contradiction with the superseded end is not open")
      (assert (= (statusOf gb) "disputed>") "the live end of the link is disputed")
      (assert (= (statusOf ga2) "superseded>N") "the superseded end keeps its status through the link")
      (assert (match (pairSecond sweep1) ((ok k) (= k 1)) (_ false)) "the sweep looks at one payload")
      (assert (and (= rows1 3) (= edges1 2)) "the sweep stored the row and the refines edge next to the stored contradicts edge")
      (assert (and (okOf sweep2) (= edges2 2)) "a second sweep stores nothing more")
      (assert (= (ids act2) "B,N") "the sweep changed no reader's answer")
      true))

; (:m :ref VS-VAULT :do "the same spec repeated finishes the replacement without a second edge or entry; once complete a repeat is idempotent")
fn testResume -> Bool
  (let [(c (vt/ingest (base) claimOnlyStep 2000 (repl "N" "A" "nu")))
        (r1 (vt/ingest (pairFirst c) mem/memStep 5000 (repl "N" "A" "nu")))
        (e1 (stored (pairFirst r1) "edges"))
        (swept (vt/completePending (pairFirst r1) mem/memStep 5500))
        (r2 (vt/ingest (pairFirst swept) mem/memStep 6000 (repl "N" "A" "nu")))
        (e2 (stored (pairFirst r2) "edges"))
        (act (vt/activeEntriesOf (pairFirst r2) mem/memStep 7000))]
    (do
      (assert (okOf r1) "repeating the spec after the crash finishes it")
      (assert (= e1 1) "and stores the edge once")
      (assert (okOf swept) "a sweep after the repeat is fine")
      (assert (okOf r2) "repeating a finished replacement is idempotent")
      (assert (= e2 1) "and adds no second edge")
      (assert (= (ids act) "B,N") "the live set is B and N")
      true))

; (:m :ref VS-VAULT :do "two writers replacing one entry: the CAS on its row serialises them, the loser gets ERR_VAULT_SUPERSEDED and creates no entry, no edge, no resolution; also when the second writer had already read the row before the first one committed")
fn testTwoWriters -> Bool
  (let [(one (vt/ingest (base) mem/memStep 2000 (repl "N1" "A" "first")))
        (two (vt/ingest (pairFirst one) mem/memStep 3000 (repl "N2" "A" "second")))
        (act (vt/activeEntriesOf (pairFirst two) mem/memStep 4000))
        (n2 (vt/getEntry (pairFirst act) mem/memStep 4000 "N2"))
        (rv (vt/ingest (pair (base) false) rivalFirst 2000 (repl "mine" "A" "my body")))
        (sv (pairFirst (pairFirst rv)))
        (actRv (vt/activeEntriesOf sv mem/memStep 4000))
        (mine (vt/getEntry (pairFirst actRv) mem/memStep 4000 "mine"))
        (ed (vt/loadEdges (pairFirst mine) mem/memStep 4000))
        (stuck (vt/ingest (base) alwaysRace 2000 (repl "N" "A" "nu")))
        (actStuck (vt/activeEntriesOf (pairFirst stuck) mem/memStep 3000))
        (once (vt/ingest (pair (base) false) onceRace 2000 (repl "N" "A" "nu")))
        (actOnce (vt/activeEntriesOf (pairFirst (pairFirst once)) mem/memStep 3000))]
    (do
      (assert (okOf one) "the first replacement wins")
      (assert (errHas? two "ERR_VAULT_SUPERSEDED") "the second replacement of the same entry is refused")
      (assert (= (ids act) "B,N1") "exactly one replacement is live")
      (assert (match (pairSecond n2) ((ok (none)) true) (_ false)) "the loser created no entry")
      (assert (errHas? rv "ERR_VAULT_SUPERSEDED") "a writer that read before the rival committed loses at the CAS")
      (assert (= (ids actRv) "B,R") "exactly the rival's replacement is live")
      (assert (match (pairSecond mine) ((ok (none)) true) (_ false)) "the loser left no entry")
      (assert (= (edgeCount ed) 1) "and no edge, only the winner's")
      (assert (errHas? stuck "ERR_VAULT_CONFLICT") "a claim that keeps losing the revision race ends in a conflict")
      (assert (= (ids actStuck) "A,B") "and nothing changed")
      (assert (okOf once) "one lost revision race is absorbed by a re-read and retry")
      (assert (= (ids actOnce) "B,N") "and the replacement is live")
      true))

fn foreignEntry id: String body: String -> m/Entry
  (let [(r (vt/ingest (mem/memEmpty) mem/memStep 900 (spec id body)))
        (g (vt/getEntry (pairFirst r) mem/memStep 900 id))]
    (match (pairSecond g) ((ok (some e)) e) (_ (m/Entry :entryId "" :unitHash "" :bodyHash "" :layer "" :role "" :scope (mapEmpty) :status "" :supersededBy "" :pending "" :provenance "" :sourceHashes (list) :title "" :summary "" :tags (list) :priorityBp 0 :validFrom 0 :validTo 0 :recordedAt 0 :updatedAt 0))))

; (:m :ref VS-VAULT :do "an id reserved by a committed replacement cannot be taken by an unrelated ingest, with or without replaces; two committed replacements of different entries under one id are refused; and a foreign row that appears under the id anyway is a collision: reported, recorded under conflicts, never read in place of the payload")
fn testReservation -> Bool
  (let [(c1 (vt/ingest (base) claimOnlyStep 2000 (repl "N" "A" "nu")))
        (c2 (vt/ingest (pairFirst c1) claimOnlyStep 2100 (repl "N" "B" "nu")))
        (plain (vt/ingest (pairFirst c2) mem/memStep 3000 (spec "N" "unrelated")))
        (viaB (vt/ingest (pairFirst plain) mem/memStep 3100 (repl "N" "B" "unrelated")))
        (act (vt/activeEntriesOf (pairFirst viaB) mem/memStep 3200))
        (fe (foreignEntry "N" "foreign"))
        (injected (pairFirst (mem/memStep (pairFirst act) (ty/opPut (ty/Key :collection "entries" :id "N") (m/emitEntry fe) 0 3300))))
        (n (vt/getEntry injected mem/memStep 3400 "N"))
        (sweep (vt/completePending injected mem/memStep 3500))
        (n2 (vt/getEntry (pairFirst sweep) mem/memStep 3600 "N"))
        (ga (vt/getEntry (pairFirst n2) mem/memStep 3600 "A"))
        (touch (vt/setEntryStatus (pairFirst ga) mem/memStep 3700 "N" "pinned"))]
    (do
      (assert (errHas? plain "ERR_VAULT_EXISTS") "an unrelated ingest of a reserved id is refused")
      (assert (errHas? c2 "ERR_VAULT_EXISTS") "a second committed replacement under the same id is refused")
      (assert (errHas? viaB "ERR_VAULT_EXISTS") "so is an unrelated replacement of another entry under it")
      (assert (= (ids act) "B,N") "nothing but the first replacement changed the live set")
      (assert (match (pairSecond n) ((ok (some e)) (and (= e.bodyHash (un-hash "nu")) (not (= e.bodyHash fe.bodyHash)))) (_ false)) "a foreign row under the id does not replace the payload in reads")
      (assert (errHas? sweep "ERR_VAULT_ID_COLLISION") "completing the replacement reports the collision")
      (assert (= (stored (pairFirst sweep) "conflicts") 1) "and records the foreign row under conflicts")
      (assert (= (statusOf ga) "superseded>N") "the logical state still follows the replaced entry")
      (assert (match (pairSecond n2) ((ok (some e)) (= e.bodyHash (un-hash "nu"))) (_ false)) "the payload still wins after the sweep")
      (assert (errHas? touch "ERR_VAULT_") "a write to the colliding id is refused rather than merged")
      true))

; (:m :ref VS-VAULT :do "a repeat while a rival tries to replace A during the completion cannot produce a second live replacement: the rival is refused at A, the repeat completes")
fn testRepeatWithHijack -> Bool
  (let [(c (vt/ingest (base) claimOnlyStep 2000 (repl "N" "A" "nu")))
        (retry (vt/ingest (pair (pairFirst c) false) hijack 3000 (repl "N" "A" "nu")))
        (sv (pairFirst (pairFirst retry)))
        (act (vt/activeEntriesOf sv mem/memStep 4000))
        (a (vt/getEntry (pairFirst act) mem/memStep 4000 "A"))
        (m1 (vt/getEntry (pairFirst a) mem/memStep 4000 "M"))
        (again (vt/ingest (pairFirst m1) mem/memStep 5000 (repl "N" "A" "nu")))]
    (do
      (assert (okOf retry) "the repeat completes")
      (assert (= (ids act) "B,N") "exactly one replacement of A is live")
      (assert (= (statusOf a) "superseded>N") "A stays superseded by N")
      (assert (match (pairSecond m1) ((ok (none)) true) (_ false)) "the rival's entry was never created")
      (assert (okOf again) "a further repeat is idempotent")
      true))

fn scopeSpec id: String sc: (Map String String) -> vt/IngestSpec
  (with (spec id "same body") :scope sc)

; (:m :ref VS-VAULT :do "an existing id is never adopted as a replacement: not across a scope boundary, not when it was created without replacing anything even if every field matches, not with another scope, source or tags; the exact repeat of a crashed ingest still resumes")
fn testNoAdoption -> Bool
  (let [(a (vt/ingest (mem/memEmpty) mem/memStep 1000 (with (scopeSpec "old" (pub)) :bodyText "old body")))
        (x (vt/ingest (pairFirst a) mem/memStep 1500 (with (scopeSpec "X" (priv)) :role "secret" :source "private:notes")))
        (r (vt/ingest (pairFirst x) mem/memStep 2000 (with (scopeSpec "X" (pub)) :replacesEntryId "old")))
        (q (vt/entriesInScope (pairFirst r) mem/memStep 3000 (pub)))
        (z (vt/ingest (pairFirst q) mem/memStep 3500 (scopeSpec "Z" (pub))))
        (zr (vt/ingest (pairFirst z) mem/memStep 3600 (with (scopeSpec "Z" (pub)) :replacesEntryId "old")))
        (oldZ (vt/getEntry (pairFirst zr) mem/memStep 3700 "old"))
        (c (vt/ingest (pairFirst oldZ) claimOnlyStep 4000 (with (scopeSpec "Y" (pub)) :replacesEntryId "old")))
        (wrongScope (vt/ingest (pairFirst c) mem/memStep 5000 (with (scopeSpec "Y" (priv)) :replacesEntryId "old")))
        (wrongSrc (vt/ingest (pairFirst wrongScope) mem/memStep 5000 (with (scopeSpec "Y" (pub)) :replacesEntryId "old" :source "elsewhere")))
        (wrongTags (vt/ingest (pairFirst wrongSrc) mem/memStep 5000 (with (scopeSpec "Y" (pub)) :replacesEntryId "old" :tags (list "t"))))
        (edges (stored (pairFirst wrongTags) "edges"))
        (ok1 (vt/ingest (pairFirst wrongTags) mem/memStep 6000 (with (scopeSpec "Y" (pub)) :replacesEntryId "old")))]
    (do
      (assert (errHas? r "ERR_VAULT_EXISTS") "an existing entry of another scope is not adopted as the replacement")
      (assert (= (ids q) "old") "the public old entry stays live and visible, the private X does not cross into the public scope")
      (assert (errHas? zr "ERR_VAULT_EXISTS") "an entry created without replacing anything is not adopted even when every field matches")
      (assert (= (statusOf oldZ) "corroborated>") "and old is not claimed by it")
      (assert (errHas? c "ERR_VAULT_STORE") "control: the crash after the commit")
      (assert (errHas? wrongScope "ERR_VAULT_EXISTS") "a retry with another scope is not a resume")
      (assert (errHas? wrongSrc "ERR_VAULT_EXISTS") "a retry with another unit source is not a resume")
      (assert (errHas? wrongTags "ERR_VAULT_EXISTS") "a retry with other tags is not a resume")
      (assert (= edges 0) "the refused retries stored no edge")
      (assert (okOf ok1) "the exact repeat resumes")
      true))

fn noCreateX st: mem/MemState op: ty/Op -> (Pair mem/MemState ty/Reply)
  (match op
    ((ty/opCas k e _ _ _) (if (and (= k.collection "entries") (and (= k.id "X") (= e 0))) (pair st (ty/rErr "ioError" "crash")) (mem/memStep st op)))
    (_ (mem/memStep st op)))

fn plainHook st: mem/MemState op: ty/Op -> (Pair mem/MemState ty/Reply)
  (match op
    ((ty/opCas k e v ttl now)
      (if (and (= k.collection "entries") (and (= k.id "X") (and (= e 0) (stringContains? v "plainX"))))
        (mem/memStep (pairFirst (vt/ingest st noCreateX now (with (repl "X" "A" "replacement body") :title "replX"))) op)
        (mem/memStep st op)))
    (_ (mem/memStep st op)))

; (:m :ref VS-VAULT :do "a replacement for X starts between the reservation and the create of a plain ingest of X: it is refused at the ids row, the plain writer keeps X and X stays writable")
fn testPlainInterleave -> Bool
  (let [(p (vt/ingest (base) plainHook 2000 (with (spec "X" "plain body") :title "plainX")))
        (live (vt/activeEntriesOf (pairFirst p) mem/memStep 3000))
        (sw (vt/completePending (pairFirst live) mem/memStep 3100))
        (stx (vt/setEntryStatus (pairFirst sw) mem/memStep 3200 "X" "pinned"))
        (a (vt/getEntry (pairFirst stx) mem/memStep 3300 "A"))
        (rep (vt/ingest (pairFirst stx) mem/memStep 3400 (repl "Y" "X" "y")))]
    (do
      (assert (okOf p) "the plain ingest of X is ok")
      (assert (= (ids live) "A,B,X") (str "live: " (ids live)))
      (assert (= (statusOf a) "corroborated>") "the interleaved replacement did not touch A")
      (assert (and (okOf sw) (okOf stx)) "sweep and a status write on X pass")
      (assert (okOf rep) "X can be replaced afterwards"))
    true)

fn replHook st: mem/MemState op: ty/Op -> (Pair mem/MemState ty/Reply)
  (match op
    ((ty/opCas k e v ttl now)
      (if (and (= k.collection "entries") (and (= k.id "A") (stringContains? v "fromA")))
        (mem/memStep (pairFirst (vt/ingest st mem/memStep now (with (repl "N" "B" "from B") :title "fromB"))) op)
        (mem/memStep st op)))
    (_ (mem/memStep st op)))

; (:m :ref VS-VAULT :do "two replacements with one new id: the second is refused at the ids row, the first keeps its commit and both old entries stay as the first left them")
fn testSameNewId -> Bool
  (let [(r (vt/ingest (base) replHook 2000 (with (repl "N" "A" "from A") :title "fromA")))
        (live (vt/activeEntriesOf (pairFirst r) mem/memStep 3000))
        (b (vt/getEntry (pairFirst live) mem/memStep 3100 "B"))
        (stn (vt/setEntryStatus (pairFirst live) mem/memStep 3200 "N" "pinned"))
        (second (vt/ingest (pairFirst stn) mem/memStep 3300 (with (repl "N" "B" "from B") :title "fromB")))]
    (do
      (assert (okOf r) (str "A replace ok"))
      (assert (= (ids live) "B,N") (str "live: " (ids live)))
      (assert (= (statusOf b) "corroborated>") "B was not superseded by the refused one")
      (assert (okOf stn) "a status write on N passes")
      (assert (errHas? second "ERR_VAULT_EXISTS") "a later replacement with the same id is refused")
      true))

fn pendingOf st: mem/MemState id: String -> String
  (match (pairSecond (mem/memStep st (ty/opGet (ty/Key :collection "entries" :id id) 5000)))
    ((ty/rValue _ v _) (if (stringContains? v ":pending \"\"") "clear" "pending"))
    (_ "absent"))

fn crashClear st: mem/MemState op: ty/Op -> (Pair mem/MemState ty/Reply)
  (match op
    ((ty/opCas k e v _ _) (if (and (= k.collection "entries") (and (= k.id "A") (stringContains? v ":pending \"\""))) (pair st (ty/rErr "ioError" "crash")) (mem/memStep st op)))
    (_ (mem/memStep st op)))

; (:m :ref VS-VAULT :do "the payload is cleared from the replaced row once the new entry exists; a crash on that clearing is finished by the sweep")
fn testClearing -> Bool
  (let [(ok1 (vt/ingest (base) mem/memStep 2000 (repl "N" "A" "nu")))
        (crashed (vt/ingest (base) crashClear 2000 (repl "N" "A" "nu")))
        (mid (pendingOf (pairFirst crashed) "A"))
        (sw (vt/completePending (pairFirst crashed) mem/memStep 3000))
        (sw2 (vt/completePending (pairFirst sw) mem/memStep 3100))]
    (do
      (assert (= (pendingOf (pairFirst ok1) "A") "clear") "no payload remains after a clean replacement")
      (assert (errHas? crashed "ERR_VAULT_STORE") "control: the crash on clearing")
      (assert (= mid "pending") "the payload is still there after that crash")
      (assert (okOf sw) "the sweep completes")
      (assert (= (pendingOf (pairFirst sw) "A") "clear") "and clears it")
      (assert (match (pairSecond sw2) ((ok n) (= n 0)) (_ false)) "a second sweep finds nothing")
      true))

fn noDone st: mem/MemState op: ty/Op -> (Pair mem/MemState ty/Reply)
  (match op
    ((ty/opCas k e _ _ _) (if (and (= k.collection "resolutions") (> e 0)) (pair st (ty/rErr "ioError" "crash")) (mem/memStep st op)))
    (_ (mem/memStep st op)))

fn resStates st: mem/MemState -> String
  (match (pairSecond (vt/loadResolutions st mem/memStep 5000)) ((ok xs) (stringJoin (map (fn [(r m/Resolution)] -> String r.state) xs) ",")) ((err e) e))

; (:m :ref VS-VAULT :do "the resolution row exists as pending before the outcome is applied, so a crash on the final write leaves the outcome and a pending row, never an outcome without a row; a repeat and the sweep each finish it to exactly one done row")
fn testResolveCrash -> Bool
  (let [(l (vt/linkEntries (base) mem/memStep 1500 "A" "B" "contradicts" 9000))
        (c (vt/resolveContradiction (pairFirst l) noDone 2000 "r1" "A" "B" "acceptA" "n"))
        (live (vt/activeEntriesOf (pairFirst c) mem/memStep 3000))
        (mid (resStates (pairFirst c)))
        (again (vt/resolveContradiction (pairFirst c) mem/memStep 3200 "r1" "A" "B" "acceptA" "n"))
        (c2 (vt/resolveContradiction (pairFirst l) noDone 2000 "r1" "A" "B" "acceptA" "n"))
        (sw (vt/completePending (pairFirst c2) mem/memStep 3300))
        (sw2 (vt/completePending (pairFirst sw) mem/memStep 3400))
        (open (vt/openContradictionsOf (pairFirst again) mem/memStep 3500))]
    (do
      (assert (errHas? c "ERR_VAULT_STORE") "control: the crash on the final write")
      (assert (= (ids live) "A") (str "live after the crash: " (ids live)))
      (assert (= mid "pending") (str "the row is pending: " mid))
      (assert (okOf again) (str "the repeat finishes " (errText again)))
      (assert (= (resStates (pairFirst again)) "done") "exactly one row, done, after the repeat")
      (assert (and (okOf sw) (match (pairSecond sw) ((ok n) (>= n 1)) (_ false))) "the sweep finishes a pending resolution")
      (assert (= (resStates (pairFirst sw)) "done") "exactly one row, done, after the sweep")
      (assert (match (pairSecond sw2) ((ok n) (= n 0)) (_ false)) "a second sweep finds nothing")
      (assert (match (pairSecond open) ((ok xs) (= (listLength xs) 0)) (_ false)) "no open contradiction")
      true))

fn failA st: mem/MemState op: ty/Op -> (Pair mem/MemState ty/Reply)
  (match op
    ((ty/opCas k e v ttl now) (if (and (= k.collection "entries") (= k.id "A")) (pair st (ty/rErr "ioError" "w1 crash")) (mem/memStep st op)))
    (_ (mem/memStep st op)))

fn releaseHook st: mem/MemState op: ty/Op -> (Pair mem/MemState ty/Reply)
  (match op
    ((ty/opCas k e v ttl now)
      (if (and (= k.collection "entries") (and (= k.id "A") (stringContains? v "replX")))
        (let [(w1 (vt/ingest st failA now (with (repl "X" "A" "replacement body") :title "replX")))
              (w3 (vt/ingest (pairFirst w1) mem/memStep now (with (spec "X" "plain body") :title "plainX")))]
          (mem/memStep (pairFirst w3) op))
        (mem/memStep st op)))
    (_ (mem/memStep st op)))

; (:m :ref VS-VAULT :do "a failed writer with the same token must not free the reservation a live writer with that token still holds: a third plain writer of the id is refused and the replacement keeps X")
fn testNoRelease -> Bool
  (let [(w2 (vt/ingest (base) releaseHook 2000 (with (repl "X" "A" "replacement body") :title "replX")))
        (live (vt/activeEntriesOf (pairFirst w2) mem/memStep 3000))
        (x (vt/getEntry (pairFirst live) mem/memStep 3100 "X"))]
    (do
      (assert (okOf w2) (str "w2 stays ok"))
      (assert (= (ids live) "B,X") (str "live: " (ids live)))
      (assert (match (pairSecond x) ((ok (some e)) (= e.title "replX")) (_ false)) "X is the replacement, not the plain write")
      true))

fn crashAfterReserve st: mem/MemState op: ty/Op -> (Pair mem/MemState ty/Reply)
  (match op
    ((ty/opCas k e v ttl now) (if (= k.collection "ids") (mem/memStep st op) (pair st (ty/rErr "ioError" "crash"))))
    (_ (mem/memStep st op)))

fn idsRows st: mem/MemState -> Int64
  (stored st "ids")

; (:m :ref VS-VAULT :do "a reservation orphaned by a crash blocks other claims until the TTL, the same spec resumes at once, and after the TTL another claim takes it over by CAS or the sweep deletes it")
fn testOrphanReservation -> Bool
  (let [(c (vt/ingest (base) crashAfterReserve 2000 (spec "X" "first")))
        (early (vt/ingest (pairFirst c) mem/memStep 3000 (spec "X" "someone else")))
        (swEarly (vt/completePending (pairFirst early) mem/memStep 3100))
        (resume (vt/ingest (pairFirst swEarly) mem/memStep 3200 (spec "X" "first")))
        (c2 (vt/ingest (base) crashAfterReserve 2000 (spec "Y" "first")))
        (swLate (vt/completePending (pairFirst c2) mem/memStep 9000000))
        (late (vt/ingest (pairFirst swLate) mem/memStep 9000001 (spec "Y" "someone else")))
        (c3 (vt/ingest (base) crashAfterReserve 2000 (spec "Z" "first")))
        (takeover (vt/ingest (pairFirst c3) mem/memStep 9000000 (spec "Z" "someone else")))]
    (do
      (assert (errHas? c "ERR_VAULT_STORE") "control: crash after the reservation")
      (assert (errHas? early "ERR_VAULT_EXISTS") "another claim inside the TTL is refused")
      (assert (= (idsRows (pairFirst swEarly)) 3) "the sweep keeps a fresh reservation")
      (assert (okOf resume) "the same spec resumes at once")
      (assert (= (idsRows (pairFirst swLate)) 2) "the sweep deletes the stale orphan (A and B remain)")
      (assert (okOf late) "after the sweep the id is free")
      (assert (okOf takeover) "a stale reservation is taken over by CAS without a sweep")
      true))

; (:m :ref VS-VAULT :do "a resolve cannot revive: B replaced by A, A replaced by C, then acceptA of A over B is refused, and nothing is written")
fn testResolveNoResurrect -> Bool
  (let [(c (vt/ingest (base) mem/memStep 1000 (spec "C" "gamma")))
        (s1 (vt/supersedeEntry (pairFirst c) mem/memStep 2000 "B" "A"))
        (s2 (vt/supersedeEntry (pairFirst s1) mem/memStep 2100 "A" "C"))
        (l (vt/linkEntries (pairFirst s2) mem/memStep 2200 "A" "B" "contradicts" 9000))
        (r (vt/resolveContradiction (pairFirst l) mem/memStep 2300 "r1" "A" "B" "acceptA" "n"))
        (a (vt/getEntry (pairFirst r) mem/memStep 2400 "A"))
        (live (vt/activeEntriesOf (pairFirst r) mem/memStep 2400))]
    (do
      (assert (and (okOf s1) (okOf s2)) "setup supersedes")
      (assert (errHas? r "ERR_VAULT_") (str "acceptA with a superseded winner is refused"))
      (assert (= (statusOf a) "superseded>C") "A stays superseded")
      (assert (= (ids live) "C") (str "live: " (ids live)))
      true))

fn errText r: (Pair S (Result A String)) -> String
  (match (pairSecond r) ((err e) e) ((ok _) ""))

fn failWinner st: mem/MemState op: ty/Op -> (Pair mem/MemState ty/Reply)
  (match op
    ((ty/opCas k e v ttl now) (if (and (= k.collection "entries") (= k.id "A")) (pair st (ty/rErr "ioError" "crash")) (mem/memStep st op)))
    (_ (mem/memStep st op)))

; (:m :ref VS-VAULT :do "a crash after the loser's commit and before the winner is promoted: the loser carries the winner as payload, readers agree, a repeat finishes, and a different resolve over the same pair does not resume")
fn testResolveCrashMid -> Bool
  (let [(l (vt/linkEntries (base) mem/memStep 1500 "A" "B" "contradicts" 9000))
        (c (vt/resolveContradiction (pairFirst l) failWinner 2000 "r1" "A" "B" "acceptA" "n"))
        (b (vt/getEntry (pairFirst c) mem/memStep 3000 "B"))
        (a (vt/getEntry (pairFirst c) mem/memStep 3000 "A"))
        (live (vt/activeEntriesOf (pairFirst c) mem/memStep 3000))
        (pend (pendingOf (pairFirst c) "B"))
        (again (vt/resolveContradiction (pairFirst c) mem/memStep 3200 "r1" "A" "B" "acceptA" "n"))
        (rs (stored (pairFirst again) "resolutions"))
        (pend2 (pendingOf (pairFirst again) "B"))]
    (do
      (assert (errHas? c "ERR_VAULT_STORE") "control: crash on the winner")
      (assert (= pend "pending") "the loser carries the payload")
      (assert (= (statusOf b) "superseded>A") "readers see the loser superseded")
      (assert (= (ids live) "A") (str "live: " (ids live)))
      (assert (okOf again) (str "the repeat finishes " (match (pairSecond again) ((err e) e) ((ok _) ""))))
      (assert (= rs 1) "one resolution row")
      (assert (= pend2 "clear") "the payload is cleared")
      true))

fn slowHook1 st: mem/MemState op: ty/Op -> (Pair mem/MemState ty/Reply)
  (match op
    ((ty/opCas k e v ttl now)
      (if (and (= k.collection "bodies") (stringContains? v "slow body"))
        (mem/memStep (pairFirst (vt/ingest st mem/memStep (+ now 3700000) (with (spec "X" "fast body") :title "fastX"))) op)
        (mem/memStep st op)))
    (_ (mem/memStep st op)))

fn slowHook2 st: mem/MemState op: ty/Op -> (Pair mem/MemState ty/Reply)
  (match op
    ((ty/opCas k e v ttl now)
      (if (and (= k.collection "entries") (and (= k.id "A") (stringContains? v "slowX")))
        (mem/memStep (pairFirst (vt/ingest st mem/memStep (+ now 3700000) (with (spec "X" "fast body") :title "fastX"))) op)
        (mem/memStep st op)))
    (_ (mem/memStep st op)))

; (:m :ref VS-VAULT :do "a writer stalled past the TTL while another claim took its id: stalled before the last check it gets EXISTS and writes nothing; stalled inside the commit window the stored row of the holder of the reservation wins in every reader and stays writable")
fn testSlowWriter -> Bool
  (let [(w1 (vt/ingest (base) slowHook1 2000 (with (repl "X" "A" "slow body") :title "slowX")))
        (a (vt/getEntry (pairFirst w1) mem/memStep 4000000 "A"))
        (live (vt/activeEntriesOf (pairFirst w1) mem/memStep 4000000))
        (x (vt/getEntry (pairFirst live) mem/memStep 4000001 "X"))
        (stx (vt/setEntryStatus (pairFirst live) mem/memStep 4000002 "X" "pinned"))
        (v1 (vt/ingest (base) slowHook2 2000 (with (repl "X" "A" "slow body") :title "slowX")))
        (live2 (vt/activeEntriesOf (pairFirst v1) mem/memStep 4000000))
        (x2 (vt/getEntry (pairFirst live2) mem/memStep 4000001 "X"))
        (stx2 (vt/setEntryStatus (pairFirst live2) mem/memStep 4000002 "X" "pinned"))
        (a2 (vt/getEntry (pairFirst v1) mem/memStep 4000000 "A"))
        (cy (vt/ingest (pairFirst v1) claimOnlyStep 4000100 (repl "Y" "B" "y")))
        (sw (vt/completePending (pairFirst cy) mem/memStep 4000200))
        (sw2 (vt/completePending (pairFirst sw) mem/memStep 4000300))
        (a3 (vt/getEntry (pairFirst sw2) mem/memStep 4000400 "A"))
        (y (vt/getEntry (pairFirst sw2) mem/memStep 4000400 "Y"))
        (live3 (vt/activeEntriesOf (pairFirst sw2) mem/memStep 4000400))]
    (do
      (assert (errHas? w1 "ERR_VAULT_EXISTS") (str "stalled before the check: " (errText w1)))
      (assert (= (statusOf a) "corroborated>") "nothing was committed on A")
      (assert (= (ids live) "A,B,X") (str "live: " (ids live)))
      (assert (match (pairSecond x) ((ok (some e)) (= e.title "fastX")) (_ false)) "X is the fast writer's")
      (assert (okOf stx) "and writable")
      (assert (errHas? v1 "ERR_VAULT_ID_COLLISION") (str "stalled inside the window: " (errText v1)))
      (assert (= (ids live2) "A,B,X") (str "live in the window case: " (ids live2)))
      (assert (= (statusOf a2) "corroborated>") "A reads as before the dead commit")
      (assert (errHas? cy "ERR_VAULT_STORE") "control: Y committed without its row")
      (assert (okOf sw) (str "the sweep is not blocked by the dead payload: " (errText sw)))
      (assert (match (pairSecond sw) ((ok n) (>= n 2)) (_ false)) "it rolled back A and completed Y")
      (assert (match (pairSecond sw2) ((ok n) (= n 0)) (_ false)) "and is idempotent")
      (assert (= (statusOf a3) "corroborated>") "A is stored as before the commit")
      (assert (match (pairSecond y) ((ok (some e)) (= e.entryId "Y")) (_ false)) "Y is written")
      (assert (= (ids live3) "A,X,Y") (str "live after the sweep: " (ids live3)))
      (assert (match (pairSecond x2) ((ok (some e)) (= e.title "fastX")) (_ false)) "the stored holder of the reservation wins in readers")
      (assert (okOf stx2) "and stays writable")
      true))

; (:m :ref VS-VAULT :do "one colliding row does not stop the sweep: the rows after it are still completed and the error is reported at the end")
fn testSweepContinues -> Bool
  (let [(c1 (vt/ingest (base) claimOnlyStep 2000 (repl "N" "A" "nu")))
        (inj (pairFirst (mem/memStep (pairFirst c1) (ty/opPut (ty/Key :collection "entries" :id "N") (m/emitEntry (foreignEntry "N" "foreign")) 0 2100))))
        (cy (vt/ingest inj claimOnlyStep 2200 (repl "Y" "B" "y")))
        (before (stored (pairFirst cy) "entries"))
        (sw (vt/completePending (pairFirst cy) mem/memStep 3000))
        (after (stored (pairFirst sw) "entries"))]
    (do
      (assert (errHas? cy "ERR_VAULT_STORE") "control: Y committed without its row")
      (assert (= before 3) "A, B and the foreign N are stored")
      (assert (errHas? sw "ERR_VAULT_ID_COLLISION") "the collision is reported")
      (assert (= after 4) "and Y was written although it sorts after the bad row")
      true))

fn un-hash s: String -> String
  (bytesSha256 (stringToBytes s))

fn runTests -> Bool
  (and (testCrashAfterCommit) (and (testResume) (and (testTwoWriters) (and (testReservation) (and (testRepeatWithHijack) (and (testNoAdoption) (and (testPlainInterleave) (and (testSameNewId) (and (testClearing) (and (testResolveCrash) (and (testNoRelease) (and (testOrphanReservation) (and (testResolveNoResurrect) (and (testResolveCrashMid) (and (testSlowWriter) (testSweepContinues)))))))))))))))
)
