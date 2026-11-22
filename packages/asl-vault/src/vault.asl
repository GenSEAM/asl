(module asl-vault/vault
  :x [IngestSpec IngestResult VaultStats EntryRow ingest completePending getEntry loadEntries loadEdges loadResolutions linkEntries setEntryStatus supersedeEntry resolveContradiction
      openContradictionsOf activeEntriesOf entriesInScope vaultStats getUnit getBody validateSpec]
  :i [(asl-store/types :a ty)
      (asl-vault/model :a m) (asl-vault/unit :a un) (asl-vault/graph :a g) (asl-vault/curate :a cu) (asl-vault/codec :a cd)])

; (:m :ref VS-VAULT :do "the vault keeps one store collection per kind: entries/<id>, edges/<from>/<relation>/<to>, resolutions/<id>, units/<sha256> and bodies/<sha256>; every function takes the adapter as a step function over any state S and threads that state, so memStep and an effectful adapter run the same code")
(schema EntryRow (:f rev Int64) (:f entry m/Entry))

(schema IngestSpec
  (:f entryId String) (:f kind String) (:f layer String) (:f role String) (:f scope (Map String String)) (:f status String)
  (:f provenance String) (:f sourceHashes (List String)) (:f title String) (:f summary String) (:f bodyText String)
  (:f source String) (:f licence String) (:f confidenceBp Int64) (:f ttlDays Int64) (:f tags (List String)) (:f priorityBp Int64)
  (:f validFrom Int64) (:f replacesEntryId String))

(schema IngestResult (:f entry m/Entry) (:f unitHash String) (:f passageCount Int64))

(schema VaultStats
  (:f totalEntries Int64) (:f activeEntries Int64) (:f pinnedCount Int64) (:f disputedCount Int64) (:f supersededCount Int64)
  (:f quarantinedCount Int64) (:f staleCount Int64) (:f edgeCount Int64) (:f openContradictions Int64))

fn bind p: (Pair S (Result A String)) f: (fn [S A] -> (Pair S (Result B String))) -> (Pair S (Result B String))
  (match (pairSecond p)
    ((err e) (pair (pairFirst p) (err e)))
    ((ok a) (f (pairFirst p) a)))

fn done st: S v: A -> (Pair S (Result A String))
  (pair st (ok v))

fn fail st: S why: String -> (Pair S (Result A String))
  (pair st (err why))

fn key c: String id: String -> ty/Key
  (ty/Key :collection c :id id)

fn storeErr r: ty/Reply -> String
  (match r
    ((ty/rErr code text) (str "ERR_VAULT_STORE: " code " " text))
    (_ "ERR_VAULT_STORE: unexpected reply"))

fn getRow st: S step: (fn [S ty/Op] -> (Pair S ty/Reply)) c: String id: String now: Int64 -> (Pair S (Result (Option (Pair Int64 String)) String))
  (let [(r (step st (ty/opGet (key c id) now)))]
    (match (pairSecond r)
      ((ty/rValue rev v _) (done (pairFirst r) (some (pair rev v))))
      ((ty/rAbsent) (done (pairFirst r) (none)))
      (other (fail (pairFirst r) (storeErr other)))))

; (:m :ref VS-VAULT :do "expectRev 0 creates, n updates revision n; a stale revision is ERR_VAULT_CONFLICT with the current one, so two writers never both win")
fn putRow st: S step: (fn [S ty/Op] -> (Pair S ty/Reply)) c: String id: String expectRev: Int64 value: String now: Int64 -> (Pair S (Result Int64 String))
  (let [(r (step st (ty/opCas (key c id) expectRev value 0 now)))]
    (match (pairSecond r)
      ((ty/rWritten rev) (done (pairFirst r) rev))
      ((ty/rConflict cur) (fail (pairFirst r) (str "ERR_VAULT_CONFLICT: " c "/" id " is at revision " (stringFromInt64 cur))))
      (other (fail (pairFirst r) (storeErr other)))))

fn scanFrom st: S step: (fn [S ty/Op] -> (Pair S ty/Reply)) c: String after: String now: Int64 acc: (List ty/ScanRow) left: Int64 -> (Pair S (Result (List ty/ScanRow) String))
  (let [(r (step st (ty/opScan c "" after 1000 now)))]
    (match (pairSecond r)
      ((ty/rPage rows next)
        (if (or (stringEmpty? next) (<= left 0))
          (done (pairFirst r) (listAppend acc rows))
          (scanFrom (pairFirst r) step c next now (listAppend acc rows) (- left 1))))
      (other (fail (pairFirst r) (storeErr other)))))

fn scanAll st: S step: (fn [S ty/Op] -> (Pair S ty/Reply)) c: String now: Int64 -> (Pair S (Result (List ty/ScanRow) String))
  (scanFrom st step c "" now (list) 100000)

fn rowsOf rows: (List ty/ScanRow) f: (fn [String String] -> (Result A String)) -> (Result (List A) String)
  (cd/mapResult (fn [(r ty/ScanRow)] -> (Result A String)
    (match (f r.id r.value) ((ok a) (ok a)) ((err e) (err (str "ERR_VAULT_PARSE: " r.id ": " e))))) rows)

fn rawEntries st: S step: (fn [S ty/Op] -> (Pair S ty/Reply)) now: Int64 -> (Pair S (Result (List EntryRow) String))
  (bind (scanAll st step "entries" now) (fn [(s S) (rows (List ty/ScanRow))] -> (Pair S (Result (List EntryRow) String))
    (pair s (cd/mapResult (fn [(r ty/ScanRow)] -> (Result EntryRow String)
      (match (m/parseEntry r.value)
        ((ok e) (ok (EntryRow :rev r.rev :entry e)))
        ((err x) (err (str "ERR_VAULT_PARSE: entries/" r.id ": " x))))) rows))))

; (:m :ref VS-VAULT :do "a pending payload is the claim token that holds the reservation, the replaced entry's status before the commit, and the new entry's row, space separated; the token is - for a payload with no reservation (supersede, resolve)")
fn payloadParts e: m/Entry -> (List String)
  (stringSplit e.pending " ")

fn payloadOf e: m/Entry -> (Option m/Entry)
  (if (stringEmpty? e.pending)
    (none)
    (match (m/parseEntry (stringJoin (optionOr (listTail (optionOr (listTail (payloadParts e)) (list))) (list)) " ")) ((ok p) (some p)) ((err _) (none))))

fn payloadToken e: m/Entry -> String
  (optionOr (listHead (payloadParts e)) "")

fn payloadPrev e: m/Entry -> String
  (optionOr (listHead (optionOr (listTail (payloadParts e)) (list))) "")

; (:m :ref VS-VAULT :do "a payload is dead when its token is not - and no longer the one ids/<id> holds for the new id: another claim took the id, so the commit is void; readers show the replaced entry as it was before the commit and the sweep writes that back")
fn deadPayload? toks: (Map String String) e: m/Entry pe: m/Entry -> Bool
  (and (!= (payloadToken e) "-") (!= (payloadToken e) (optionOr (mapGet toks pe.entryId) "")))

fn rolledBack e: m/Entry -> m/Entry
  (with e :status (payloadPrev e) :supersededBy "" :validTo 0 :pending "")

fn viewDead toks: (Map String String) r: EntryRow -> EntryRow
  (match (payloadOf r.entry)
    ((some pe) (if (deadPayload? toks r.entry pe) (EntryRow :rev r.rev :entry (rolledBack r.entry)) r))
    ((none) r))

fn rowFor rows: (List EntryRow) id: String -> (Option EntryRow)
  (listFind (fn [(r EntryRow)] -> Bool (= r.entry.entryId id)) rows)

fn withRow rows: (List EntryRow) r: EntryRow -> (List EntryRow)
  (cons r (filter (fn [(x EntryRow)] -> Bool (!= x.entry.entryId r.entry.entryId)) rows))

fn viewStep rows: (List EntryRow) acc: (List EntryRow) r: EntryRow -> (List EntryRow)
  (match (payloadOf r.entry)
    ((none) acc)
    ((some pe)
      (match (rowFor acc pe.entryId)
        ((none) (cons (EntryRow :rev 0 :entry pe) acc))
        ((some x) (if (m/sameOrigin pe x.entry) acc (withRow acc (EntryRow :rev -1 :entry pe)))))))

; (:m :ref VS-VAULT :do "the one normalised view every reader uses: a row that carries a pending payload stands for its replacement too, so the replacement is read from the payload while its own row is absent (revision 0, a write creates it) and the payload wins over a row of another claim under the same id and carries revision -1, so a write to it is refused as an id collision; a dead payload is not applied and its row reads as before the commit; rows in id order")
fn viewRows raw: (List EntryRow) toks: (Map String String) -> (List EntryRow)
  (let [(live (map (fn [(r EntryRow)] -> EntryRow (viewDead toks r)) raw))]
  (listSortBy (fn [(r EntryRow)] -> String r.entry.entryId) (fold (fn [(acc (List EntryRow)) (r EntryRow)] -> (List EntryRow) (viewStep live acc r)) live live)))

fn tokenMap held: (List ty/ScanRow) -> (Map String String)
  (fold (fn [(m (Map String String)) (r ty/ScanRow)] -> (Map String String) (mapSet m r.id (pairFirst (reservationOf r.value)))) (mapEmpty) held)

; (:m :ref VS-VAULT :do "every entry with its revision in id order, as the normalised view; a row that does not parse is an error naming it")
fn loadEntries st: S step: (fn [S ty/Op] -> (Pair S ty/Reply)) now: Int64 -> (Pair S (Result (List EntryRow) String))
  (bind (rawEntries st step now) (fn [(s S) (rows (List EntryRow))] -> (Pair S (Result (List EntryRow) String))
    (bind (scanAll s step "ids" now) (fn [(s1 S) (held (List ty/ScanRow))] -> (Pair S (Result (List EntryRow) String))
      (done s1 (viewRows rows (tokenMap held)))))))

fn implicitEdge r: EntryRow -> (Option m/Edge)
  (match (payloadOf r.entry)
    ((some pe) (some (m/Edge :fromId pe.entryId :toId r.entry.entryId :relation "refines" :weightBp 9500)))
    ((none) (none)))

fn addImplicit edges: (List m/Edge) e: m/Edge -> (List m/Edge)
  (if (listAny? (fn [(x m/Edge)] -> Bool (and (= x.fromId e.fromId) (and (= x.toId e.toId) (= x.relation e.relation)))) edges) edges (listAppend edges (list e)))

; (:m :ref VS-VAULT :do "the stored edges plus the refines edge every pending payload implies, so a replacement whose edge was never written still reads as linked")
fn loadEdges st: S step: (fn [S ty/Op] -> (Pair S ty/Reply)) now: Int64 -> (Pair S (Result (List m/Edge) String))
  (bind (scanAll st step "edges" now) (fn [(s S) (rows (List ty/ScanRow))] -> (Pair S (Result (List m/Edge) String))
    (bind (rawEntries s step now) (fn [(s2 S) (es (List EntryRow))] -> (Pair S (Result (List m/Edge) String))
      (match (rowsOf rows (fn [(id String) (v String)] -> (Result m/Edge String) (m/parseEdge v)))
        ((err e) (fail s2 e))
        ((ok edges) (done s2 (fold addImplicit edges (listFlatMap (fn [(r EntryRow)] -> (List m/Edge) (match (implicitEdge r) ((some e) (list e)) ((none) (list)))) es)))))))))

fn loadResolutions st: S step: (fn [S ty/Op] -> (Pair S ty/Reply)) now: Int64 -> (Pair S (Result (List m/Resolution) String))
  (bind (scanAll st step "resolutions" now) (fn [(s S) (rows (List ty/ScanRow))] -> (Pair S (Result (List m/Resolution) String))
    (pair s (rowsOf rows (fn [(id String) (v String)] -> (Result m/Resolution String) (m/parseResolution v))))))

fn entriesOf rows: (List EntryRow) -> (List m/Entry)
  (map (fn [(r EntryRow)] -> m/Entry r.entry) rows)

fn revOf rows: (List EntryRow) id: String -> Int64
  (match (listFind (fn [(r EntryRow)] -> Bool (= r.entry.entryId id)) rows) ((some r) r.rev) ((none) 0))

fn getEntry st: S step: (fn [S ty/Op] -> (Pair S ty/Reply)) now: Int64 id: String -> (Pair S (Result (Option m/Entry) String))
  (bind (loadEntries st step now) (fn [(s S) (rows (List EntryRow))] -> (Pair S (Result (Option m/Entry) String))
    (done s (match (rowFor rows id) ((some r) (some r.entry)) ((none) (none))))))

fn getUnit st: S step: (fn [S ty/Op] -> (Pair S ty/Reply)) now: Int64 hash: String -> (Pair S (Result (Option un/ProvUnit) String))
  (bind (getRow st step "units" hash now) (fn [(s S) (row (Option (Pair Int64 String)))] -> (Pair S (Result (Option un/ProvUnit) String))
    (match row
      ((none) (done s (none)))
      ((some p) (match (un/parseUnit (pairSecond p)) ((ok u) (done s (some u))) ((err x) (fail s (str "ERR_VAULT_PARSE: units/" hash ": " x))))))))

fn getBody st: S step: (fn [S ty/Op] -> (Pair S ty/Reply)) now: Int64 hash: String -> (Pair S (Result (Option String) String))
  (bind (getRow st step "bodies" hash now) (fn [(s S) (row (Option (Pair Int64 String)))] -> (Pair S (Result (Option String) String))
    (done s (optionMap pairSecond row))))

; (:m :ref VS-VAULT :do "a content-addressed row is written once; finding it there already is success because equal keys have equal bytes")
fn putOnce st: S step: (fn [S ty/Op] -> (Pair S ty/Reply)) c: String id: String value: String now: Int64 -> (Pair S (Result Bool String))
  (let [(r (step st (ty/opCas (key c id) 0 value 0 now)))]
    (match (pairSecond r)
      ((ty/rWritten _) (done (pairFirst r) true))
      ((ty/rConflict _) (done (pairFirst r) false))
      (other (fail (pairFirst r) (storeErr other)))))

fn validScope? sc: (Map String String) -> Bool
  (listAll? (fn [(k String)] -> Bool (and (cd/validId? k) (and (not (stringEmpty? (stringTrim (optionOr (mapGet sc k) "")))) (<= (stringLength (optionOr (mapGet sc k) "")) 120)))) (mapKeys sc))

; (:m :ref VS-VAULT :do "an ingest spec is refused for a bad id, kind, layer, role, scope, status or provenance, for a derived entry without sha256 source hashes, an empty title or body, ttlDays under 1, basis points outside 0..10000, or a nonpositive now")
fn validateSpec spec: IngestSpec now: Int64 -> (Option String)
  (cd/firstFailure
    (list (cd/check (cd/validId? spec.entryId) (str "ERR_VAULT_ARG: invalid entryId: " spec.entryId))
          (cd/check (cd/validId? spec.kind) (str "ERR_VAULT_ARG: invalid kind: " spec.kind))
          (cd/check (cd/validId? spec.layer) (str "ERR_VAULT_ARG: invalid layer: " spec.layer))
          (cd/check (cd/validId? spec.role) (str "ERR_VAULT_ARG: invalid role: " spec.role))
          (cd/check (validScope? spec.scope) "ERR_VAULT_ARG: scope keys are ids and values 1 to 120 characters")
          (cd/check (m/validStatus? spec.status) (str "ERR_VAULT_ARG: invalid status: " spec.status))
          (cd/check (not (= spec.status "superseded")) "ERR_VAULT_ARG: a new entry cannot start superseded")
          (cd/check (m/validProvenance? spec.provenance) (str "ERR_VAULT_ARG: invalid provenance: " spec.provenance))
          (cd/check (or (!= spec.provenance "derived") (not (listEmpty? (cd/dedupStrings spec.sourceHashes)))) "ERR_VAULT_PROVENANCE: derived entry requires at least one sourceHash")
          (cd/check (listAll? un/hexHash? spec.sourceHashes) "ERR_VAULT_PROVENANCE: sourceHashes must be sha256 hex")
          (cd/check (not (stringEmpty? (stringTrim spec.title))) "ERR_VAULT_ARG: title must not be empty")
          (cd/check (not (stringEmpty? (stringTrim spec.bodyText))) "ERR_VAULT_ARG: bodyText must not be empty")
          (cd/check (>= spec.ttlDays 1) "ERR_VAULT_ARG: ttlDays must be >= 1")
          (cd/check (and (>= spec.confidenceBp 0) (<= spec.confidenceBp 10000)) "ERR_VAULT_ARG: confidenceBp must be 0..10000")
          (cd/check (and (>= spec.priorityBp 0) (<= spec.priorityBp 10000)) "ERR_VAULT_ARG: priorityBp must be 0..10000")
          (cd/check (>= spec.validFrom 0) "ERR_VAULT_ARG: validFrom must not be negative")
          (cd/check (> now 0) "ERR_VAULT_ARG: now must be positive epoch ms")))

fn sourceOf spec: IngestSpec -> String
  (if (stringEmpty? (stringTrim spec.source)) (str "vault:" spec.kind "/" spec.entryId) (stringTrim spec.source))

fn licenceOf spec: IngestSpec -> String
  (if (stringEmpty? (stringTrim spec.licence)) "owner-notes" (stringTrim spec.licence))

fn unitOfSpec spec: IngestSpec now: Int64 replacesHash: String passages: (List un/Passage) -> un/ProvUnit
  (un/sealUnit (un/ProvUnit :kind spec.kind :source (sourceOf spec)
                            :title (stringTrim spec.title) :observedAt now :retrievedAt now
                            :licence (licenceOf spec)
                            :reviewBy (+ now (* spec.ttlDays 86400000)) :confidenceBp spec.confidenceBp :replaces replacesHash :contentHash ""
                            :ext (list (pair "layer" spec.layer) (pair "provenance" spec.provenance)) :passages passages))

fn entryOfSpec spec: IngestSpec unitHash: String bodyHash: String now: Int64 -> m/Entry
  (m/Entry :entryId spec.entryId :unitHash unitHash :bodyHash bodyHash :layer spec.layer :role spec.role :scope spec.scope :status spec.status
           :supersededBy "" :pending "" :provenance spec.provenance :sourceHashes (cd/dedupStrings spec.sourceHashes) :title (stringTrim spec.title)
           :summary (if (stringEmpty? (stringTrim spec.summary)) (stringTrim spec.title) (stringTrim spec.summary)) :tags (cd/dedupStrings spec.tags)
           :priorityBp spec.priorityBp :validFrom (if (= spec.validFrom 0) now spec.validFrom) :validTo 0 :recordedAt now :updatedAt now)

fn writeEntry st: S step: (fn [S ty/Op] -> (Pair S ty/Reply)) rev: Int64 e: m/Entry now: Int64 -> (Pair S (Result Int64 String))
  (if (< rev 0)
    (fail st (str "ERR_VAULT_ID_COLLISION: entries/" e.entryId " holds another claim, it is not written"))
    (putRow st step "entries" e.entryId rev (m/emitEntry e) now))

fn writeEdge st: S step: (fn [S ty/Op] -> (Pair S ty/Reply)) e: m/Edge now: Int64 -> (Pair S (Result Int64 String))
  (let [(id (m/edgeKey e.fromId e.relation e.toId))]
    (bind (getRow st step "edges" id now) (fn [(s S) (row (Option (Pair Int64 String)))] -> (Pair S (Result Int64 String))
      (putRow s step "edges" id (match row ((some p) (pairFirst p)) ((none) 0)) (m/emitEdge e) now))))

fn sealPending e: m/Entry token: String prev: String pe: m/Entry -> m/Entry
  (with e :pending (str token " " prev " " (m/emitEntry pe)))

; (:m :ref VS-VAULT :do "a replacement commits at one point: the CAS on the replaced entry's row, which stores the new supersededBy and the whole row of the new entry as its pending payload; once it passes the replacement has happened for every reader, and storing the new row and the refines edge is an idempotent completion anyone may run. Two writers replacing one entry are serialised by that CAS, the loser gets ERR_VAULT_SUPERSEDED. The unit and the body are content addressed and written before the commit, so a loser leaves at most unreferenced content rows")
fn ingest st: S step: (fn [S ty/Op] -> (Pair S ty/Reply)) now: Int64 spec: IngestSpec -> (Pair S (Result IngestResult String))
  (ingestTry st step now spec 3)

; (:m :ref VS-VAULT :do "the reservation token of an ingest: a hash of the claim derived from the spec (entry fields without clock, the id it replaces, the unit's kind, source and licence); the same spec always has the same token, whatever time it is retried at")
fn tokenOf spec: IngestSpec -> String
  (un/sha256Hex (str (m/emitEntry (entryOfSpec spec "" (un/sha256Hex spec.bodyText) 0)) "|" spec.replacesEntryId "|" spec.kind "|" (sourceOf spec) "|" (licenceOf spec)))

fn tokenRow st: S step: (fn [S ty/Op] -> (Pair S ty/Reply)) now: Int64 id: String -> (Pair S (Result (Option (Pair Int64 String)) String))
  (getRow st step "ids" id now)

; (:m :ref VS-VAULT :do "how long a reservation of an id that no entry or payload names blocks other claims, in ms (adopted 2026-11-22, no measurement: long enough for one ingest to finish, short enough that a crashed writer does not close an id for good)")
fn reservationTtlMs -> Int64
  3600000

; (:m :ref VS-VAULT :do "an ids row holds the claim token, a space and the time it was reserved")
fn reservationOf v: String -> (Pair String Int64)
  (let [(parts (stringSplit v " "))]
    (pair (optionOr (listHead parts) "")
          (match (listHead (optionOr (listTail parts) (list))) ((some t) (optionOr (stringToInt64 t) 0)) ((none) 0))))

fn reservationValue spec: IngestSpec now: Int64 -> String
  (str (tokenOf spec) " " (stringFromInt64 now))

fn stale? held: (Pair String Int64) now: Int64 -> Bool
  (< (+ (pairSecond held) (reservationTtlMs)) now)

; (:m :ref VS-VAULT :do "the id is taken first, by a CAS on ids/<id> holding token and time, for plain and replacing ingests alike: the same token is the same claim (a resume); another token is ERR_VAULT_EXISTS and nothing else is written, except that a reservation older than the TTL which no entry or payload names is taken over by CAS; a failed ingest keeps its reservation, only the TTL frees it")
fn reserve st: S step: (fn [S ty/Op] -> (Pair S ty/Reply)) now: Int64 spec: IngestSpec exists: Bool tries: Int64 -> (Pair S (Result Int64 String))
  (bind (tokenRow st step now spec.entryId) (fn [(s S) (row (Option (Pair Int64 String)))] -> (Pair S (Result Int64 String))
    (match row
      ((none)
        (if exists
          (fail s (str "ERR_VAULT_EXISTS: " spec.entryId " exists without a reservation"))
          (let [(w (putRow s step "ids" spec.entryId 0 (reservationValue spec now) now))]
            (match (pairSecond w)
              ((ok rv) (done (pairFirst w) rv))
              ((err e) (if (and (> tries 0) (stringContains? e "ERR_VAULT_CONFLICT"))
                         (reserve (pairFirst w) step now spec exists (- tries 1))
                         (fail (pairFirst w) e)))))))
      ((some p)
        (let [(held (reservationOf (pairSecond p)))]
          (cond
            ((= (pairFirst held) (tokenOf spec)) (done s (pairFirst p)))
            ((and (not exists) (stale? held now))
              (let [(w (putRow s step "ids" spec.entryId (pairFirst p) (reservationValue spec now) now))]
                (match (pairSecond w)
                  ((ok rv) (done (pairFirst w) rv))
                  ((err e) (if (stringContains? e "ERR_VAULT_CONFLICT")
                             (fail (pairFirst w) (str "ERR_VAULT_EXISTS: " spec.entryId " was taken over by another claim"))
                             (fail (pairFirst w) e))))))
            (else (fail s (str "ERR_VAULT_EXISTS: " spec.entryId " is reserved by another claim")))))))))

; (:m :ref VS-VAULT :do "the last check before a claim is written (the plain create or the commit CAS on the replaced row): ids/<id> must still hold this spec's token at the revision this attempt took; a writer that was stalled past the TTL and lost its reservation gets ERR_VAULT_EXISTS and writes nothing")
fn guardedWrite st: S step: (fn [S ty/Op] -> (Pair S ty/Reply)) now: Int64 spec: IngestSpec held: Int64 rev: Int64 e: m/Entry -> (Pair S (Result Int64 String))
  (bind (tokenRow st step now spec.entryId) (fn [(s S) (row (Option (Pair Int64 String)))] -> (Pair S (Result Int64 String))
    (match row
      ((some p)
        (if (and (= (pairFirst p) held) (= (pairFirst (reservationOf (pairSecond p))) (tokenOf spec)))
          (writeEntry s step rev e now)
          (fail s (str "ERR_VAULT_EXISTS: " spec.entryId " is no longer reserved by this claim"))))
      ((none) (fail s (str "ERR_VAULT_EXISTS: " spec.entryId " reservation is gone"))))))

fn ingestTry st: S step: (fn [S ty/Op] -> (Pair S ty/Reply)) now: Int64 spec: IngestSpec tries: Int64 -> (Pair S (Result IngestResult String))
  (match (validateSpec spec now)
    ((some why) (fail st why))
    ((none)
      (bind (loadEntries st step now) (fn [(s0 S) (rows (List EntryRow))] -> (Pair S (Result IngestResult String))
        (let [(existing (rowFor rows spec.entryId))
              (old (if (stringEmpty? spec.replacesEntryId) (none) (rowFor rows spec.replacesEntryId)))]
          (if (and (not (stringEmpty? spec.replacesEntryId)) (none? old))
            (fail s0 (str "ERR_VAULT_NOTFOUND: replacesEntryId not found: " spec.replacesEntryId))
            (bind (reserve s0 step now spec (some? existing) 2) (fn [(s1 S) (held Int64)] -> (Pair S (Result IngestResult String))
              (if (none? old)
                (ingestPlain s1 step now spec existing held)
                (ingestReplace s1 step now spec old existing held tries))))))))))

fn ingestPlain st: S step: (fn [S ty/Op] -> (Pair S ty/Reply)) now: Int64 spec: IngestSpec existing: (Option EntryRow) held: Int64 -> (Pair S (Result IngestResult String))
  (match existing
    ((some e) (done st (IngestResult :entry e.entry :unitHash e.entry.unitHash :passageCount (listLength (un/splitPassages spec.bodyText)))))
    ((none)
      (let [(passages (un/splitPassages spec.bodyText))
            (unit (unitOfSpec spec now "" passages))
            (bodyHash (un/sha256Hex spec.bodyText))
            (entry (entryOfSpec spec unit.contentHash bodyHash now))]
        (match (un/validateUnit unit)
          ((err e) (fail st e))
          ((ok u)
            (bind (putOnce st step "units" u.contentHash (un/emitUnit u) now) (fn [(s1 S) (_ Bool)] -> (Pair S (Result IngestResult String))
            (bind (putOnce s1 step "bodies" bodyHash spec.bodyText now) (fn [(s2 S) (_ Bool)] -> (Pair S (Result IngestResult String))
            (bind (guardedWrite s2 step now spec held 0 entry) (fn [(s3 S) (_ Int64)] -> (Pair S (Result IngestResult String))
              (done s3 (IngestResult :entry entry :unitHash u.contentHash :passageCount (listLength passages))))))))))))))

fn ingestReplace st: S step: (fn [S ty/Op] -> (Pair S ty/Reply)) now: Int64 spec: IngestSpec old: (Option EntryRow) existing: (Option EntryRow) held: Int64 tries: Int64 -> (Pair S (Result IngestResult String))
  (match old
    ((none) (fail st "ERR_VAULT_NOTFOUND: replacesEntryId"))
    ((some o)
      (match existing
        ((some e)
          (if (and (= o.entry.status "superseded") (= o.entry.supersededBy spec.entryId))
            (bind (completeOne st step now e.entry o.entry.entryId) (fn [(s S) (_ Bool)] -> (Pair S (Result IngestResult String))
              (done s (IngestResult :entry e.entry :unitHash e.entry.unitHash :passageCount (listLength (un/splitPassages spec.bodyText))))))
            (fail st (str "ERR_VAULT_EXISTS: " spec.entryId))))
        ((none)
          (if (= o.entry.status "superseded")
            (fail st (str "ERR_VAULT_SUPERSEDED: " spec.replacesEntryId " is already superseded by " o.entry.supersededBy))
            (replaceCommit st step now spec o held tries))))))

fn replaceCommit st: S step: (fn [S ty/Op] -> (Pair S ty/Reply)) now: Int64 spec: IngestSpec o: EntryRow held: Int64 tries: Int64 -> (Pair S (Result IngestResult String))
  (let [(passages (un/splitPassages spec.bodyText))
        (unit (unitOfSpec spec now o.entry.unitHash passages))
        (bodyHash (un/sha256Hex spec.bodyText))
        (entry (entryOfSpec spec unit.contentHash bodyHash now))]
    (match (un/validateUnit unit)
      ((err e) (fail st e))
      ((ok u)
        (bind (putOnce st step "units" u.contentHash (un/emitUnit u) now) (fn [(s1 S) (_ Bool)] -> (Pair S (Result IngestResult String))
        (bind (putOnce s1 step "bodies" bodyHash spec.bodyText now) (fn [(s2 S) (_ Bool)] -> (Pair S (Result IngestResult String))
          (let [(w (guardedWrite s2 step now spec held o.rev (sealPending (cu/supersededEntry o.entry spec.entryId now) (tokenOf spec) o.entry.status entry)))]
            (match (pairSecond w)
              ((err e) (if (and (> tries 0) (stringContains? e "ERR_VAULT_CONFLICT"))
                         (ingestRetry (pairFirst w) step now spec (- tries 1))
                         (fail (pairFirst w) e)))
              ((ok _)
                (bind (completeOne (pairFirst w) step now entry o.entry.entryId) (fn [(s3 S) (_ Bool)] -> (Pair S (Result IngestResult String))
                  (done s3 (IngestResult :entry entry :unitHash u.contentHash :passageCount (listLength passages)))))))))))))))

fn ingestRetry st: S step: (fn [S ty/Op] -> (Pair S ty/Reply)) now: Int64 spec: IngestSpec tries: Int64 -> (Pair S (Result IngestResult String))
  (ingestTry st step now spec tries)

; (:m :ref VS-VAULT :do "the completion of a committed replacement, idempotent and open to anyone: create the new row if absent (a row of another claim under that id is ERR_VAULT_ID_COLLISION, recorded under conflicts/<id>), write the refines edge, then clear the payload from the replaced row")
fn materializeEntry st: S step: (fn [S ty/Op] -> (Pair S ty/Reply)) now: Int64 pe: m/Entry tries: Int64 -> (Pair S (Result Bool String))
  (bind (getRow st step "entries" pe.entryId now) (fn [(s S) (row (Option (Pair Int64 String)))] -> (Pair S (Result Bool String))
    (match row
      ((none)
        (let [(w (putRow s step "entries" pe.entryId 0 (m/emitEntry pe) now))]
          (match (pairSecond w)
            ((ok _) (done (pairFirst w) true))
            ((err e) (if (and (> tries 0) (stringContains? e "ERR_VAULT_CONFLICT"))
                       (materializeEntry (pairFirst w) step now pe (- tries 1))
                       (fail (pairFirst w) e))))))
      ((some p)
        (match (m/parseEntry (pairSecond p))
          ((err x) (fail s (str "ERR_VAULT_PARSE: entries/" pe.entryId ": " x)))
          ((ok e)
            (if (m/sameOrigin pe e)
              (done s true)
              (let [(c (putRow s step "conflicts" pe.entryId 0 (pairSecond p) now))]
                (fail (pairFirst c) (str "ERR_VAULT_ID_COLLISION: entries/" pe.entryId " holds another claim than the committed replacement of " pe.entryId))))))))))

fn unpend e: m/Entry -> m/Entry
  (with e :pending "")

; (:m :ref VS-VAULT :do "the payload is cleared from the replaced row by CAS once the new row and the edge are stored; a row that has no payload, or one for another id, is left alone, a stale revision re-reads once")
fn clearPending st: S step: (fn [S ty/Op] -> (Pair S ty/Reply)) now: Int64 oldId: String newId: String tries: Int64 -> (Pair S (Result Bool String))
  (bind (getRow st step "entries" oldId now) (fn [(s S) (row (Option (Pair Int64 String)))] -> (Pair S (Result Bool String))
    (match row
      ((none) (done s true))
      ((some p)
        (match (m/parseEntry (pairSecond p))
          ((err x) (fail s (str "ERR_VAULT_PARSE: entries/" oldId ": " x)))
          ((ok e)
            (match (payloadOf e)
              ((none) (done s true))
              ((some pe)
                (if (!= pe.entryId newId)
                  (done s true)
                  (let [(w (writeEntry s step (pairFirst p) (unpend e) now))]
                    (match (pairSecond w)
                      ((ok _) (done (pairFirst w) true))
                      ((err x) (if (and (> tries 0) (stringContains? x "ERR_VAULT_CONFLICT"))
                                 (clearPending (pairFirst w) step now oldId newId (- tries 1))
                                 (fail (pairFirst w) x))))))))))))))

fn completeOne st: S step: (fn [S ty/Op] -> (Pair S ty/Reply)) now: Int64 pe: m/Entry oldId: String -> (Pair S (Result Bool String))
  (bind (materializeEntry st step now pe 3) (fn [(s S) (_ Bool)] -> (Pair S (Result Bool String))
    (bind (writeEdge s step (m/Edge :fromId pe.entryId :toId oldId :relation "refines" :weightBp 9500) now) (fn [(s2 S) (_ Int64)] -> (Pair S (Result Bool String))
      (clearPending s2 step now oldId pe.entryId 2)))))

; (:m :ref VS-VAULT :do "an undone commit: the replaced row is written back as it was before the commit, with the payload cleared")
fn rollbackRow st: S step: (fn [S ty/Op] -> (Pair S ty/Reply)) now: Int64 r: EntryRow -> (Pair S (Result Bool String))
  (bind (writeEntry st step r.rev (rolledBack r.entry) now) (fn [(s S) (_ Int64)] -> (Pair S (Result Bool String)) (done s true)))

; (:m :ref VS-VAULT :do "one row at a time: a live payload is completed, a dead one rolled back; a failing row is collected and the next row still runs, so one bad row never blocks the sweep")
fn completeRows st: S step: (fn [S ty/Op] -> (Pair S ty/Reply)) now: Int64 toks: (Map String String) rows: (List EntryRow) n: Int64 errs: (List String) -> (Pair S (Result (Pair Int64 (List String)) String))
  (match (listHead rows)
    ((none) (done st (pair n errs)))
    ((some r)
      (let [(rest (optionOr (listTail rows) (list)))]
        (match (payloadOf r.entry)
          ((none) (completeRows st step now toks rest n errs))
          ((some pe)
            (let [(w (if (deadPayload? toks r.entry pe) (rollbackRow st step now r) (completeOne st step now pe r.entry.entryId)))]
              (match (pairSecond w)
                ((ok _) (completeRows (pairFirst w) step now toks rest (+ n 1) errs))
                ((err e) (completeRows (pairFirst w) step now toks rest n (cons e errs))))))))))

fn finishResolutions st: S step: (fn [S ty/Op] -> (Pair S ty/Reply)) now: Int64 rs: (List m/Resolution) n: Int64 -> (Pair S (Result Int64 String))
  (match (listHead rs)
    ((none) (done st n))
    ((some r)
      (let [(rest (optionOr (listTail rs) (list)))]
        (if (= r.state "done")
          (finishResolutions st step now rest n)
          (bind (loadEntries st step now) (fn [(s S) (rows (List EntryRow))] -> (Pair S (Result Int64 String))
            (if (resumeResolve rows rs r)
              (bind (resolveWrite s step now r rows) (fn [(s1 S) (_ Bool)] -> (Pair S (Result Int64 String))
                (finishResolutions s1 step now rest (+ n 1))))
              (finishResolutions s step now rest n))))))))

fn sweepIds st: S step: (fn [S ty/Op] -> (Pair S ty/Reply)) now: Int64 rows: (List EntryRow) held: (List ty/ScanRow) -> (Pair S (Result Bool String))
  (match (listHead held)
    ((none) (done st true))
    ((some r)
      (let [(rest (optionOr (listTail held) (list)))]
        (if (and (stale? (reservationOf r.value) now) (none? (rowFor rows r.id)))
          (let [(d (step st (ty/opDel (key "ids" r.id) r.rev now)))]
            (match (pairSecond d)
              ((ty/rErr _ _) (fail (pairFirst d) (storeErr (pairSecond d))))
              (_ (sweepIds (pairFirst d) step now rows rest))))
          (sweepIds st step now rows rest)))))

; (:m :ref VS-VAULT :do "the sweep: finishes every committed replacement whose row, edge or payload clearing is missing, rolls back the commits whose payload is dead, finishes pending resolutions and deletes reservations older than the TTL that no entry or payload names; it answers how many payloads and resolutions it finished, an error row is reported at the end after every other row ran, and once everything is complete it answers 0 and writes nothing")
fn completePending st: S step: (fn [S ty/Op] -> (Pair S ty/Reply)) now: Int64 -> (Pair S (Result Int64 String))
  (bind (rawEntries st step now) (fn [(s S) (rows (List EntryRow))] -> (Pair S (Result Int64 String))
    (bind (scanAll s step "ids" now) (fn [(s0 S) (held0 (List ty/ScanRow))] -> (Pair S (Result Int64 String))
    (bind (completeRows s0 step now (tokenMap held0) rows 0 (list)) (fn [(s1 S) (ne (Pair Int64 (List String)))] -> (Pair S (Result Int64 String))
      (bind (loadResolutions s1 step now) (fn [(sr S) (rs (List m/Resolution))] -> (Pair S (Result Int64 String))
      (bind (finishResolutions sr step now rs 0) (fn [(sf S) (nr Int64)] -> (Pair S (Result Int64 String))
      (bind (loadEntries sf step now) (fn [(s2 S) (view (List EntryRow))] -> (Pair S (Result Int64 String))
        (bind (scanAll s2 step "ids" now) (fn [(s3 S) (held (List ty/ScanRow))] -> (Pair S (Result Int64 String))
          (bind (sweepIds s3 step now view held) (fn [(s4 S) (_ Bool)] -> (Pair S (Result Int64 String))
            (if (= (listLength (pairSecond ne)) 0)
              (done s4 (+ (pairFirst ne) nr))
              (fail s4 (stringJoin (pairSecond ne) "; ")))))))))))))))))))

fn changedRows before: (List EntryRow) after: (List m/Entry) -> (List EntryRow)
  (filter (fn [(r EntryRow)] -> Bool
            (match (cu/findEntry after r.entry.entryId)
              ((some e) (!= (m/emitEntry e) (m/emitEntry r.entry)))
              ((none) false)))
          before)

fn writeChanged st: S step: (fn [S ty/Op] -> (Pair S ty/Reply)) before: (List EntryRow) after: (List m/Entry) now: Int64 -> (Pair S (Result Int64 String))
  (writeAll st step (changedRows before after) after now 0)

fn writeAll st: S step: (fn [S ty/Op] -> (Pair S ty/Reply)) rows: (List EntryRow) after: (List m/Entry) now: Int64 n: Int64 -> (Pair S (Result Int64 String))
  (match (listHead rows)
    ((none) (done st n))
    ((some r)
      (match (cu/findEntry after r.entry.entryId)
        ((none) (writeAll st step (optionOr (listTail rows) (list)) after now n))
        ((some e) (bind (writeEntry st step r.rev e now) (fn [(s S) (_ Int64)] -> (Pair S (Result Int64 String))
          (writeAll s step (optionOr (listTail rows) (list)) after now (+ n 1))))))))

; (:m :ref VS-VAULT :do "a link needs a valid edge and two stored entries; a contradicts link marks both live ends disputed unless pinned, and linking the same triple again replaces its weight")
fn linkEntries st: S step: (fn [S ty/Op] -> (Pair S ty/Reply)) now: Int64 fromId: String toId: String relation: String weightBp: Int64 -> (Pair S (Result Bool String))
  (let [(edge (m/Edge :fromId fromId :toId toId :relation relation :weightBp weightBp))]
    (match (g/edgeProblem edge)
      ((some why) (fail st (str "ERR_VAULT_EDGE: " why)))
      ((none)
        (bind (loadEntries st step now) (fn [(s0 S) (rows (List EntryRow))] -> (Pair S (Result Bool String))
          (let [(es (entriesOf rows))]
            (cond
              ((none? (cu/findEntry es fromId)) (fail s0 (str "ERR_VAULT_NOTFOUND: fromId " fromId)))
              ((none? (cu/findEntry es toId)) (fail s0 (str "ERR_VAULT_NOTFOUND: toId " toId)))
              (else
                (bind (writeEdge s0 step edge now) (fn [(s1 S) (_ Int64)] -> (Pair S (Result Bool String))
                  (if (= relation "contradicts")
                    (bind (writeChanged s1 step rows (cu/linkMarks es fromId toId now) now) (fn [(s2 S) (_ Int64)] -> (Pair S (Result Bool String)) (done s2 true)))
                    (done s1 true))))))))))))

; (:m :ref VS-VAULT :do "a status is set on a stored entry; superseded is refused here because only supersedeEntry and resolveContradiction record what replaced it")
fn setEntryStatus st: S step: (fn [S ty/Op] -> (Pair S ty/Reply)) now: Int64 id: String status: String -> (Pair S (Result m/Entry String))
  (cond
    ((not (m/validStatus? status)) (fail st (str "ERR_VAULT_ARG: invalid status " status)))
    ((= status "superseded") (fail st "ERR_VAULT_ARG: use supersedeEntry to supersede"))
    (else
      (bind (loadEntries st step now) (fn [(s S) (rows (List EntryRow))] -> (Pair S (Result m/Entry String))
        (match (rowFor rows id)
          ((none) (fail s (str "ERR_VAULT_NOTFOUND: " id)))
          ((some r)
            (let [(next (cu/setStatus r.entry status now))]
              (bind (writeEntry s step r.rev next now) (fn [(s2 S) (_ Int64)] -> (Pair S (Result m/Entry String)) (done s2 next))))))))))

; (:m :ref VS-VAULT :do "old becomes superseded by new, stops being valid now, and new gets a refines edge to old; refused for a superseded old, a cycle and the other cases of supersedeProblem, with nothing written")
fn supersedeEntry st: S step: (fn [S ty/Op] -> (Pair S ty/Reply)) now: Int64 old: String new: String -> (Pair S (Result Bool String))
  (bind (loadEntries st step now) (fn [(s0 S) (rows (List EntryRow))] -> (Pair S (Result Bool String))
    (match (cu/supersedeProblem (entriesOf rows) old new)
      ((some why) (fail s0 why))
      ((none)
        (match (rowFor rows old)
          ((none) (fail s0 (str "ERR_VAULT_NOTFOUND: " old)))
          ((some o)
            (match (rowFor rows new)
              ((none) (fail s0 (str "ERR_VAULT_NOTFOUND: " new)))
              ((some n)
                (bind (writeEntry s0 step o.rev (sealPending (cu/supersededEntry o.entry new now) "-" o.entry.status n.entry) now) (fn [(s1 S) (_ Int64)] -> (Pair S (Result Bool String))
                (bind (completeOne s1 step now n.entry old) (fn [(s2 S) (_ Bool)] -> (Pair S (Result Bool String))
                  (done s2 true)))))))))))))

fn hasContradiction? edges: (List m/Edge) a: String b: String -> Bool
  (listAny? (fn [(e m/Edge)] -> Bool (g/contradictsPair? e a b)) edges)

; (:m :ref VS-VAULT :do "a resolution needs an existing contradicts edge between the two ids and one of the four outcomes; it is stored under its own id (reusing an id replaces it) and applies the outcome to both entries")
fn resolveContradiction st: S step: (fn [S ty/Op] -> (Pair S ty/Reply)) now: Int64 resolutionId: String a: String b: String outcome: String note: String -> (Pair S (Result Bool String))
  (cond
    ((not (cd/validId? resolutionId)) (fail st (str "ERR_VAULT_ARG: invalid resolutionId " resolutionId)))
    ((not (m/validOutcome? outcome)) (fail st (str "ERR_VAULT_ARG: invalid outcome " outcome)))
    (else
      (bind (loadEdges st step now) (fn [(s0 S) (edges (List m/Edge))] -> (Pair S (Result Bool String))
        (if (not (hasContradiction? edges a b))
          (fail s0 (str "ERR_VAULT_NO_CONTRADICTION: no contradicts edge between " a " and " b))
          (bind (loadEntries s0 step now) (fn [(s1 S) (rows (List EntryRow))] -> (Pair S (Result Bool String))
            (bind (loadResolutions s1 step now) (fn [(s2 S) (rs (List m/Resolution))] -> (Pair S (Result Bool String))
              (let [(r (m/Resolution :resolutionId resolutionId :entryA a :entryB b :outcome outcome :note (stringTrim note) :resolvedAt now :state "pending"))]
                (if (resumeResolve rows rs r)
                  (resolveWrite s2 step now r rows)
                  (match (resolveProblem (entriesOf rows) a b outcome)
                    ((some why) (fail s2 why))
                    ((none) (resolveWrite s2 step now r rows))))))))))))))

; (:m :ref VS-VAULT :do "a resolution needs both entries active; acceptA and acceptB also run supersedeProblem on the loser and the winner, so a resolution can never revive a superseded entry or close a supersede cycle; refused before anything is written")
; (:m :ref VS-VAULT :do "a repeated resolve resumes only when the loser is superseded by this winner, the winner is alive, and the loser still carries the winner as payload or a stored resolution of that id names this very pair and outcome; anything else gets the full active checks")
fn resumeResolve rows: (List EntryRow) rs: (List m/Resolution) r: m/Resolution -> Bool
  (let [(loserId (loserOf r.entryA r.entryB r.outcome))
        (winnerId (winnerOf r.entryA r.entryB r.outcome))]
    (match (rowFor rows loserId)
      ((none) false)
      ((some l)
        (match (rowFor rows winnerId)
          ((none) false)
          ((some w)
            (and (m/entryActive? w.entry)
              (and (and (= l.entry.status "superseded") (= l.entry.supersededBy winnerId))
                (or (match (payloadOf l.entry) ((some p) (= p.entryId winnerId)) ((none) false))
                    (some? (listFind (fn [(x m/Resolution)] -> Bool (and (= x.resolutionId r.resolutionId) (and (= x.entryA r.entryA) (and (= x.entryB r.entryB) (= x.outcome r.outcome))))) rs))))))))))

fn resolveProblem es: (List m/Entry) a: String b: String outcome: String -> (Option String)
  (cond
    ((not (cu/bothActive? es a b)) (some (str "ERR_VAULT_INACTIVE: " a " and " b " must both be active to resolve")))
    ((= outcome "acceptA") (cu/supersedeProblem es b a))
    ((= outcome "acceptB") (cu/supersedeProblem es a b))
    (else (none)))

fn loserOf a: String b: String outcome: String -> String
  (cond ((= outcome "acceptA") b) ((= outcome "acceptB") a) (else ""))

fn winnerOf a: String b: String outcome: String -> String
  (cond ((= outcome "acceptA") a) ((= outcome "acceptB") b) (else ""))

fn prevStatusOf es: (List m/Entry) id: String -> String
  (match (cu/findEntry es id) ((some e) e.status) ((none) ""))

fn withLoserPayload es: (List m/Entry) after: (List m/Entry) loserId: String winnerId: String -> (List m/Entry)
  (match (cu/findEntry es winnerId)
    ((some w) (map (fn [(e m/Entry)] -> m/Entry (if (= e.entryId loserId) (sealPending e "-" (prevStatusOf es loserId) w) e)) after))
    ((none) after))

fn rowsWhere rows: (List EntryRow) id: String same: Bool -> (List EntryRow)
  (filter (fn [(r EntryRow)] -> Bool (= same (= r.entry.entryId id))) rows)

fn completeWinner st: S step: (fn [S ty/Op] -> (Pair S ty/Reply)) now: Int64 es: (List m/Entry) winnerId: String loserId: String -> (Pair S (Result Bool String))
  (match (cu/findEntry es winnerId)
    ((some w) (completeOne st step now w loserId))
    ((none) (done st true)))

fn doneOf x: m/Resolution -> m/Resolution
  (with x :state "done")

fn sameResolve? x: m/Resolution r: m/Resolution -> Bool
  (and (= x.entryA r.entryA) (and (= x.entryB r.entryB) (= x.outcome r.outcome)))

; (:m :ref VS-VAULT :do "the resolution row is taken first, in state pending (nothing reads it as closing), so an outcome that is applied can never be left without its row; a row of the same pair and outcome is continued whatever its state, a row of another resolve under the id is replaced as before")
fn beginResolution st: S step: (fn [S ty/Op] -> (Pair S ty/Reply)) now: Int64 r: m/Resolution -> (Pair S (Result Bool String))
  (bind (getRow st step "resolutions" r.resolutionId now) (fn [(s S) (row (Option (Pair Int64 String)))] -> (Pair S (Result Bool String))
    (match row
      ((none) (bind (putRow s step "resolutions" r.resolutionId 0 (m/emitResolution r) now) (fn [(s1 S) (_ Int64)] -> (Pair S (Result Bool String)) (done s1 true))))
      ((some p)
        (match (m/parseResolution (pairSecond p))
          ((err x) (fail s (str "ERR_VAULT_PARSE: resolutions/" r.resolutionId ": " x)))
          ((ok x) (if (sameResolve? x r) (done s true) (bind (putRow s step "resolutions" r.resolutionId (pairFirst p) (m/emitResolution r) now) (fn [(s1 S) (_ Int64)] -> (Pair S (Result Bool String)) (done s1 true))))))))))

; (:m :ref VS-VAULT :do "the last step of a resolve: CAS the row to state done; a row already done is left alone, a stale revision re-reads once")
fn finishResolution st: S step: (fn [S ty/Op] -> (Pair S ty/Reply)) now: Int64 r: m/Resolution tries: Int64 -> (Pair S (Result Bool String))
  (bind (getRow st step "resolutions" r.resolutionId now) (fn [(s S) (row (Option (Pair Int64 String)))] -> (Pair S (Result Bool String))
    (match row
      ((none) (fail s (str "ERR_VAULT_NOTFOUND: resolutions/" r.resolutionId)))
      ((some p)
        (match (m/parseResolution (pairSecond p))
          ((err x) (fail s (str "ERR_VAULT_PARSE: resolutions/" r.resolutionId ": " x)))
          ((ok x)
            (if (= x.state "done")
              (done s true)
              (let [(w (putRow s step "resolutions" r.resolutionId (pairFirst p) (m/emitResolution (doneOf x)) now))]
                (match (pairSecond w)
                  ((ok _) (done (pairFirst w) true))
                  ((err e) (if (and (> tries 0) (stringContains? e "ERR_VAULT_CONFLICT"))
                             (finishResolution (pairFirst w) step now r (- tries 1))
                             (fail (pairFirst w) e))))))))))))

; (:m :ref VS-VAULT :do "a resolve is: the pending resolution row, then the outcome in commit order (the loser's row first as a replacement with the winner as payload, then the other entries, the completion of the winner and the edge), then the row to done; a crash anywhere is finished by repeating the resolve or by the sweep")
fn resolveWrite st: S step: (fn [S ty/Op] -> (Pair S ty/Reply)) now: Int64 r: m/Resolution rows: (List EntryRow) -> (Pair S (Result Bool String))
  (let [(es (entriesOf rows))
        (loserId (loserOf r.entryA r.entryB r.outcome))
        (winnerId (winnerOf r.entryA r.entryB r.outcome))
        (after (withLoserPayload es (cu/resolveEntries es r.entryA r.entryB r.outcome now) loserId winnerId))]
    (bind (beginResolution st step now r) (fn [(s0 S) (_ Bool)] -> (Pair S (Result Bool String))
    (bind (writeChanged s0 step (rowsWhere rows loserId true) after now) (fn [(s1 S) (_ Int64)] -> (Pair S (Result Bool String))
    (bind (writeChanged s1 step (rowsWhere rows loserId false) after now) (fn [(s2 S) (_ Int64)] -> (Pair S (Result Bool String))
    (bind (completeWinner s2 step now es winnerId loserId) (fn [(s3 S) (_ Bool)] -> (Pair S (Result Bool String))
    (bind (nuanceEdge s3 step now r) (fn [(s4 S) (_ Bool)] -> (Pair S (Result Bool String))
      (finishResolution s4 step now r 2))))))))))))

fn nuanceEdge st: S step: (fn [S ty/Op] -> (Pair S ty/Reply)) now: Int64 r: m/Resolution -> (Pair S (Result Bool String))
  (if (= r.outcome "nuance")
    (match (cu/resolveEdge r.entryA r.entryB r.outcome)
      ((some e) (bind (writeEdge st step e now) (fn [(s S) (_ Int64)] -> (Pair S (Result Bool String)) (done s true))))
      ((none) (done st true)))
    (done st true))

; (:m :ref VS-VAULT :do "the contradicts pairs between active entries that no acceptA, acceptB or nuance resolution has closed")
fn openContradictionsOf st: S step: (fn [S ty/Op] -> (Pair S ty/Reply)) now: Int64 -> (Pair S (Result (List (Pair String String)) String))
  (bind (loadEntries st step now) (fn [(s0 S) (rows (List EntryRow))] -> (Pair S (Result (List (Pair String String)) String))
  (bind (loadEdges s0 step now) (fn [(s1 S) (edges (List m/Edge))] -> (Pair S (Result (List (Pair String String)) String))
  (bind (loadResolutions s1 step now) (fn [(s2 S) (rs (List m/Resolution))] -> (Pair S (Result (List (Pair String String)) String))
    (done s2 (cu/openContradictions (entriesOf rows) edges rs))))))))

fn activeEntriesOf st: S step: (fn [S ty/Op] -> (Pair S ty/Reply)) now: Int64 -> (Pair S (Result (List m/Entry) String))
  (bind (loadEntries st step now) (fn [(s S) (rows (List EntryRow))] -> (Pair S (Result (List m/Entry) String))
    (done s (filter m/entryActive? (entriesOf rows)))))

; (:m :ref VS-VAULT :do "the active entries whose scope applies to the query Map, in id order; an entry with an empty scope applies to every query")
fn entriesInScope st: S step: (fn [S ty/Op] -> (Pair S ty/Reply)) now: Int64 query: (Map String String) -> (Pair S (Result (List m/Entry) String))
  (bind (activeEntriesOf st step now) (fn [(s S) (es (List m/Entry))] -> (Pair S (Result (List m/Entry) String))
    (done s (filter (fn [(e m/Entry)] -> Bool (m/scopeMatches? e query)) es))))

fn countStatus es: (List m/Entry) status: String -> Int64
  (listLength (filter (fn [(e m/Entry)] -> Bool (= e.status status)) es))

fn staleCount st: S step: (fn [S ty/Op] -> (Pair S ty/Reply)) now: Int64 es: (List m/Entry) n: Int64 -> (Pair S (Result Int64 String))
  (match (listHead es)
    ((none) (done st n))
    ((some e)
      (bind (getUnit st step now e.unitHash) (fn [(s S) (u (Option un/ProvUnit))] -> (Pair S (Result Int64 String))
        (staleCount s step now (optionOr (listTail es) (list))
          (match u ((some x) (if (<= x.reviewBy now) (+ n 1) n)) ((none) n)))))))

; (:m :ref VS-VAULT :do "counts of every status, edges and open contradictions; an active entry is stale when its unit's reviewBy is at or before now")
fn vaultStats st: S step: (fn [S ty/Op] -> (Pair S ty/Reply)) now: Int64 -> (Pair S (Result VaultStats String))
  (bind (loadEntries st step now) (fn [(s0 S) (rows (List EntryRow))] -> (Pair S (Result VaultStats String))
  (bind (loadEdges s0 step now) (fn [(s1 S) (edges (List m/Edge))] -> (Pair S (Result VaultStats String))
  (bind (loadResolutions s1 step now) (fn [(s2 S) (rs (List m/Resolution))] -> (Pair S (Result VaultStats String))
  (let [(es (entriesOf rows)) (act (filter m/entryActive? es))]
    (bind (staleCount s2 step now act 0) (fn [(s3 S) (stale Int64)] -> (Pair S (Result VaultStats String))
      (done s3 (VaultStats :totalEntries (listLength es) :activeEntries (listLength act) :pinnedCount (countStatus es "pinned")
                           :disputedCount (countStatus es "disputed") :supersededCount (countStatus es "superseded")
                           :quarantinedCount (countStatus es "quarantined") :staleCount stale :edgeCount (listLength edges)
                           :openContradictions (listLength (cu/openContradictions es edges rs)))))))))))))
