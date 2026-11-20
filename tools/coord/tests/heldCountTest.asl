(module asl-tools/coord/tests/heldCountTest
  :x [runTests]
  :i [(asl-tools/coord/conductor :a cd) (asl-tools/coord/store :a st) (asl-tools/fleet/run :a fr) (asl-tools/coord/tests/fixtures/pipeFix :a pf)])

; (:m :ref COND-HELD-COUNT-AS-MERGING :do "units held on a red base (merging with await baseRed:) are outside the :maxMerging cap: with a cap of 1 and two merging units, one of them held, a ready unit is admitted to writing; with neither held the same store holds the writer; bpNote! counts only the units outside the hold")
fn ctxOf dir: String -> cd/Ctx
  (cd/Ctx :dir dir :holder "heldCountTest" :ttlMs 600000 :maxWait 0 :maxSame 3 :stageSec 60 :maxDesc 50
          :launch (fn [(stage String) (u st/Task) (c cd/CUnit)] -> (List String) (list "/usr/bin/true")) :pace (cd/fixedPace 8 8))

fn ! stOf dir: String id: String -> String
  (match (listFind (fn [(c cd/CUnit)] -> Bool (= c.id id)) (cd/readCUnits! dir))
    ((some c) c.st)
    ((none) ""))

fn ! admitCase root: String name: String await: String -> String
  (let [(dir (str root "/" name))
        (_ (dirCreate root))
        (_ (dirCreate dir))
        (_ (map (fn [(id String)] -> Bool (ok? (st/put! dir (pf/unitIn id "true")))) (list "M1" "M2" "R1")))
        (_ (cd/writeCUnit! dir (pf/cuIn "M1" "merging" "" "")))
        (_ (cd/writeCUnit! dir (with (pf/cuIn "M2" "merging" "" "") :await await)))
        (_ (cd/writeCUnit! dir (pf/cuIn "R1" "ready" "" "")))
        (_ (fileWrite (str dir "/ladder.asn") "(:backpressure :maxMerging 1)\n"))
        (_ (cd/step! (ctxOf dir) (pf/unitIn "R1" "true") 8))]
    (stOf dir "R1"))

fn ! runTests -> Bool
  (let [(root (pf/scratch "heldCount" "w"))
        (_ (pf/cleanup root))
        (plain (admitCase root "plain" ""))
        (held (admitCase root "held" "baseRed:abc123456 train baseRed: a/aTest.asl"))
        (other (admitCase root "other" "solo"))
        (hu (with (pf/cuIn "H" "merging" "" "") :await "baseRed:abc train baseRed: x"))
        (mu (pf/cuIn "M" "merging" "" ""))
        (dir (str root "/vis"))
        (_ (dirCreate dir))
        (ctx (ctxOf dir))
        (_ (fileWrite (str dir "/ladder.asn") "(:backpressure :maxMerging 1)\n"))
        (note1 (cd/bpNote! ctx (list mu hu hu hu)))
        (j1 (resultOr (fileReadString (cd/journalPath dir)) ""))
        (_ (pf/cleanup root))
        (stubGone (fr/stubRemove!))]
    (do (assert (= plain "ready") (str "two merging over a cap of one hold the writer: " plain))
        (assert (= held "writing") (str "a unit held on a red base is outside the cap, so the writer is admitted: " held))
        (assert (= other "ready") (str "another await still counts as merging: " other))
        (assert (= (cd/mergingCount (list mu hu hu hu)) 1) "only the unit outside the hold is counted")
        (assert (not (cd/mergeHeld? 1 (list mu hu hu hu))) "one counted merging at a cap of one does not hold")
        (assert (cd/mergeHeld? 0 (list mu hu hu hu)) "and one counted merging over a cap of zero holds")
        (assert (and (= note1 "") (not (stringContains? j1 "(:bpHeld"))) (str "no hold, no bpHeld row: " note1 " " j1))
        (assert stubGone "the stand-in host dir of this run is removed")
        true))
