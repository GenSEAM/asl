(module asl-tools/coord/tests/deployWindowTest
  :x [runTests]
  :i [(asl-tools/coord/conductor :a cd) (asl-tools/coord/deployWindow :a dw) (asl-tools/coord/store :a st) (asl-tools/coord/tests/fixtures/pipeFix :a pf)])

; (:m :ref DEPLOY-WINDOW :do "the pending-deploy marker: a live marker holds the start of a train and of an admission, lets a stage that already runs and every other stage be, and an expired or unreadable marker holds nothing, so a dead deployer cannot freeze the queue")
fn ctxOf dir: String -> cd/Ctx
  (cd/Ctx :dir dir :holder "deployWindowTest" :ttlMs 600000 :maxWait 30 :maxSame 3 :stageSec 60 :maxDesc 50
          :launch (fn [(stage String) (u st/Task) (c cd/CUnit)] -> (List String) (list "/usr/bin/true")) :pace (cd/fixedPace 8 8))

fn ! now -> Int64
  (/ (nowNs) 1000000)

fn ! seed! dir: String id: String stateName: String launched: Int64 -> cd/CUnit
  (let [(c (with (pf/cuIn id stateName "" "") :launched launched :since 1))
        (_ (st/put! dir (pf/unitIn id "true")))
        (_ (cd/writeCUnit! dir c))]
    c)

fn ! runs dir: String -> Bool
  (fileExists? (str dir "/runs"))

fn ! testHold root: String -> Bool
  (let [(dir (str root "/hold"))
        (_ (dirCreate dir))
        (ctx (ctxOf dir))
        (m (seed! dir "M1" "merging" 0))
        (a (seed! dir "A1" "admitting" 0))
        (w (seed! dir "W1" "writing" 0))
        (_ (dirCreate (str dir "/runs")))
        (_ (dw/mark! dir "abc123" (now) 600000))
        (held (cd/launchNow! ctx (pf/unitIn "M1" "true") m))
        (heldA (cd/launchNow! ctx (pf/unitIn "A1" "true") a))]
    (do (assert (dw/live? dir (now)) "a fresh marker is live")
        (assert (and (cd/deployHeld? dir m) (cd/deployHeld? dir a)) "a pending marker holds a train start and an admission")
        (assert (not (cd/deployHeld? dir w)) "a writing stage is not held")
        (assert (and (= held.launched 0) (= heldA.launched 0) (not (fileExists? (cd/runPath dir "M1" "merge" "run")))) "the held units are not started")
        true))

fn ! testExpiry root: String -> Bool
  (let [(dir (str root "/expiry"))
        (_ (dirCreate dir))
        (m (seed! dir "M1" "merging" 0))
        (_ (fileWrite (str dir "/deployPending.asn") "garbage"))
        (junk (dw/live? dir (now)))
        (_ (dw/mark! dir "abc123" (- (now) 700000) 600000))
        (stale (dw/live? dir (now)))
        (held (cd/deployHeld? dir m))
        (_ (dw/mark! dir "abc123" (now) 600000))
        (_ (dw/clear! dir))]
    (do (assert (not stale) "a marker past its :untilMs is ignored")
        (assert (not junk) "an unreadable marker is ignored")
        (assert (not held) "an expired marker does not hold a train start")
        (assert (not (dw/live? dir (now))) "a cleared marker holds nothing")
        (assert (= (dw/shaOf "(:deploy :pending \"abc123\" :at 1 :untilMs 2)") "abc123") "the marker names its sha")
        true))

fn ! runTests -> Bool
  (let [(root (pf/scratch "deployWindow" "t"))
        (_ (pf/cleanup root))
        (_ (dirCreate root))
        (r0 (testHold root))
        (r1 (testExpiry root))
        (_ (pf/cleanup root))]
    (and r0 r1))
