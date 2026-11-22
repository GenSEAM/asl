(module asl-vault/curate
  :x [bothActive? findEntry setStatus supersedeProblem supersededEntry applySupersede linkMarks openContradictions resolveEntries resolveEdge promoted]
  :i [(asl-vault/model :a m) (asl-vault/graph :a g) (asl-vault/codec :a cd)])

fn findEntry entries: (List m/Entry) id: String -> (Option m/Entry)
  (listFind (fn [(e m/Entry)] -> Bool (= e.entryId id)) entries)

fn mapEntry entries: (List m/Entry) id: String f: (fn [m/Entry] -> m/Entry) -> (List m/Entry)
  (map (fn [(e m/Entry)] -> m/Entry (if (= e.entryId id) (f e) e)) entries)

fn setStatus e: m/Entry status: String now: Int64 -> m/Entry
  (with e :status status :updatedAt now)

fn reaches? entries: (List m/Entry) from: String target: String left: Int64 -> Bool
  (cond
    ((= from target) true)
    ((<= left 0) true)
    (else (match (findEntry entries from)
            ((some e) (if (stringEmpty? e.supersededBy) false (reaches? entries e.supersededBy target (- left 1))))
            ((none) false))))

; (:m :ref VS-VAULT :do "superseding old by new is refused for a self link, an unknown id, a cycle (new already leads back to old through supersededBy links, or the chain is longer than the entry count), an old entry that is already superseded, and a new entry that is already superseded; the chain therefore stays a line that ends in one live entry")
fn supersedeProblem entries: (List m/Entry) old: String new: String -> (Option String)
  (cond
    ((= old new) (some "ERR_VAULT_ARG: cannot supersede entry with itself"))
    ((none? (findEntry entries old)) (some (str "ERR_VAULT_NOTFOUND: " old)))
    ((none? (findEntry entries new)) (some (str "ERR_VAULT_NOTFOUND: " new)))
    ((reaches? entries new old (listLength entries)) (some (str "ERR_VAULT_CYCLE: " new " already leads to " old)))
    ((match (findEntry entries old) ((some e) (= e.status "superseded")) ((none) false)) (some (str "ERR_VAULT_SUPERSEDED: " old " is already superseded")))
    ((match (findEntry entries new) ((some e) (= e.status "superseded")) ((none) false)) (some (str "ERR_VAULT_SUPERSEDED: " new " is superseded and cannot replace anything")))
    (else (none)))

; (:m :ref VS-VAULT :do "old becomes superseded by new and stops being valid now unless it already had an end; nothing else changes")
fn supersededEntry e: m/Entry new: String now: Int64 -> m/Entry
  (with e :status "superseded" :supersededBy new :validTo (if (= e.validTo 0) now e.validTo) :updatedAt now)

fn applySupersede entries: (List m/Entry) old: String new: String now: Int64 -> (List m/Entry)
  (mapEntry entries old (fn [(e m/Entry)] -> m/Entry (supersededEntry e new now)))

; (:m :ref VS-VAULT :do "a contradicts edge marks both live ends disputed unless pinned")
fn linkMarks entries: (List m/Entry) a: String b: String now: Int64 -> (List m/Entry)
  (map (fn [(e m/Entry)] -> m/Entry
         (if (and (or (= e.entryId a) (= e.entryId b)) (and (!= e.status "pinned") (m/entryActive? e))) (setStatus e "disputed" now) e))
       entries)

fn closing? a: String b: String r: m/Resolution -> Bool
  (and (= r.state "done") (and (m/pairMatches? a b r.entryA r.entryB) (or (= r.outcome "acceptA") (or (= r.outcome "acceptB") (= r.outcome "nuance")))))

fn bothActive? entries: (List m/Entry) a: String b: String -> Bool
  (match (findEntry entries a)
    ((some x) (match (findEntry entries b) ((some y) (and (m/entryActive? x) (m/entryActive? y))) ((none) false)))
    ((none) false))

fn seenPair? acc: (List (Pair String String)) e: m/Edge -> Bool
  (listAny? (fn [(p (Pair String String))] -> Bool (m/pairMatches? (pairFirst p) (pairSecond p) e.fromId e.toId)) acc)

; (:m :ref VS-VAULT :do "a contradicts edge between two active entries stays listed, once per pair, until a resolution with outcome acceptA, acceptB or nuance names the pair; needsResearch records a note and leaves it open")
fn openContradictions entries: (List m/Entry) edges: (List m/Edge) resolutions: (List m/Resolution) -> (List (Pair String String))
  (fold (fn [(acc (List (Pair String String))) (e m/Edge)] -> (List (Pair String String))
          (if (and (= e.relation "contradicts")
                   (and (bothActive? entries e.fromId e.toId)
                        (and (not (listAny? (fn [(r m/Resolution)] -> Bool (closing? e.fromId e.toId r)) resolutions))
                             (not (seenPair? acc e)))))
            (listAppend acc (list (pair e.fromId e.toId)))
            acc))
        (list) edges)

fn promoted e: m/Entry now: Int64 -> m/Entry
  (if (= e.status "pinned") e (setStatus e "corroborated" now))

fn demoted e: m/Entry winner: String now: Int64 -> m/Entry
  (with e :status "superseded" :supersededBy winner :validTo (if (= e.validTo 0) now e.validTo) :updatedAt now)

fn disputed e: m/Entry now: Int64 -> m/Entry
  (if (= e.status "pinned") e (setStatus e "disputed" now))

; (:m :ref VS-VAULT :do "acceptA keeps A and supersedes B (acceptB the reverse), nuance keeps both and corroborates them, needsResearch keeps both disputed; pinned entries are never demoted by status")
fn resolveEntries entries: (List m/Entry) a: String b: String outcome: String now: Int64 -> (List m/Entry)
  (map (fn [(e m/Entry)] -> m/Entry
         (cond
           ((and (= outcome "acceptA") (= e.entryId a)) (promoted e now))
           ((and (= outcome "acceptA") (= e.entryId b)) (demoted e a now))
           ((and (= outcome "acceptB") (= e.entryId b)) (promoted e now))
           ((and (= outcome "acceptB") (= e.entryId a)) (demoted e b now))
           ((and (= outcome "nuance") (or (= e.entryId a) (= e.entryId b))) (promoted e now))
           ((and (= outcome "needsResearch") (or (= e.entryId a) (= e.entryId b))) (disputed e now))
           (else e)))
       entries)

fn resolveEdge a: String b: String outcome: String -> (Option m/Edge)
  (cond
    ((= outcome "acceptA") (some (m/Edge :fromId a :toId b :relation "refines" :weightBp 9500)))
    ((= outcome "acceptB") (some (m/Edge :fromId b :toId a :relation "refines" :weightBp 9500)))
    ((= outcome "nuance") (some (m/Edge :fromId a :toId b :relation "refines" :weightBp 8000)))
    (else (none)))
