(module asl-tools/coord/tests/storeCorruptTest
  :x [runTests]
  :i [(asl-tools/coord/conductor :a cd) (asl-tools/coord/store :a st) (asl-tools/fleet/run :a fr) (asl-tools/coord/tests/fixtures/pipeFix :a pf)])

; (:m :ref PIPE-GATES :do "G8: settled? on a temp store whose rows are damaged: a unit row that does not parse, a store row that does not parse and a store row with no conductor row are never settled, so a drain does not report a done run while a unit is unreadable; the healthy store is settled and status! lists every unit, so the damaged cases are measured against it")
fn ctxOf dir: String -> cd/Ctx
  (cd/Ctx :dir dir :holder "storeCorruptTest" :ttlMs 600000 :maxWait 0 :maxSame 3 :stageSec 60 :maxDesc 50
          :launch (fn [(stage String) (u st/Task) (c cd/CUnit)] -> (List String) (list "true")) :pace (cd/fixedPace 4 4))

fn ! seed! dir: String ids: (List String) -> Bool
  (let [(put (fn [(id String)] -> Bool
               (and (ok? (st/put! dir (pf/unitIn id "true")))
                    (ok? (cd/writeCUnit! dir (pf/cuIn id "merged" "" ""))))))]
    (listAll? put ids))

fn ! runTests -> Bool
  (let [(root (pf/scratch "storeCorrupt" "g8"))
        (_ (pf/cleanup root))
        (dir (str root "/store"))
        (seeded (seed! dir (list "U1" "U2" "U3")))
        (ctx (ctxOf dir))
        (okSettled (cd/settled? ctx))
        (okStatus (cd/status! ctx))
        (_ (fileWrite (cd/cuPath dir "U2") "(:cu :id \"U2\" :st merged :lane\n"))
        (rowBad (cd/settled? ctx))
        (_ (cd/writeCUnit! dir (pf/cuIn "U2" "merged" "" "")))
        (healedAgain (cd/settled? ctx))
        (_ (fileWrite (st/unitPath dir "U3") "(:unit :id \"U3\" :owns (\n"))
        (storeBad (cd/settled? ctx))
        (_ (st/put! dir (pf/unitIn "U3" "true")))
        (_ (st/put! dir (pf/unitIn "U4" "true")))
        (noCond (cd/settled? ctx))
        (_ (pf/cleanup root))]
    (do (assert seeded "fixture: three units in the store, each with a merged conductor row")
        (assert okSettled "control: a store of three merged units is settled")
        (assert (and (stringContains? okStatus ":id \"U1\"") (and (stringContains? okStatus ":id \"U2\"") (stringContains? okStatus ":id \"U3\""))) (str "control: status! lists every unit: " okStatus))
        (assert (not rowBad) "a conductor row that does not parse makes the store not settled")
        (assert healedAgain "control: the same row rewritten whole settles again, so the damage was the cause")
        (assert (not storeBad) "a store row that does not parse makes the store not settled")
        (assert (not noCond) "a store unit with no conductor row makes the store not settled")
        true))
