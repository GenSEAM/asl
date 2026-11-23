(module asl-tools/coord/tests/depBlockWakeTest
  :x [runTests]
  :i [(asl-tools/coord/conductor :a cd) (asl-tools/coord/store :a st) (asl-tools/fleet/run :a fr) (asl-tools/coord/tests/fixtures/pipeFix :a pf)])

; (:m :ref DEP-BLOCK-WAKE :do "the dependency wait names its cause and wakes its unit: a queued unit whose :after unit is blocked blocks with the verdict escalated: depBlocked DEP (the dep's own signature); once no dependency is stalled depWake! queues it again, including a legacy unit blocked with the bare waitedOut deps signature, while a unit blocked for its own reason or a claim wait stays blocked")
fn ctxOf dir: String -> cd/Ctx
  (cd/Ctx :dir dir :holder "depBlockWakeTest" :ttlMs 600000 :maxWait 30 :maxSame 3 :stageSec 60 :maxDesc 50
          :launch (fn [(stage String) (u st/Task) (c cd/CUnit)] -> (List String) (list "/usr/bin/true")) :pace (cd/fixedPace 8 8))

fn ! readOr path: String -> String
  (resultOr (fileReadString path) "")

fn ! cuOf! dir: String id: String -> cd/CUnit
  (optionOr (listFind (fn [(c cd/CUnit)] -> Bool (= c.id id)) (cd/readCUnits! dir)) (pf/cuIn id "missing" "" ""))

fn unitAfter id: String after: (List String) -> st/Task
  (with (pf/unitIn id "true") :after after)

fn ! seed! dir: String u: st/Task c: cd/CUnit -> Bool
  (let [(_ (st/put! dir u))] (ok? (cd/writeCUnit! dir c)))

fn ! testDepBlockWake root: String -> Bool
  (let [(dir (str root "/dbw"))
        (_ (dirCreate root))
        (_ (dirCreate dir))
        (ctx (ctxOf dir))
        (_ (seed! dir (pf/unitIn "ROOT" "true") (with (pf/cuIn "ROOT" "blocked" "" "") :sig "trainDeadline: light :running 597")))
        (_ (seed! dir (unitAfter "DEP" (list "ROOT")) (with (pf/cuIn "DEP" "queued" "" "") :waited 30)))
        (_ (seed! dir (unitAfter "LEG" (list "ROOT")) (with (pf/cuIn "LEG" "blocked" "" "") :sig "waitedOut: deps not merged" :waited 31 :esc 1)))
        (_ (seed! dir (unitAfter "OWN" (list "ROOT")) (with (pf/cuIn "OWN" "blocked" "" "") :sig "merge failed" :waited 31)))
        (_ (seed! dir (unitAfter "CLM" (list "ROOT")) (with (pf/cuIn "CLM" "blocked" "" "") :sig "waitedOut: (:refused :why held)" :waited 31)))
        (units (resultOr (st/readUnits! dir) (list)))
        (_ (cd/step! ctx (optionOr (listFind (fn [(u st/Task)] -> Bool (= u.id "DEP")) units) (pf/unitIn "DEP" "true")) 8))
        (dep1 (cuOf! dir "DEP"))
        (journal (readOr (str dir "/journal.asn")))
        (idle (cd/depWake! ctx units))
        (_ (cd/writeCUnit! dir (with (cuOf! dir "ROOT") :st "merged" :sig "")))
        (woke (cd/depWake! ctx units))
        (dep2 (cuOf! dir "DEP"))
        (leg2 (cuOf! dir "LEG"))
        (own2 (cuOf! dir "OWN"))
        (clm2 (cuOf! dir "CLM"))]
    (do (assert (and (= dep1.st "blocked") (stringStartsWith? dep1.sig "waitedOut: ")) (str "the wait blocks the unit: " dep1.st " " dep1.sig))
        (assert (stringContains? journal ":verdict \"escalated: depBlocked ROOT (trainDeadline: light :running 597)\"") (str "the verdict names the dep and its reason: " journal))
        (assert (= idle 0) "while the dep is blocked nothing wakes")
        (assert (= woke 2) (str "once the dep merged the two dep waiters wake: " (stringFromInt64 woke)))
        (assert (and (= dep2.st "queued") (= leg2.st "queued")) (str "the named and the legacy bare waiter are queued again: " dep2.st " " leg2.st))
        (assert (and (= own2.st "blocked") (= own2.sig "merge failed")) (str "a unit blocked for its own reason stays blocked: " own2.st " " own2.sig))
        (assert (and (= clm2.st "blocked") (stringStartsWith? clm2.sig "waitedOut: (:refused")) (str "a claim wait stays blocked: " clm2.st " " clm2.sig))
        true))

fn ! runTests -> Bool
  (let [(root (pf/scratch "depBlockWake" "t"))
        (_ (pf/cleanup root))
        (_ (dirCreate root))
        (r (testDepBlockWake root))
        (_ (pf/cleanup root))]
    r)
