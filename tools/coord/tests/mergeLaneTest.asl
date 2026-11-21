(module asl-tools/coord/tests/mergeLaneTest
  :x [runTests]
  :i [(asl-tools/coord/conductor :a cd) (asl-tools/coord/store :a st) (asl-tools/fleet/run :a fr) (asl-tools/coord/tests/fixtures/pipeFix :a pf)])

; (:m :ref MERGE-LANES-DROPPED :do "what is left of the lanes work: a ladder row naming :lanes above 1 is valid and read as one lane with one journal row; units that share only grades.asn (merged by row) still ride in one batch beside a code file they do not share")
fn ctxOf dir: String -> cd/Ctx
  (cd/Ctx :dir dir :holder "mergeLaneTest" :ttlMs 600000 :maxWait 0 :maxSame 3 :stageSec 60 :maxDesc 50
          :launch (fn [(stage String) (u st/Task) (c cd/CUnit)] -> (List String) (list "/usr/bin/true")) :pace (cd/fixedPace 8 8))

fn ! cuOf dir: String id: String -> cd/CUnit
  (optionOr (listFind (fn [(c cd/CUnit)] -> Bool (= c.id id)) (cd/readCUnits! dir)) (pf/cuIn id "gone" "" ""))

fn ! testRows -> Bool
  (do (assert (listEmpty? (cd/trainErrors "(:train :lanes 2)")) "a lanes row is valid")
      (assert (listEmpty? (cd/trainErrors "(:train :jobs 6 :batch 3 :lanes 4)")) "lanes beside jobs and batch is valid")
      (assert (not (listEmpty? (cd/trainErrors "(:train :lanes 5)"))) "more than 4 lanes are rejected")
      (assert (= (cd/trainBatchOf "(:train :batch 3 :lanes 2)") 3) "the batch of a row with lanes is read")
      true)

; (:m :ref MERGE-LANES-DROPPED :do "lanes 2 in the ladder: lanesIgnored! journals one row, a second call adds none, and a row with no lanes or one lane journals nothing")
fn ! testIgnored root: String -> Bool
  (let [(dir (str root "/ign"))
        (_ (dirCreate root))
        (_ (dirCreate dir))
        (_ (fileWrite (str dir "/ladder.asn") "(:train :jobs 4)\n"))
        (none (cd/lanesIgnored! dir))
        (_ (fileWrite (str dir "/ladder.asn") "(:train :batch 2 :lanes 3)\n"))
        (first (cd/lanesIgnored! dir))
        (second (cd/lanesIgnored! dir))
        (rows (filter (fn [(l String)] -> Bool (stringStartsWith? l "(:lanesIgnored ")) (stringLines (resultOr (fileReadString (str dir "/journal.asn")) ""))))]
    (do (assert (not none) "no lanes row: nothing journalled")
        (assert (and first (not second)) "lanes 3: the first call journals, the second does not")
        (assert (= (listLength rows) 1) (str "one lanesIgnored row: " (stringJoin rows "|")))
        true))

; (:m :ref MERGE-LANES-DROPPED :do "H1 at batch planning: two units whose branches change different code files and the same .asl/mem/grades.asn (a row per reviewed branch, merged by row) ride in one train; a third sharing a code file with the leader does not")
fn ! testSharedBatch root: String -> Bool
  (let [(repo (pf/repoIn root))
        (store (str root "/store"))
        (u1 (pf/unitIn "G1" "true")) (u2 (pf/unitIn "G2" "true")) (u3 (pf/unitIn "G3" "true"))
        (w1 (pf/seedUnit! root u1 "merging" "g1.txt && mkdir -p .asl/mem && printf one > .asl/mem/grades.asn"))
        (w2 (pf/seedUnit! root u2 "merging" "g2.txt && mkdir -p .asl/mem && printf two > .asl/mem/grades.asn"))
        (w3 (pf/seedUnit! root u3 "merging" "g1.txt"))
        (_ (fileWrite (cd/repoPath store) repo))
        (_ (fileWrite (str store "/ladder.asn") "(:train :batch 3)\n"))
        (picked (cd/batchPlan! (ctxOf store) u1 (cuOf store "G1")))]
    (do (assert (and (not (stringEmpty? w1)) (and (not (stringEmpty? w2)) (not (stringEmpty? w3)))) "fixture: three unit branches")
        (assert (= picked (list "G2")) (str "G2 shares only grades.asn and rides, G3 shares g1.txt and does not: " (stringJoin picked ",")))
        true))

fn ! runTests -> Bool
  (let [(root (pf/scratch "mergeLane" "w"))
        (_ (pf/cleanup root))
        (_ (dirCreate root))
        (ign (testIgnored (str root "/ign")))
        (shared (testSharedBatch (str root "/shared")))
        (_ (pf/cleanup root))
        (stubGone (fr/stubRemove!))]
    (do (assert (testRows) "lanes row accepted")
        (assert ign "lanes above 1 are ignored with one journal row")
        (assert shared "a shared grades.asn does not keep batch members apart")
        (assert stubGone "the stand-in host dir of this run is removed")
        true))
