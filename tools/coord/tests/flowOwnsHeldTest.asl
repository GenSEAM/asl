(module asl-tools/coord/tests/flowOwnsHeldTest
  :x [runTests]
  :i [(asl-tools/coord/conductor :a cd) (asl-tools/coord/store :a st) (asl-tools/fleet/run :a fr) (asl-tools/coord/tests/fixtures/pipeFix :a pf)])

; (:m :ref COND-NO-CLAIMS-0713 :do "node2 2026-11-23: with (:flow ... :newWhen always) four ready fix rounds whose :owns a merging unit's live lease held counted as owed slots, the new pass got 4 free slots minus 4 and no new unit was claimed for 2 h; a fix round the claim refuses on :owns holds no slot, so a new unit with free :owns is claimed")

fn ctxFor dir: String slots: Int64 -> cd/Ctx
  (cd/Ctx :dir dir :holder "flowOwnsHeldTest" :ttlMs 3600000 :maxWait 5 :maxSame 3 :stageSec 60 :maxDesc 50
          :launch (fn [(stage String) (u st/Task) (c cd/CUnit)] -> (List String) (list "/usr/bin/true")) :pace (cd/fixedPace slots slots))

fn ! cuNow dir: String id: String -> cd/CUnit
  (optionOr (listFind (fn [(x cd/CUnit)] -> Bool (= x.id id)) (cd/readCUnits! dir)) (pf/cuIn id "absent" "" ""))

fn ! unit! dir: String id: String owns: String c: cd/CUnit -> st/Task
  (let [(u (with (pf/unitIn id "true") :owns (list owns)))
        (_ (st/put! dir u))
        (_ (cd/writeCUnit! dir c))]
    u)

fn ! runTests -> Bool
  (let [(root (pf/scratch "flowOwnsHeld" "w"))
        (_ (pf/cleanup root))
        (dir (str root "/store"))
        (_ (dirCreate root))
        (_ (dirCreate dir))
        (_ (dirCreate (str dir "/tasks")))
        (ctx (ctxFor dir 2))
        (_ (fileWrite (str dir "/ladder.asn") "(:flow :order (merge gate review fix new) :newWhen always)\n"))
        (h (unit! dir "H1" "held.txt" (pf/cuIn "H1" "merging" "" "sh/H1")))
        (lease (st/claim! dir "H1" "flowOwnsHeldTest" 3600000))
        (f1 (unit! dir "F1" "held.txt" (pf/cuIn "F1" "ready" "" "sh/F1")))
        (f2 (unit! dir "F2" "held.txt" (pf/cuIn "F2" "ready" "" "sh/F2")))
        (n1 (unit! dir "N1" "free.txt" (pf/cuIn "N1" "ready" "" "")))
        (cus (cd/readCUnits! dir))
        (leases (filter (fn [(l st/Lease)] -> Bool (st/live? l (nowNs))) (resultOr (st/readLeases! dir) (list))))
        (blocked (map (fn [(u st/Task)] -> String u.id) (filter (fn [(u st/Task)] -> Bool (not (stringEmpty? (st/ownsClash u leases)))) (list f1 f2 n1))))
        (heldFix (cd/flowHeldIn ctx cus cus "fix"))
        (_ (cd/flowStep! ctx (list h f1 f2 n1) (cd/flowRowOf dir)))
        (afterF1 (cuNow dir "F1"))
        (afterN1 (cuNow dir "N1"))
        (_ (pf/cleanup root))
        (stubGone (fr/stubRemove!))]
    (do (assert (ok? lease) "the merging unit holds a live lease on held.txt")
        (assert (and (listContains? blocked "F1") (and (listContains? blocked "F2") (not (listContains? blocked "N1")))) (str "the fix rounds clash with the live lease, the new unit does not: " (stringJoin blocked ",")))
        (assert (listEmpty? heldFix) (str "a fix round whose :owns a live lease holds is not owed a slot: " (stringJoin heldFix ",")))
        (assert (= afterF1.st "ready") (str "the claim refuses the owns-held fix round, it stays ready: " afterF1.st))
        (assert (= afterN1.st "writing") (str "the new unit with free :owns takes a free slot: " afterN1.st))
        (assert stubGone "the stand-in host dir of this run is removed")
        true))
