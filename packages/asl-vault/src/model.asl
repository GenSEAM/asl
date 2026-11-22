(module asl-vault/model
  :x [Entry Edge Resolution statuses validStatus? outcomes validOutcome? relations validRelation? provenances validProvenance?
      entryActive? sameOrigin scopeMatches? emitEntry parseEntry emitEdge parseEdge emitResolution parseResolution edgeKey pairMatches?]
  :i [(asl-store/wire :a w) (asl-vault/codec :a cd)])

; (:m :ref VS-VAULT :do "one claim in the vault: provenance by unitHash, text by bodyHash, a scope Map that says where it applies (an empty scope is global), a status, a supersededBy link and bitemporal times in epoch ms where validTo 0 means still valid, pending holds the whole row of the entry that replaced this one until it is stored (the single commit of a replacement), recordedAt is when the vault learned it and updatedAt when the row last changed")
(schema Entry
  (:f entryId String)
  (:f unitHash String)
  (:f bodyHash String)
  (:f layer String)
  (:f role String)
  (:f scope (Map String String))
  (:f status String)
  (:f supersededBy String)
  (:f pending String)
  (:f provenance String)
  (:f sourceHashes (List String))
  (:f title String)
  (:f summary String)
  (:f tags (List String))
  (:f priorityBp Int64)
  (:f validFrom Int64)
  (:f validTo Int64)
  (:f recordedAt Int64)
  (:f updatedAt Int64))

(schema Edge (:f fromId String) (:f toId String) (:f relation String) (:f weightBp Int64))

(schema Resolution (:f resolutionId String) (:f entryA String) (:f entryB String) (:f outcome String) (:f note String) (:f resolvedAt Int64) (:f state String))

fn statuses -> (List String)
  (list "unverified" "corroborated" "pinned" "disputed" "superseded" "quarantined")

fn validStatus? s: String -> Bool
  (listContains? (statuses) s)

fn outcomes -> (List String)
  (list "acceptA" "acceptB" "nuance" "needsResearch")

fn validOutcome? s: String -> Bool
  (listContains? (outcomes) s)

fn relations -> (List String)
  (list "grounds" "contradicts" "refines" "derivesFrom")

fn validRelation? s: String -> Bool
  (listContains? (relations) s)

fn provenances -> (List String)
  (list "primary" "derived")

fn validProvenance? s: String -> Bool
  (listContains? (provenances) s)

; (:m :ref VS-VAULT :do "superseded and quarantined entries are out of play; every other status, disputed included, is active")
fn entryActive? e: Entry -> Bool
  (and (!= e.status "superseded") (!= e.status "quarantined"))

; (:m :ref VS-VAULT :do "two rows are the same claim when everything but the fields that change after creation (status, supersededBy, pending, validTo, updatedAt) is equal; a row that differs is a different claim under the same id")
fn sameOrigin a: Entry b: Entry -> Bool
  (= (emitEntry (with a :status b.status :supersededBy b.supersededBy :pending b.pending :validTo b.validTo :updatedAt b.updatedAt)) (emitEntry b))

fn scopeHolds? query: (Map String String) p: (Pair String String) -> Bool
  (or (= (pairSecond p) "*") (= (mapGet query (pairFirst p)) (some (pairSecond p))))

; (:m :ref VS-VAULT :do "an entry applies to a query scope when every key it names holds the same value in the query, or the entry's value is *; an entry with an empty scope applies everywhere, so the global layer needs no special case")
fn scopeMatches? e: Entry query: (Map String String) -> Bool
  (listAll? (fn [(k String)] -> Bool (scopeHolds? query (pair k (optionOr (mapGet e.scope k) "")))) (mapKeys e.scope))

fn scopePairs m: (Map String String) -> (List (Pair String String))
  (map (fn [(k String)] -> (Pair String String) (pair k (optionOr (mapGet m k) ""))) (listSort (mapKeys m)))

fn kvp k: String v: w/Sx -> (List w/Sx)
  (list (cd/atomSx k) v)

; (:m :ref VS-VAULT :do "one canonical single-line row per entry, scope keys sorted, so equal entries have equal bytes")
fn emitEntry e: Entry -> String
  (w/sxShow (w/sxList (listFlatMap (fn [(x (List w/Sx))] -> (List w/Sx) x) (list
    (list (cd/atomSx ":entry"))
    (kvp ":entryId" (cd/strSx e.entryId)) (kvp ":unitHash" (cd/strSx e.unitHash)) (kvp ":bodyHash" (cd/strSx e.bodyHash))
    (kvp ":layer" (cd/strSx e.layer)) (kvp ":role" (cd/strSx e.role)) (kvp ":scope" (cd/pairList (scopePairs e.scope)))
    (kvp ":status" (cd/strSx e.status)) (kvp ":supersededBy" (cd/strSx e.supersededBy)) (kvp ":pending" (cd/strSx e.pending)) (kvp ":provenance" (cd/strSx e.provenance))
    (kvp ":sourceHashes" (cd/strList e.sourceHashes)) (kvp ":title" (cd/strSx e.title)) (kvp ":summary" (cd/strSx e.summary))
    (kvp ":tags" (cd/strList e.tags)) (kvp ":priorityBp" (cd/intSx e.priorityBp)) (kvp ":validFrom" (cd/intSx e.validFrom))
    (kvp ":validTo" (cd/intSx e.validTo)) (kvp ":recordedAt" (cd/intSx e.recordedAt)) (kvp ":updatedAt" (cd/intSx e.updatedAt))))))

fn entryShape -> (List (Pair String String))
  (list (pair ":entryId" "s") (pair ":unitHash" "s") (pair ":bodyHash" "s") (pair ":layer" "s") (pair ":role" "s") (pair ":scope" "l")
        (pair ":status" "s") (pair ":supersededBy" "s") (pair ":pending" "s") (pair ":provenance" "s") (pair ":sourceHashes" "S") (pair ":title" "s")
        (pair ":summary" "s") (pair ":tags" "S") (pair ":priorityBp" "i") (pair ":validFrom" "i") (pair ":validTo" "i")
        (pair ":recordedAt" "i") (pair ":updatedAt" "i"))

fn scopeMap ps: (List (Pair String String)) -> (Map String String)
  (fold (fn [(m (Map String String)) (p (Pair String String))] -> (Map String String) (mapSet m (pairFirst p) (pairSecond p))) (mapEmpty) ps)

fn entryOfMap m: (Map String w/Sx) -> Entry
  (Entry :entryId (cd/fs m ":entryId") :unitHash (cd/fs m ":unitHash") :bodyHash (cd/fs m ":bodyHash") :layer (cd/fs m ":layer")
         :role (cd/fs m ":role") :scope (scopeMap (cd/fpairs m ":scope")) :status (cd/fs m ":status") :supersededBy (cd/fs m ":supersededBy") :pending (cd/fs m ":pending")
         :provenance (cd/fs m ":provenance") :sourceHashes (cd/fstrs m ":sourceHashes") :title (cd/fs m ":title") :summary (cd/fs m ":summary")
         :tags (cd/fstrs m ":tags") :priorityBp (cd/fi m ":priorityBp") :validFrom (cd/fi m ":validFrom") :validTo (cd/fi m ":validTo")
         :recordedAt (cd/fi m ":recordedAt") :updatedAt (cd/fi m ":updatedAt"))

fn rowOf head: String text: String shape: (List (Pair String String)) -> (Result (Map String w/Sx) String)
  (cd/andThen (w/sxRead text) (fn [(forms (List w/Sx))] -> (Result (Map String w/Sx) String)
    (if (!= (listLength forms) 1)
      (err (str "a " head " row is exactly one form"))
      (cd/andThen (cd/formItems head (w/headOr forms)) (fn [(items (List w/Sx))] -> (Result (Map String w/Sx) String)
        (let [(m (cd/fieldMap items))]
          (cd/andThen (cd/checkShape m shape) (fn [(_ Bool)] -> (Result (Map String w/Sx) String) (ok m)))))))))

; (:m :ref VS-VAULT :do "the inverse of emitEntry; a missing field is an error, never a default, and a status outside the six is refused")
fn parseEntry text: String -> (Result Entry String)
  (cd/andThen (rowOf ":entry" text (entryShape)) (fn [(m (Map String w/Sx))] -> (Result Entry String)
    (let [(e (entryOfMap m))]
      (if (validStatus? e.status) (ok e) (err (str "bad status " e.status))))))

; (:m :ref VS-VAULT :do "edges are stored under fromId/relation/toId, so a prefix scan on a fromId lists its outgoing edges and a repeated link is the same key")
fn edgeKey fromId: String relation: String toId: String -> String
  (str fromId "/" relation "/" toId)

fn emitEdge e: Edge -> String
  (w/sxShow (w/sxList (list (cd/atomSx ":edge") (cd/atomSx ":fromId") (cd/strSx e.fromId) (cd/atomSx ":toId") (cd/strSx e.toId)
                            (cd/atomSx ":relation") (cd/strSx e.relation) (cd/atomSx ":weightBp") (cd/intSx e.weightBp))))

fn parseEdge text: String -> (Result Edge String)
  (cd/andThen (rowOf ":edge" text (list (pair ":fromId" "s") (pair ":toId" "s") (pair ":relation" "s") (pair ":weightBp" "i")))
    (fn [(m (Map String w/Sx))] -> (Result Edge String)
      (ok (Edge :fromId (cd/fs m ":fromId") :toId (cd/fs m ":toId") :relation (cd/fs m ":relation") :weightBp (cd/fi m ":weightBp")))))

fn emitResolution r: Resolution -> String
  (w/sxShow (w/sxList (list (cd/atomSx ":resolution") (cd/atomSx ":resolutionId") (cd/strSx r.resolutionId) (cd/atomSx ":entryA") (cd/strSx r.entryA)
                            (cd/atomSx ":entryB") (cd/strSx r.entryB) (cd/atomSx ":outcome") (cd/strSx r.outcome) (cd/atomSx ":note") (cd/strSx r.note)
                            (cd/atomSx ":resolvedAt") (cd/intSx r.resolvedAt) (cd/atomSx ":state") (cd/strSx r.state))))

fn parseResolution text: String -> (Result Resolution String)
  (cd/andThen (rowOf ":resolution" text (list (pair ":resolutionId" "s") (pair ":entryA" "s") (pair ":entryB" "s") (pair ":outcome" "s") (pair ":note" "s") (pair ":resolvedAt" "i") (pair ":state" "s")))
    (fn [(m (Map String w/Sx))] -> (Result Resolution String)
      (ok (Resolution :resolutionId (cd/fs m ":resolutionId") :entryA (cd/fs m ":entryA") :entryB (cd/fs m ":entryB")
                      :outcome (cd/fs m ":outcome") :note (cd/fs m ":note") :resolvedAt (cd/fi m ":resolvedAt") :state (cd/fs m ":state")))))

fn pairMatches? a: String b: String x: String y: String -> Bool
  (or (and (= a x) (= b y)) (and (= a y) (= b x)))
