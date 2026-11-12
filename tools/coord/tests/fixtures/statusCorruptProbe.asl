(module asl-tools/coord/tests/fixtures/statusCorruptProbe
  :x [runTests]
  :i [(asl-tools/coord/conductor :a cd) (asl-tools/coord/store :a st) (asl-tools/fleet/run :a fr) (asl-tools/coord/tests/fixtures/pipeFix :a pf)])

; (:m :ref PIPE-GATES :do "PROBE, not a suite (not named *Test): status! on a store with one damaged conductor row; run with ./bin/asl test asl/tools/coord/tests/fixtures/statusCorruptProbe.asl, it fails while status! drops the unit")
fn ! runTests -> Bool
  (let [(root (pf/scratch "statusProbe" "g8"))
        (_ (pf/cleanup root))
        (dir (str root "/store"))
        (_ (st/put! dir (pf/unitIn "U1" "true")))
        (_ (st/put! dir (pf/unitIn "U2" "true")))
        (_ (cd/writeCUnit! dir (pf/cuIn "U1" "merged" "" "")))
        (_ (fileWrite (cd/cuPath dir "U2") "(:cu :id \"U2\" :st merged :lane\n"))
        (ctx (cd/Ctx :dir dir :holder "probe" :ttlMs 600000 :maxWait 0 :maxSame 3 :stageSec 60 :maxDesc 50 :launch (fn [(stage String) (u st/Task) (c cd/CUnit)] -> (List String) (list "true")) :pace (cd/fixedPace 4 4)))
        (status (cd/status! ctx))
        (_ (pf/cleanup root))]
    (do (assert (stringContains? status "U2") (str "status! reports the unit whose row is damaged: " status))
        true))
