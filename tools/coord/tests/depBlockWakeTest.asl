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

; (:m :ref DEP-BLOCK-WAKE :do "the dep reason in a block verdict is clipped at 80 bytes on a character edge: a dep signature of 3-byte characters keeps 26 whole ones (78 bytes), never a half character")
fn ! testDepSigClip root: String -> Bool
  (let [(dir (str root "/clip"))
        (_ (dirCreate dir))
        (ctx (ctxOf dir))
        (long (fold (fn [(a String) (_ Int64)] -> String (str a "日")) "" (range 0 40)))
        (_ (seed! dir (pf/unitIn "RT" "true") (with (pf/cuIn "RT" "blocked" "" "") :sig long)))
        (_ (seed! dir (unitAfter "DP" (list "RT")) (with (pf/cuIn "DP" "queued" "" "") :waited 30)))
        (units (resultOr (st/readUnits! dir) (list)))
        (_ (cd/step! ctx (optionOr (listFind (fn [(u st/Task)] -> Bool (= u.id "DP")) units) (pf/unitIn "DP" "true")) 8))
        (verdict (cd/depBlockWhy (unitAfter "DP" (list "RT")) (cd/readCUnits! dir)))
        (clipped (optionOr (listHead (stringSplit (optionOr (listGet (stringSplit verdict "depBlocked RT (") 1) "") ")")) ""))
        (journal (readOr (str dir "/journal.asn")))]
    (do (assert (= (stringLength clipped) 78) (str "a 120-byte multibyte dep sig is clipped to 78 bytes, not 80: " (stringFromInt64 (stringLength clipped))))
        (assert (stringContains? journal (str "depBlocked RT (" clipped ")")) "the journal verdict carries the whole-character clip")
        true))

; (:m :ref CLAIMWAIT-WAKE :do "claim-wait blocks wake through retryBlocked: a store lock or an I/O error, and an after refusal whose dep is merged in cond, which marks the store row done; a dep not merged, and a hold past the retry cap, stay blocked")
fn claimUnit! dir: String id: String sig: String -> Bool
  (seed! dir (pf/unitIn id "true") (with (pf/cuIn id "blocked" "" "") :sig sig :waited 31 :esc 1))

fn ! testClaimWait root: String -> Bool
  (let [(dir (str root "/cw"))
        (_ (dirCreate dir))
        (ctx (ctxOf dir))
        (_ (seed! dir (pf/unitIn "DM" "true") (pf/cuIn "DM" "merged" "" "")))
        (_ (seed! dir (pf/unitIn "DB" "true") (with (pf/cuIn "DB" "blocked" "" "") :sig "merge failed")))
        (_ (claimUnit! dir "SL" "waitedOut: store lock: lock wait timed out"))
        (_ (claimUnit! dir "IO" "waitedOut: I/O error: No space left on device"))
        (_ (claimUnit! dir "AF" "waitedOut: (:refused :unit \"AF\" :why after :wait \"DM\")"))
        (_ (claimUnit! dir "AN" "waitedOut: (:refused :unit \"AN\" :why after :wait \"DB\")"))
        (_ (claimUnit! dir "OW" "waitedOut: merge failed"))
        (units (resultOr (st/readUnits! dir) (list)))
        (woke (cd/retryBlocked! ctx units))
        (rows (resultOr (st/readUnits! dir) (list)))
        (dm (optionOr (listFind (fn [(u st/Task)] -> Bool (= u.id "DM")) rows) (pf/unitIn "DM" "true")))
        (db (optionOr (listFind (fn [(u st/Task)] -> Bool (= u.id "DB")) rows) (pf/unitIn "DB" "true")))
        (sl (cuOf! dir "SL"))
        (io (cuOf! dir "IO"))
        (af (cuOf! dir "AF"))
        (an (cuOf! dir "AN"))
        (ow (cuOf! dir "OW"))
        (dirCap (str root "/cwcap"))
        (_ (dirCreate dirCap))
        (_ (fileWrite (str dirCap "/ladder.asn") "(:conductor :blockedRetryMax 0)\n"))
        (ctxCap (ctxOf dirCap))
        (_ (claimUnit! dirCap "SL" "waitedOut: store lock: lock wait timed out"))
        (_ (claimUnit! dirCap "HD" "waitedOut: (:refused :unit \"HD\" :why held :holder \"x\" :epoch 1)"))
        (capWoke (cd/retryBlocked! ctxCap (resultOr (st/readUnits! dirCap) (list))))]
    (do (assert (and (= sl.st "ready") (= io.st "ready")) (str "a store lock and an I/O error claim wait return to ready: " sl.st " " io.st))
        (assert (= af.st "ready") (str "a refusal after with its dep merged in cond/ returns to ready: " af.st))
        (assert (= dm.st "done") (str "the merged dep is marked done in the store: " dm.st))
        (assert (and (= an.st "blocked") (= db.st "queued")) (str "a dep that is not merged keeps the unit blocked and the store untouched: " an.st " " db.st))
        (assert (= ow.st "blocked") (str "a waitedOut with another reason stays blocked: " ow.st))
        (assert (= woke 3) (str "three woke: " (stringFromInt64 woke)))
        (assert (and (= capWoke 0) (= (cuOf! dirCap "SL").st "blocked") (= (cuOf! dirCap "HD").st "blocked")) "past the retry cap (0) a store lock and a held refusal stay blocked")
        true))

; (:m :ref READY-LANE-PARKED :do "writer admission decides, not the review lane table: a gateway text with a model row and two profiles, one whose chain holds an admitted model and one whose chain holds none, wired to tiers by (:writeProfiles) rows of the lanes file")
fn gwText ghostB: Bool -> String
  (str "(:gateway :models ((:model :id liveFree :provider p1)" (if ghostB " (:model :id ghostB :provider p2)" "") ")\n"
       "  :profiles ((:profile :id deadP :routes ((:intent any :chain (ghostA ghostB)))) (:profile :id goodP :routes ((:intent any :chain (ghostA liveFree))))))\n")

fn laneFiles! home: String lanes: String gateway: String -> Bool
  (let [(_ (dirCreate (str home "/.asl")))
        (_ (fileWrite lanes (str "(:reviewLanes :v 1 :lanes ((:lane :alias liveFree :tier strong :quality 5 :allowance 3)))\n(:writeProfiles :tier free :profiles (goodP))\n(:writeProfiles :tier strong :profiles (deadP))\n")))]
    (ok? (fileWrite (str home "/.asl/gateway.asn") gateway)))

fn ! testLaneParked root: String -> Bool
  (let [(dir (str root "/lp"))
        (home (str root "/lphome"))
        (lanes (str root "/lphome/lanes.asn"))
        (_ (dirCreate dir))
        (_ (dirCreate home))
        (_ (fileWrite (str dir "/ladder.asn") "(:dwell :ready 1)\n"))
        (_ (laneFiles! home lanes (gwText false)))
        (args (list "--repo" root "--home" home "--lanes" lanes))
        (ctx (cd/realCtx args dir (cd/realCfg args dir)))
        (_ (fileWrite (str dir "/restart") "(:restart :at 1 :untilMs 99999999999999)\n"))
        (_ (seed! dir (with (pf/unitIn "PK" "true") :channel "strong") (with (pf/cuIn "PK" "ready" "" "") :lane "strong" :since 1)))
        (_ (seed! dir (pf/unitIn "LV" "true") (with (pf/cuIn "LV" "ready" "" "") :since 1)))
        (_ (seed! dir (with (pf/unitIn "HD" "true") :owns (list "hd/x.asl")) (with (pf/cuIn "HD" "merging" "" "") :since 1)))
        (_ (st/claim! dir "HD" "h" 600000))
        (_ (seed! dir (with (pf/unitIn "OH" "true") :owns (list "hd/x.asl")) (with (pf/cuIn "OH" "ready" "" "") :since 1)))
        (_ (cd/dwellNote! ctx))
        (pk (cuOf! dir "PK"))
        (lv (cuOf! dir "LV"))
        (oh (cuOf! dir "OH"))
        (journal (readOr (str dir "/journal.asn")))
        (idle (cd/laneWake! ctx))
        (_ (laneFiles! home lanes (gwText true)))
        (_ (cd/tickRepo! ctx))
        (pk2 (cuOf! dir "PK"))
        (gw (gwText false))
        (lt "(:writeProfiles :tier free :profiles (goodP))\n(:writeProfiles :tier strong :profiles (deadP))\n(:writeProfile :tier paid :profile goodP)")]
    (do (assert (and (= pk.st "blocked") (= pk.sig "laneParked strong")) (str "a ready unit whose tier writer profile has no admitted model blocks named, though the lane table has a strong row: " pk.st " " pk.sig))
        (assert (stringContains? journal ":unit \"PK\" :st ready") "the dwell row is one row of the ready episode")
        (assert (stringContains? journal ":reason \"laneParked strong\"") "the dwell reason names the parked tier")
        (assert (and (= lv.st "ready") (stringContains? journal ":unit \"LV\" :st ready :since 1 :ageS") (stringContains? journal ":reason \"none\"")) (str "a ready unit whose writer profile has an admitted model stays ready, reason none: " lv.st))
        (assert (and (= oh.st "ready") (stringContains? journal ":reason \"ownsHeld HD\"")) (str "a ready unit behind a live lease names its holder: " oh.st))
        (assert (= idle 0) "no wake while the profile has no admitted model")
        (assert (and (= pk2.st "ready") (stringEmpty? pk2.sig)) (str "the real tick wakes the parked unit once the profile has an admitted model: " pk2.st " " pk2.sig))
        (assert (and (cd/tierLiveIn? gw lt "freeP" (list) "free") (not (cd/tierLiveIn? gw lt "freeP" (list) "strong")) (not (cd/tierLiveIn? gw lt "freeP" (list "liveFree") "free")) (cd/tierLiveIn? gw lt "freeP" (list) "paid") (cd/tierLiveIn? gw lt "freeP" (list) "other")) "a profile chain with an admitted alias is live, one without or whose alias is dead-listed is not, the paid row follows its profile, a non-tier name is never parked")
        (assert (and (cd/tierLiveIn? gw "" "liveFree" (list) "free") (not (cd/tierLiveIn? gw "" "ghostZ" (list) "free"))) "with no row the base profile decides, a bare admitted alias counting as its own chain")
        true))

; (:m :ref CLAIMWAIT-WAKE :do "claimWait is not an infra cause: under infraFree with :blockedRetryMax 2 a unit already retried twice stays blocked, since infra causes alone retry past the cap")
fn ! testClaimWaitCap root: String -> Bool
  (let [(dir (str root "/cwinf"))
        (_ (dirCreate dir))
        (_ (fileWrite (str dir "/ladder.asn") "(:conductor :infraFree true :blockedRetryMax 2)\n"))
        (ctx (ctxOf dir))
        (_ (claimUnit! dir "CP" "waitedOut: store lock: lock wait timed out"))
        (_ (fileWrite (str dir "/retries.asn") (str "(:retry :unit \"CP\" :why \"claimWait\" :n 1 :at 1)\n(:retry :unit \"CP\" :why \"claimWait\" :n 2 :at 2)\n")))
        (woke (cd/retryBlocked! ctx (resultOr (st/readUnits! dir) (list))))]
    (do (assert (and (= woke 0) (= (cuOf! dir "CP").st "blocked")) (str "a claimWait unit past :blockedRetryMax stays blocked under infraFree: " (cuOf! dir "CP").st))
        true))

; (:m :ref CLAIMWAIT-WAKE :do "the store write of an after wake waits for the retry to be admitted: a unit whose retry backoff has not passed leaves its merged dep not done")
fn ! testClaimWaitNoWrite root: String -> Bool
  (let [(dir (str root "/cwnw"))
        (_ (dirCreate dir))
        (ctx (ctxOf dir))
        (_ (seed! dir (pf/unitIn "DQ" "true") (pf/cuIn "DQ" "merged" "" "")))
        (_ (claimUnit! dir "AQ" "waitedOut: (:refused :unit \"AQ\" :why after :wait \"DQ\")"))
        (_ (fileWrite (str dir "/retries.asn") (str "(:retry :unit \"AQ\" :why \"claimWait\" :n 1 :at " (stringFromInt64 (/ (nowNs) 1000000)) ")\n")))
        (woke (cd/retryBlocked! ctx (resultOr (st/readUnits! dir) (list))))
        (dq (optionOr (listFind (fn [(u st/Task)] -> Bool (= u.id "DQ")) (resultOr (st/readUnits! dir) (list))) (pf/unitIn "DQ" "true")))]
    (do (assert (and (= woke 0) (= (cuOf! dir "AQ").st "blocked")) "inside the backoff the unit stays blocked")
        (assert (= dq.st "queued") (str "and the store row of the merged dep is not written: " dq.st))
        true))

fn ! runTests -> Bool
  (let [(root (pf/scratch "depBlockWake" "t"))
        (_ (pf/cleanup root))
        (_ (dirCreate root))
        (r0 (testDepBlockWake root))
        (r1 (testDepSigClip root))
        (r2 (testClaimWait root))
        (r3 (testLaneParked root))
        (r4 (testClaimWaitCap root))
        (r5 (testClaimWaitNoWrite root))
        (r (and r0 (and r1 (and r2 (and r3 (and r4 r5))))))
        (_ (pf/cleanup root))]
    r)
