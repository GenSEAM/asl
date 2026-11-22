(module asl-vault/tests/modelTest
  :x [runTests]
  :i [(asl-vault/model :a m) (asl-vault/graph :a g) (asl-vault/curate :a cu) (asl-vault/codec :a cd)])

fn edge f: String t: String r: String w: Int64 -> m/Edge
  (m/Edge :fromId f :toId t :relation r :weightBp w)

fn entry id: String status: String sc: (Map String String) -> m/Entry
  (m/Entry :entryId id :unitHash "" :bodyHash "" :layer "topic" :role "evidence" :scope sc :status status :supersededBy "" :pending "" :provenance "primary"
           :sourceHashes (list) :title (str "T " id) :summary "s" :tags (list "a" "b c") :priorityBp 100 :validFrom 5 :validTo 0 :recordedAt 6 :updatedAt 7)

fn problem e: m/Edge -> String
  (optionOr (g/edgeProblem e) "")

fn scopeOf pairs: (List (Pair String String)) -> (Map String String)
  (fold (fn [(a (Map String String)) (p (Pair String String))] -> (Map String String) (mapSet a (pairFirst p) (pairSecond p))) (mapEmpty) pairs)

; (:m :ref VS-VAULT :do "ports the automate graphTest vocabulary and edge rules: relations, roles as ids, weights 1..10000 inclusive, self-loop refused, outgoing and incoming, contradictions found from either end once")
fn testGraph -> Bool
  (let [(es (list (edge "pain-1" "ev-1" "contradicts" 9000) (edge "ev-1" "pain-1" "contradicts" 8000) (edge "pain-1" "aud-1" "grounds" 5000) (edge "aud-1" "pain-1" "refines" 4000)))]
    (do
      (assert (= (listLength (m/relations)) 4) "four closed edge relations")
      (assert (listAll? m/validRelation? (m/relations)) "every listed relation validates")
      (assert (and (m/validRelation? "grounds") (and (m/validRelation? "contradicts") (and (m/validRelation? "refines") (m/validRelation? "derivesFrom")))) "grounds contradicts refines derivesFrom valid")
      (assert (not (m/validRelation? "Grounds")) "relation comparison is case-sensitive")
      (assert (not (m/validRelation? "supports")) "unknown relation rejected")
      (assert (not (m/validRelation? "")) "empty relation rejected")
      (assert (= (listLength (m/statuses)) 6) "six statuses")
      (assert (and (m/validStatus? "pinned") (not (m/validStatus? "Pinned"))) "status comparison is case-sensitive")
      (assert (and (m/validOutcome? "nuance") (not (m/validOutcome? "maybe"))) "outcomes are the closed four")
      (assert (= (problem (edge "n1" "n1" "grounds" 5000)) "self-edge not allowed") "self-loop edge rejected")
      (assert (stringContains? (problem (edge "n1" "n2" "bogusRel" 5000)) "invalid relation") "invalid relation rejected")
      (assert (stringContains? (problem (edge "n1" "n2" "grounds" 0)) "weightBp") "weightBp 0 rejected")
      (assert (stringContains? (problem (edge "n1" "n2" "grounds" 10001)) "weightBp") "weightBp 10001 rejected")
      (assert (and (none? (g/edgeProblem (edge "n1" "n2" "grounds" 1))) (none? (g/edgeProblem (edge "n1" "n2" "grounds" 10000)))) "boundary weights 1 and 10000 accepted")
      (assert (stringContains? (problem (edge "" "n2" "grounds" 5000)) "invalid fromId") "empty fromId rejected")
      (assert (stringContains? (problem (edge "bad/id" "n2" "grounds" 5000)) "invalid fromId") "slash in an id rejected so it cannot become a key segment")
      (assert (stringContains? (problem (edge "n1" "../x" "grounds" 5000)) "invalid toId") "path traversal id rejected")
      (assert (= (listLength (g/outgoingOf es "pain-1")) 2) "outgoingOf pain-1 finds 2 edges")
      (assert (= (listLength (g/incomingOf es "pain-1")) 2) "incomingOf pain-1 finds 2 edges")
      (assert (= (g/contradictionsOf es "pain-1") (list "ev-1")) "contradictionsOf pain-1 deduplicates bidirectional contradictions")
      (assert (= (g/contradictionsOf es "ev-1") (list "pain-1")) "contradictionsOf works from the other end")
      (assert (listEmpty? (g/contradictionsOf es "aud-1")) "contradictionsOf aud-1 is empty")
      (assert (= (g/neighbours es "pain-1") (list "ev-1" "aud-1")) "neighbours lists both directions once")
      (assert (= (m/edgeKey "a" "refines" "b") "a/refines/b") "edges are keyed from/relation/to")
      true))

; (:m :ref VS-VAULT :do "rows are canonical and strict: a round trip is byte identical, scope keys sort, quotes and newlines survive, and a missing field, a wrong shape, a wrong head, a bad status or trailing text is an error and never a default")
fn testRows -> Bool
  (let [(e (with (entry "e1" "pinned" (scopeOf (list (pair "zone" "b") (pair "channel" "a")))) :title "Q\"uote\nline\ttab \\ end"))
        (txt (m/emitEntry e))
        (back (m/parseEntry txt))
        (ed (edge "a" "b" "grounds" 77))
        (rs (m/Resolution :resolutionId "r1" :entryA "a" :entryB "b" :outcome "nuance" :note "n \"x\"" :resolvedAt 9 :state "done"))]
    (do
      (assert (= back (ok e)) "an entry survives emit and parse unchanged")
      (assert (= (m/emitEntry (match back ((ok x) x) ((err _) e))) txt) "emit after parse is byte identical")
      (assert (stringContains? txt ":scope ((\"channel\" \"a\") (\"zone\" \"b\"))") "scope keys are written sorted")
      (assert (not (stringContains? txt "\n")) "an entry row is a single line")
      (assert (= (m/parseEntry (m/emitEntry (with e :pending (m/emitEntry e)))) (ok (with e :pending (m/emitEntry e)))) "an entry carrying a whole pending payload survives emit and parse")
      (assert (m/sameOrigin e (with e :status "disputed" :supersededBy "x" :pending "p" :validTo 9 :updatedAt 99)) "sameOrigin ignores the fields that change after creation")
      (assert (not (m/sameOrigin e (with e :bodyHash "other"))) "sameOrigin tells a different body")
      (assert (not (m/sameOrigin e (with e :scope (mapSet (mapEmpty) "k" "v")))) "sameOrigin tells a different scope")
      (assert (= (m/parseEdge (m/emitEdge ed)) (ok ed)) "an edge survives emit and parse")
      (assert (= (m/parseResolution (m/emitResolution rs)) (ok rs)) "a resolution survives emit and parse")
      (assert (ok? (m/parseEntry (stringReplace txt ":priorityBp 100" ":priorityBp 100"))) "control: an untouched row parses")
      (assert (err? (m/parseEntry (stringReplace txt ":priorityBp 100" ""))) "a missing field is an error")
      (assert (err? (m/parseEntry (stringReplace txt ":priorityBp 100" ":priorityBp \"100\""))) "an integer written as a string is an error")
      (assert (err? (m/parseEntry (stringReplace txt ":tags (\"a\" \"b c\")" ":tags (1 2)"))) "a tag that is not a string is an error")
      (assert (err? (m/parseEntry (stringReplace txt ":status \"pinned\"" ":status \"bogus\""))) "a status outside the six is an error")
      (assert (err? (m/parseEntry (str txt " (:extra)"))) "trailing forms are an error")
      (assert (err? (m/parseEntry (stringReplace txt "(:entry" "(:edge"))) "a row of another kind is not read as an entry")
      (assert (err? (m/parseEntry "(:entry :entryId")) "truncated text is an error")
      (assert (err? (m/parseEdge (stringReplace (m/emitEdge ed) ":weightBp 77" ":weightBp x"))) "a non-integer weight is an error")
      (assert (err? (m/parseResolution (stringReplace (m/emitResolution rs) ":resolvedAt 9" ""))) "a resolution missing a field is an error")
      true))

; (:m :ref VS-VAULT :do "scope semantics of the generalised layers: an empty scope applies everywhere, every named key must hold the query's value, * matches any value, a key missing from the query fails")
fn testScope -> Bool
  (let [(glob (entry "g" "corroborated" (mapEmpty)))
        (ch (entry "c" "corroborated" (scopeOf (list (pair "channel" "ch-1")))))
        (star (entry "s" "corroborated" (scopeOf (list (pair "channel" "*")))))
        (two (entry "t" "corroborated" (scopeOf (list (pair "channel" "ch-1") (pair "audience" "a1")))))
        (q1 (scopeOf (list (pair "channel" "ch-1"))))
        (q2 (scopeOf (list (pair "channel" "ch-2"))))]
    (do
      (assert (and (m/scopeMatches? glob (mapEmpty)) (m/scopeMatches? glob q1)) "an empty scope applies to every query")
      (assert (and (m/scopeMatches? ch q1) (not (m/scopeMatches? ch q2))) "a named key must hold the query's value")
      (assert (not (m/scopeMatches? ch (mapEmpty))) "a key missing from the query does not match")
      (assert (and (m/scopeMatches? star q1) (m/scopeMatches? star q2)) "* matches any value of its key")
      (assert (m/scopeMatches? star (mapEmpty)) "* matches even a query that lacks the key, like the global brand layer of automate")
      (assert (not (m/scopeMatches? two q1)) "every key of the entry must hold, not just one")
      (assert (m/scopeMatches? two (mapSet q1 "audience" "a1")) "all keys held matches")
      (assert (and (m/entryActive? glob) (and (not (m/entryActive? (entry "x" "superseded" (mapEmpty)))) (not (m/entryActive? (entry "y" "quarantined" (mapEmpty)))))) "superseded and quarantined are out of play")
      (assert (m/entryActive? (entry "z" "disputed" (mapEmpty))) "disputed stays active")
      true))

; (:m :ref VS-VAULT :do "the pure curation rules, checked without a store: a pinned entry is not demoted to disputed, needsResearch keeps a contradiction open and acceptB closes it")
fn testCurateRules -> Bool
  (let [(a (entry "a" "pinned" (mapEmpty)))
        (b (entry "b" "corroborated" (mapEmpty)))
        (es (list a b))
        (edges (list (edge "a" "b" "contradicts" 9000) (edge "b" "a" "contradicts" 9000)))
        (rNeed (m/Resolution :resolutionId "r" :entryA "a" :entryB "b" :outcome "needsResearch" :note "" :resolvedAt 1 :state "done"))
        (rB (m/Resolution :resolutionId "r2" :entryA "b" :entryB "a" :outcome "acceptB" :note "" :resolvedAt 1 :state "done"))
        (marked (cu/linkMarks es "a" "b" 50))
        (accB (cu/resolveEntries es "a" "b" "acceptB" 60))]
    (do
      (assert (= (map (fn [(e m/Entry)] -> String e.status) marked) (list "pinned" "disputed")) "linkMarks disputes b and leaves the pinned a")
      (assert (= (listLength (cu/openContradictions es edges (list))) 1) "a contradicts pair listed in both directions is one open contradiction")
      (assert (= (listLength (cu/openContradictions es edges (list rNeed))) 1) "needsResearch leaves it open")
      (assert (= (listLength (cu/openContradictions es edges (list (with rB :state "pending")))) 1) "a pending resolution does not close anything")
      (assert (= (listLength (cu/openContradictions es edges (list rB))) 0) "an acceptB resolution on the reversed pair closes it")
      (assert (= (map (fn [(e m/Entry)] -> String e.status) accB) (list "superseded" "corroborated")) "acceptB supersedes a and corroborates b")
      (assert (= (map (fn [(e m/Entry)] -> String e.supersededBy) accB) (list "b" "")) "the demoted entry names the winner")
      (assert (= (map (fn [(e m/Entry)] -> Int64 e.validTo) accB) (list 60 0)) "the demoted entry stops being valid at the resolution time")
      (assert (= (cu/openContradictions (list (with (entry "a" "superseded" (mapEmpty)) :supersededBy "b") b) edges (list)) (list)) "a contradiction with an inactive end is not open")
      (assert (some? (cu/supersedeProblem es "a" "a")) "self supersede is a problem")
      (assert (some? (cu/supersedeProblem (list (with (entry "o" "superseded" (mapEmpty)) :supersededBy "n") (entry "n" "corroborated" (mapEmpty))) "o" "n")) "an already superseded old entry is a problem")
      (assert (some? (cu/supersedeProblem (list (entry "o" "corroborated" (mapEmpty)) (with (entry "n" "superseded" (mapEmpty)) :supersededBy "o")) "o" "n")) "a superseded new entry is a problem")
      (assert (none? (cu/supersedeProblem es "a" "b")) "a plain supersede between live entries is allowed")
      true))

fn runTests -> Bool
  (and (testGraph) (and (testRows) (and (testScope) (testCurateRules))))
