(module asl-vault/tests/vaultTest
  :x [runTests]
  :i [(asl-store/mem :a mem) (asl-vault/model :a m) (asl-vault/unit :a un) (asl-vault/time :a tm) (asl-vault/vault :a vt)])

fn now0 -> Int64
  (optionOr (tm/isoToEpoch "2026-11-20T12:00:00Z") 0)

fn scope1 ch: String -> (Map String String)
  (mapSet (mapEmpty) "channel" ch)

; (:m :ref VS-VAULT :do "ported from automate vaultTest baseSpec: same ids, titles and bodies, with the channel, audience and topic columns generalised to a scope Map and nowIso to epoch ms")
fn baseSpec id: String layer: String role: String sc: (Map String String) title: String body: String -> vt/IngestSpec
  (vt/IngestSpec :entryId id :kind "note" :layer layer :role role :scope sc :status "corroborated" :provenance "primary" :sourceHashes (list)
                 :title title :summary title :bodyText body :source "" :licence "owner-notes" :confidenceBp 9500 :ttlDays 180 :tags (list "test")
                 :priorityBp 8000 :validFrom 0 :replacesEntryId "")

fn okOf r: (Pair S (Result A String)) -> Bool
  (ok? (pairSecond r))

fn errHas? r: (Pair S (Result A String)) what: String -> Bool
  (match (pairSecond r) ((err e) (stringContains? e what)) ((ok _) false))

fn passages r: (Pair S (Result vt/IngestResult String)) -> Int64
  (match (pairSecond r) ((ok x) x.passageCount) ((err _) -1))

fn unitHashOf r: (Pair S (Result vt/IngestResult String)) -> String
  (match (pairSecond r) ((ok x) x.unitHash) ((err _) ""))

fn countOf r: (Pair S (Result (List A) String)) -> Int64
  (match (pairSecond r) ((ok xs) (listLength xs)) ((err _) -1))

fn statusIs? r: (Pair S (Result (Option m/Entry) String)) status: String by: String -> Bool
  (match (pairSecond r) ((ok (some e)) (and (= e.status status) (= e.supersededBy by))) (_ false))

fn mdBody -> String
  "# Audience Pain Notes\n\nRetail investors feel hidden advisory fees silently drain retirement accounts.\n\n# Quotes\nWhy did nobody warn me about trailing commissions?"

; (:m :ref VS-VAULT :do "ports automate testIngestPersistenceAndFts5 minus the sqlite index (VS-INDEX owns recall): 9 checks there, 9 ported here plus bitemporal, content addressing and duplicate refusal")
fn testIngestAndScope -> Bool
  (let [(st0 (mem/memEmpty))
        (sBrand (with (baseSpec "brand-voice" "brand" "styleToken" (scope1 "ch-fin") "Signature Voice" "Speak with crisp numbers and zero hype.\n\n# Framework\nUse the Compound Drag Lens framework.") :status "pinned" :priorityBp 9800))
        (sGlobal (baseSpec "global-fee-study" "global" "evidence" (mapEmpty) "Index Fee Drag Study" "Expense ratios above 0.75 percent compound into 28 percent wealth loss over thirty years."))
        (sAud (with (baseSpec "aud-pain-md" "audience" "painPoint" (mapSet (scope1 "ch-fin") "audience" "aud-retire") "Gemini Notebook Export" (mdBody)) :kind "notebookExport"))
        (r1 (vt/ingest st0 mem/memStep (now0) sBrand))
        (r2 (vt/ingest (pairFirst r1) mem/memStep (now0) sGlobal))
        (r3 (vt/ingest (pairFirst r2) mem/memStep (now0) sAud))
        (dup (vt/ingest (pairFirst r3) mem/memStep (now0) (with sBrand :bodyText "another body")))
        (same (vt/ingest (pairFirst dup) mem/memStep (+ (now0) 5000) sBrand))
        (st3 (pairFirst same))
        (reloaded (vt/loadEntries st3 mem/memStep (now0)))
        (qFin (vt/entriesInScope (pairFirst reloaded) mem/memStep (now0) (mapSet (scope1 "ch-fin") "audience" "aud-retire")))
        (qOther (vt/entriesInScope (pairFirst qFin) mem/memStep (now0) (scope1 "ch-other")))
        (act (vt/activeEntriesOf (pairFirst qOther) mem/memStep (now0)))
        (stats (vt/vaultStats (pairFirst act) mem/memStep (now0)))
        (unit (vt/getUnit (pairFirst stats) mem/memStep (now0) (unitHashOf r3)))
        (body (vt/getBody (pairFirst unit) mem/memStep (now0) (un/sha256Hex (mdBody))))
        (brand (vt/getEntry (pairFirst body) mem/memStep (now0) "brand-voice"))]
    (do
      (assert (= (passages r1) 2) "markdown heading splits into 2 passages")
      (assert (= (passages r3) 3) "markdown file splits into 3 passages")
      (assert (ok? (pairSecond reloaded)) "vault round-trips cleanly through emitEntry/parseEntry")
      (assert (= (countOf reloaded) 3) "reloaded vault has 3 entries")
      (assert (= (countOf qFin) 3) "ch-fin sees global + brand + audience entries")
      (assert (= (countOf qOther) 1) "ch-other sees only global entry")
      (assert (= (countOf act) 3) "3 active entries project")
      (assert (match (pairSecond stats) ((ok s) (and (= s.totalEntries 3) (and (= s.pinnedCount 1) (= s.staleCount 0)))) ((err _) false)) "stats report 3 total, 1 pinned, 0 stale")
      (assert (errHas? dup "ERR_VAULT_EXISTS") "ingesting an existing entry id with another claim is refused, history is never overwritten")
      (assert (and (okOf same) (= (countOf reloaded) 3)) "repeating the same spec later is the same claim: ok and no second entry")
      (assert (match (pairSecond unit) ((ok (some u)) (= (un/bodyHash u) u.contentHash)) (_ false)) "the stored unit is sealed: its hash binds its bytes and its key")
      (assert (match (pairSecond body) ((ok (some t)) (= t (mdBody))) (_ false)) "the body is stored under its sha256 and read back whole")
      (assert (match (pairSecond brand) ((ok (some e)) (and (= e.validFrom (now0)) (and (= e.validTo 0) (and (= e.recordedAt (now0)) (= e.bodyHash (un/sha256Hex "Speak with crisp numbers and zero hype.\n\n# Framework\nUse the Compound Drag Lens framework.")))))) (_ false)) "a new entry is valid from now, open ended, recorded now and keyed to its body hash")
      true))

fn derivedSpec -> vt/IngestSpec
  (baseSpec "derived-no-src" "topic" "evidence" (scope1 "ch-fin") "Bad Derived" "Unbacked LLM claim")

; (:m :ref VS-VAULT :do "ports automate testSupersedeContradictionAndProvenanceGuards: its 7 checks, then supersede of a superseded entry, a cycle, direct superseded status, a missing link end, a repeated resolution id and needsResearch")
fn testCurate -> Bool
  (let [(st0 (mem/memEmpty))
        (sOld (baseSpec "fact-2024" "topic" "evidence" (scope1 "ch-fin") "2024 Fee Average" "Average equity fund fee was 0.68 percent in 2024."))
        (sContra (baseSpec "fact-counter" "topic" "evidence" (scope1 "ch-fin") "Counter Report" "Asset-weighted index fee dropped to 0.05 percent."))
        (rOld (vt/ingest st0 mem/memStep (now0) sOld))
        (rCon (vt/ingest (pairFirst rOld) mem/memStep (now0) sContra))
        (rBad (vt/ingest (pairFirst rCon) mem/memStep (now0) (with (derivedSpec) :provenance "derived" :sourceHashes (list))))
        (rBadHex (vt/ingest (pairFirst rBad) mem/memStep (now0) (with (derivedSpec) :provenance "derived" :sourceHashes (list "not-a-hash"))))
        (sNew (with (baseSpec "fact-2026" "topic" "evidence" (scope1 "ch-fin") "2026 Fee Average" "Average equity fund fee fell to 0.52 percent in 2026.") :replacesEntryId "fact-2024"))
        (rNew (vt/ingest (pairFirst rBadHex) mem/memStep (+ (now0) 1000) sNew))
        (sDer (with (baseSpec "derived-summary" "topic" "evidence" (scope1 "ch-fin") "Grounded Summary" "Fees fell sharply across index funds.") :provenance "derived" :sourceHashes (list (unitHashOf rOld))))
        (rDer (vt/ingest (pairFirst rNew) mem/memStep (+ (now0) 2000) sDer))
        (rMissing (vt/ingest (pairFirst rDer) mem/memStep (now0) (with (baseSpec "orphan" "topic" "evidence" (mapEmpty) "Orphan" "x") :replacesEntryId "nope")))
        (rReplaceDead (vt/ingest (pairFirst rMissing) mem/memStep (now0) (with (baseSpec "again" "topic" "evidence" (mapEmpty) "Again" "y") :replacesEntryId "fact-2024")))
        (again (vt/getEntry (pairFirst rReplaceDead) mem/memStep (now0) "again"))
        (old (vt/getEntry (pairFirst again) mem/memStep (now0) "fact-2024"))
        (linked (vt/linkEntries (pairFirst old) mem/memStep (+ (now0) 300000) "fact-2026" "fact-counter" "contradicts" 9000))
        (ghost (vt/linkEntries (pairFirst linked) mem/memStep (now0) "fact-2026" "ghost" "grounds" 5000))
        (selfLink (vt/linkEntries (pairFirst ghost) mem/memStep (now0) "fact-2026" "fact-2026" "grounds" 5000))
        (open1 (vt/openContradictionsOf (pairFirst selfLink) mem/memStep (now0)))
        (disputedNew (vt/getEntry (pairFirst open1) mem/memStep (now0) "fact-2026"))
        (disputedCon (vt/getEntry (pairFirst disputedNew) mem/memStep (now0) "fact-counter"))
        (resNuance (vt/resolveContradiction (pairFirst disputedCon) mem/memStep (+ (now0) 600000) "res-1" "fact-2026" "fact-counter" "nuance" "0.52% is equal-weighted; 0.05% is asset-weighted"))
        (open2 (vt/openContradictionsOf (pairFirst resNuance) mem/memStep (now0)))
        (act2 (vt/activeEntriesOf (pairFirst open2) mem/memStep (now0)))
        (noEdge (vt/resolveContradiction (pairFirst act2) mem/memStep (now0) "res-x" "fact-2026" "derived-summary" "acceptA" "none"))
        (badOutcome (vt/resolveContradiction (pairFirst noEdge) mem/memStep (now0) "res-y" "fact-2026" "fact-counter" "maybe" "none"))
        (resA (vt/resolveContradiction (pairFirst badOutcome) mem/memStep (+ (now0) 700000) "res-1" "fact-2026" "fact-counter" "acceptA" "prefer equal-weighted benchmark"))
        (counter (vt/getEntry (pairFirst resA) mem/memStep (now0) "fact-counter"))
        (act3 (vt/activeEntriesOf (pairFirst counter) mem/memStep (now0)))
        (quar (vt/setEntryStatus (pairFirst act3) mem/memStep (+ (now0) 720000) "derived-summary" "quarantined"))
        (act4 (vt/activeEntriesOf (pairFirst quar) mem/memStep (now0)))
        (stale (vt/vaultStats (pairFirst act4) mem/memStep (+ (now0) (* 366 86400000))))]
    (do
      (assert (errHas? rBad "ERR_VAULT_PROVENANCE") "derived entry without sourceHashes rejected")
      (assert (errHas? rBadHex "ERR_VAULT_PROVENANCE") "derived entry with a non-sha256 sourceHash rejected")
      (assert (okOf rNew) "an entry that replaces a live entry is ingested")
      (assert (statusIs? old "superseded" "fact-2026") "replacesEntryId automatically marks old entry superseded")
      (assert (match (pairSecond old) ((ok (some e)) (= e.validTo (+ (now0) 1000))) (_ false)) "the replaced entry stops being valid when its replacement is recorded")
      (assert (errHas? rMissing "ERR_VAULT_NOTFOUND") "replacing an unknown entry is refused")
      (assert (errHas? rReplaceDead "ERR_VAULT_SUPERSEDED") "replacing an already superseded entry is refused")
      (assert (match (pairSecond again) ((ok (none)) true) (_ false)) "the refused replacement left no entry behind")
      (assert (errHas? ghost "ERR_VAULT_NOTFOUND") "a link to an unknown entry is refused")
      (assert (errHas? selfLink "ERR_VAULT_EDGE") "a self link is refused")
      (assert (= (countOf open1) 1) "linked contradicts edge opens 1 contradiction")
      (assert (match (pairSecond disputedNew) ((ok (some e)) (= e.status "disputed")) (_ false)) "a contradicts link marks both live ends disputed")
      (assert (match (pairSecond disputedCon) ((ok (some e)) (= e.status "disputed")) (_ false)) "a contradicts link marks the other end fact-counter disputed too")
      (assert (okOf resNuance) "a nuance resolution is recorded")
      (assert (and (= (countOf open2) 0) (= (countOf act2) 3)) "nuance resolution closes contradiction keeping both sides active")
      (assert (errHas? noEdge "ERR_VAULT_NO_CONTRADICTION") "resolving a pair with no contradicts edge is refused")
      (assert (errHas? badOutcome "ERR_VAULT_ARG") "an outcome outside the four is refused")
      (assert (statusIs? counter "superseded" "fact-2026") "acceptA resolution supersedes fact-counter")
      (assert (= (countOf act3) 2) "acceptA resolution leaves 2 active entries")
      (assert (okOf quar) "setting quarantined succeeds")
      (assert (= (countOf act4) 1) "quarantining entry removes it from activeEntries")
      (assert (match (pairSecond stale) ((ok s) (and (= s.staleCount 1) (and (= s.supersededCount 2) (= s.quarantinedCount 1)))) ((err _) false)) "a year later the one active entry is stale and the counts of statuses add up")
      true))

; (:m :ref VS-VAULT :do "the supersede chain is a line: a superseded entry cannot be superseded again, a cycle is refused, superseded cannot be set directly, and a refused call writes nothing")
fn testSupersedeChain -> Bool
  (let [(st0 (mem/memEmpty))
        (a (vt/ingest st0 mem/memStep (now0) (baseSpec "ea" "topic" "evidence" (mapEmpty) "A" "alpha")))
        (b (vt/ingest (pairFirst a) mem/memStep (now0) (baseSpec "eb" "topic" "evidence" (mapEmpty) "B" "beta")))
        (c (vt/ingest (pairFirst b) mem/memStep (now0) (baseSpec "ec" "topic" "evidence" (mapEmpty) "C" "gamma")))
        (s1 (vt/supersedeEntry (pairFirst c) mem/memStep (+ (now0) 10) "ea" "eb"))
        (again (vt/supersedeEntry (pairFirst s1) mem/memStep (+ (now0) 20) "ea" "ec"))
        (cycle (vt/supersedeEntry (pairFirst again) mem/memStep (+ (now0) 30) "eb" "ea"))
        (toDead (vt/supersedeEntry (pairFirst cycle) mem/memStep (+ (now0) 40) "ec" "ea"))
        (self (vt/supersedeEntry (pairFirst toDead) mem/memStep (+ (now0) 50) "ec" "ec"))
        (direct (vt/setEntryStatus (pairFirst self) mem/memStep (+ (now0) 60) "ec" "superseded"))
        (s2 (vt/supersedeEntry (pairFirst direct) mem/memStep (+ (now0) 70) "eb" "ec"))
        (cycle2 (vt/supersedeEntry (pairFirst s2) mem/memStep (+ (now0) 80) "ec" "ea"))
        (ea (vt/getEntry (pairFirst cycle2) mem/memStep (now0) "ea"))
        (eb (vt/getEntry (pairFirst ea) mem/memStep (now0) "eb"))
        (ec (vt/getEntry (pairFirst eb) mem/memStep (now0) "ec"))
        (edges (vt/loadEdges (pairFirst ec) mem/memStep (now0)))]
    (do
      (assert (okOf s1) "superseding a live entry by another succeeds")
      (assert (errHas? again "ERR_VAULT_SUPERSEDED") "superseding an already superseded entry is refused")
      (assert (errHas? cycle "ERR_VAULT_CYCLE") "superseding the new entry by the one it replaced is a cycle and is refused")
      (assert (errHas? toDead "ERR_VAULT_SUPERSEDED") "a superseded entry cannot replace anything")
      (assert (errHas? self "ERR_VAULT_ARG") "an entry cannot supersede itself")
      (assert (errHas? direct "ERR_VAULT_ARG") "status superseded cannot be set directly")
      (assert (okOf s2) "the chain extends from its live end")
      (assert (errHas? cycle2 "ERR_VAULT_CYCLE") "a three-entry cycle is refused")
      (assert (statusIs? ea "superseded" "eb") "ea keeps its first successor after the refused attempts")
      (assert (statusIs? eb "superseded" "ec") "eb is superseded by ec")
      (assert (match (pairSecond ec) ((ok (some e)) (and (= e.status "corroborated") (= e.supersededBy ""))) (_ false)) "the chain ends in one live entry")
      (assert (= (countOf edges) 2) "each accepted supersede wrote exactly one refines edge and the refused ones none")
      true))

fn live r: (Pair S (Result (Option m/Entry) String)) -> String
  (match (pairSecond r) ((ok (some e)) (str e.status ">" e.supersededBy)) ((ok (none)) "absent") ((err e) e))

; (:m :ref VS-VAULT :do "a resolution cannot bypass the supersede rules: with ea superseded by eb and the two linked as contradicts, acceptA and acceptB are refused, nothing is written, no resolution row appears and no cycle forms; a quarantined end also refuses")
fn testResolveGuards -> Bool
  (let [(st0 (mem/memEmpty))
        (a (vt/ingest st0 mem/memStep (now0) (baseSpec "ea" "topic" "evidence" (mapEmpty) "A" "alpha")))
        (b (vt/ingest (pairFirst a) mem/memStep (now0) (baseSpec "eb" "topic" "evidence" (mapEmpty) "B" "beta")))
        (c (vt/ingest (pairFirst b) mem/memStep (now0) (baseSpec "ec" "topic" "evidence" (mapEmpty) "C" "gamma")))
        (s (vt/supersedeEntry (pairFirst c) mem/memStep (+ (now0) 10) "ea" "eb"))
        (l (vt/linkEntries (pairFirst s) mem/memStep (+ (now0) 20) "ea" "eb" "contradicts" 9000))
        (rA (vt/resolveContradiction (pairFirst l) mem/memStep (+ (now0) 30) "r1" "ea" "eb" "acceptA" "n"))
        (rB (vt/resolveContradiction (pairFirst rA) mem/memStep (+ (now0) 40) "r2" "ea" "eb" "acceptB" "n"))
        (rN (vt/resolveContradiction (pairFirst rB) mem/memStep (+ (now0) 45) "r3" "ea" "eb" "nuance" "n"))
        (ea (vt/getEntry (pairFirst rN) mem/memStep (now0) "ea"))
        (eb (vt/getEntry (pairFirst ea) mem/memStep (now0) "eb"))
        (rs (vt/loadResolutions (pairFirst eb) mem/memStep (now0)))
        (l2 (vt/linkEntries (pairFirst rs) mem/memStep (+ (now0) 50) "eb" "ec" "contradicts" 9000))
        (q (vt/setEntryStatus (pairFirst l2) mem/memStep (+ (now0) 60) "ec" "quarantined"))
        (rQ (vt/resolveContradiction (pairFirst q) mem/memStep (+ (now0) 70) "r4" "eb" "ec" "acceptA" "n"))
        (rs2 (vt/loadResolutions (pairFirst rQ) mem/memStep (now0)))
        (ebOk (vt/getEntry (pairFirst rs2) mem/memStep (now0) "eb"))]
    (do
      (assert (errHas? rA "ERR_VAULT_INACTIVE") "acceptA over a superseded end is refused")
      (assert (errHas? rB "ERR_VAULT_INACTIVE") "acceptB over a superseded end is refused")
      (assert (errHas? rN "ERR_VAULT_INACTIVE") "even nuance needs both ends active")
      (assert (= (live ea) "superseded>eb") "ea stays superseded by eb, it is not revived")
      (assert (= (live eb) "disputed>") "eb is not superseded back by ea: no cycle")
      (assert (= (countOf rs) 0) "no resolution row was written by the refused calls")
      (assert (errHas? rQ "ERR_VAULT_INACTIVE") "a quarantined end refuses the resolution")
      (assert (= (countOf rs2) 0) "the quarantine refusal wrote no resolution")
      (assert (= (live ebOk) "disputed>") "eb is untouched by the refused resolution")
      true))

fn runTests -> Bool
  (and (testIngestAndScope) (and (testCurate) (and (testSupersedeChain) (testResolveGuards))))
