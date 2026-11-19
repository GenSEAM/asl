(module asl-tools/coord/tests/mergeWideTrainTest
  :x [runTests]
  :i [(asl-tools/coord/conductor :a cd) (asl-tools/coord/store :a st) (asl-tools/fleet/run :a fr) (asl-tools/coord/tests/fixtures/pipeFix :a pf)])

; (:m :ref MERGE-WIDE-TRAIN-STARVES :do "one wide train must not hold the merge stage: a train its limit killed parks its unit blocked await trainTimeout with an escalation, out of the merging count, and neither a moved base nor the blocked retry brings it back; the merging units that wait start their trains fewest merge outcomes first; redWake returns one unit to merging at most redWakeMax times; stores are scratch dirs under this worktree's .asl/cache and the train is a stub")

fn ctxFor root: String -> cd/Ctx
  (cd/Ctx :dir (str root "/store") :holder "mwtTest" :ttlMs 3600000 :maxWait 5 :maxSame 3 :stageSec 60 :maxDesc 50
          :launch (fn [(stage String) (u st/Task) (c cd/CUnit)] -> (List String) (list "/usr/bin/true")) :pace (cd/fixedPace 8 8))

fn n i: Int64 -> String
  (stringFromInt64 i)

fn ! cuNow root: String id: String -> cd/CUnit
  (optionOr (listFind (fn [(x cd/CUnit)] -> Bool (= x.id id)) (cd/readCUnits! (str root "/store"))) (pf/cuIn id "absent" "" ""))

fn resOf sig: String -> cd/Res
  (cd/Res :ok 0 :wt "" :branch "" :model "" :tokens 0 :costMicro 0 :claimedGreen 0 :sig sig :ms 0 :exit 1 :asserts 0 :verdict "fail" :tiers "")

; (:m :do "the unit merging with a live lease of the test's holder and no train started")
fn ! waiting! root: String id: String -> cd/CUnit
  (let [(store (str root "/store"))
        (c0 (cuNow root id))
        (epoch (if (> c0.epoch 0) c0.epoch (match (st/claim! store id "mwtTest" 3600000) ((ok t) (match (st/parseLease t) ((ok l) l.epoch) ((err _) 0))) ((err _) 0))))
        (c (with c0 :st "merging" :epoch epoch :launched 0))
        (_ (cd/writeCUnit! store c))]
    c)

; (:m :do "one merge result of the unit's running train")
fn ! fin! root: String u: st/Task sig: String -> cd/CUnit
  (let [(c (with (waiting! root u.id) :launched 1))
        (_ (cd/writeCUnit! (str root "/store") c))
        (_ (cd/finish! (ctxFor root) u c (resOf sig)))]
    (cuNow root u.id))

fn ! seeded! root: String id: String -> st/Task
  (let [(u (with (pf/unitIn id "true") :base "bx" :owns (list (str id ".txt"))))
        (_ (pf/seedUnit! root (pf/unitIn id "true") "merging" (str id ".txt")))
        (_ (st/put! (str root "/store") u))]
    u)

; (:m :do "the base branch gets one more commit; git is kept inside the scratch root")
fn ! bump! root: String -> Bool
  (stringContains? (pf/sh (str "cd " root "/repo && export GIT_CEILING_DIRECTORIES=" root " && git branch -f bx $(git commit-tree -m n -p bx 'bx^{tree}') && echo bumpOk")) "bumpOk")

fn ! rootFor name: String ladder: String -> String
  (let [(root (pf/scratch "mergeWideTrain" name))
        (_ (pf/cleanup root))
        (repo (pf/repoIn root))
        (_ (fileWrite (cd/repoPath (str root "/store")) repo))
        (made (pf/sh (str "cd " root "/repo && export GIT_CEILING_DIRECTORIES=" root " && git branch -f bx main && echo ok")))
        (_ (fileWrite (str root "/store/ladder.asn") ladder))]
    (if (and (not (stringEmpty? repo)) (stringContains? made "ok")) root ""))

; (:m :do "a red train, parked as unchanged, then the base moves and the blocked retry runs once")
fn ! redRound! root: String u: st/Task suite: String -> cd/CUnit
  (let [(_ (fin! root u (str "train red: asl/a/" suite ".asl")))
        (_ (bump! root))
        (_ (cd/retryBlocked! (ctxFor root) (list u)))]
    (cuNow root u.id))

fn ! tRows root: String id: String part: String -> (List String)
  (filter (fn [(l String)] -> Bool (and (stringStartsWith? l (str "(:t :unit " (st/q id) " ")) (stringContains? l part))) (pf/journalLines (str root "/store")))

fn ! escRows root: String id: String part: String -> (List String)
  (filter (fn [(l String)] -> Bool (and (stringStartsWith? l (str "(:escalate :unit " (st/q id) " ")) (stringContains? l part)))
          (stringLines (resultOr (fileReadString (cd/escalationsPath (str root "/store"))) "")))

fn kill -> String
  "killed: timeout after 10800 s :running 36 a.asl b.asl"

fn ! runTests -> Bool
  (let [; (:m :do "a: W had a red and a redWake, then its train is killed by the limit while A waits its turn")
        (ra (rootFor "a" "(:conductor :redNoRetry true)\n(:backpressure :maxMerging 1)\n"))
        (ctxA (ctxFor ra))
        (storeA (str ra "/store"))
        (uw (seeded! ra "W"))
        (w0 (redRound! ra uw "zeroTest"))
        (ua (seeded! ra "A"))
        (_ (waiting! ra "A"))
        (heldBefore (cd/mergeHeld? 1 (cd/readCUnits! storeA)))
        (w1 (fin! ra uw (kill)))
        (leaseW (resultOr (fileReadString (st/leasePath storeA "W")) ""))
        (cusAfter (cd/readCUnits! storeA))
        (_ (cd/tick! ctxA))
        (a1 (cuNow ra "A"))
        (_ (bump! ra))
        (wokeW (cd/retryBlocked! ctxA (list uw)))
        (w2 (cuNow ra "W"))
        (_ (cd/requeueOne! ctxA (list uw) "W"))
        (w3 (cuNow ra "W"))
        ; (:m :do "a merge stage its own deadline killed is the same outcome")
        (us (seeded! ra "S"))
        (s1 (fin! ra us "stage timeout after 60 s"))
        ; (:m :do "the key keeps the retry of before")
        (_ (fileWrite (str storeA "/ladder.asn") "(:conductor :redNoRetry true :trainTimeoutRetry true)\n"))
        (keyProblems (cd/ladderProblems storeA))
        (uk (seeded! ra "K"))
        (k1 (fin! ra uk (kill)))
        (tA (stringJoin (tRows ra "A" "") "|"))
        (tW (tRows ra "W" " :verdict \"trainTimeout: 10800 s, 36 suites still running\""))
        (eW (escRows ra "W" ":seen \"trainTimeout: 10800 s, 36 suites still running\""))
        (_ (pf/cleanup ra))
        ; (:m :do "b: M1 came back red twice, M2 and M3 never had a train; all three wait")
        (rb (rootFor "b" "(:conductor :redNoRetry true)\n"))
        (ctxB (ctxFor rb))
        (um1 (seeded! rb "M1"))
        (_ (redRound! rb um1 "alphaTest"))
        (m1w (redRound! rb um1 "betaTest"))
        (um2 (seeded! rb "M2"))
        (_ (waiting! rb "M2"))
        (um3 (seeded! rb "M3"))
        (_ (waiting! rb "M3"))
        (linesB (pf/journalLines (str rb "/store")))
        (triesB (map (fn [(id String)] -> String (n (cd/mergeCountIn linesB id "merge"))) (list "M1" "M2" "M3")))
        (fair (stringJoin (map (fn [(u st/Task)] -> String u.id) (cd/mergeFair! ctxB (list um1 um2 um3))) " "))
        (_ (cd/tick! ctxB))
        (m1 (cuNow rb "M1"))
        (m2 (cuNow rb "M2"))
        (m3 (cuNow rb "M3"))
        (_ (pf/cleanup rb))
        ; (:m :do "c: R is red at every new base, each time on another suite")
        (rc (rootFor "c" "(:conductor :redNoRetry true)\n"))
        (ctxC (ctxFor rc))
        (ur (seeded! rc "R"))
        (r1 (redRound! rc ur "alphaTest"))
        (r2 (redRound! rc ur "betaTest"))
        (r3 (redRound! rc ur "gammaTest"))
        (r4 (redRound! rc ur "deltaTest"))
        (wakes (listLength (tRows rc "R" " :to merging :stage redWake ")))
        (boundRows (tRows rc "R" " :verdict \"redWakeBound: 3 "))
        (boundEsc (escRows rc "R" "redWakeBound: 3 "))
        (_ (bump! rc))
        (woke5 (cd/retryBlocked! ctxC (list ur)))
        (r5 (cuNow rc "R"))
        (countBefore (cd/mergeCountIn (pf/journalLines (str rc "/store")) "R" "redWake"))
        (_ (cd/requeueOne! ctxC (list ur) "R"))
        (countAfter (cd/mergeCountIn (pf/journalLines (str rc "/store")) "R" "redWake"))
        (_ (pf/cleanup rc))
        (stubGone (fr/stubRemove!))]
    (do (assert (and (not (stringEmpty? ra)) (and (not (stringEmpty? rb)) (not (stringEmpty? rc)))) "fixture: three scratch repos with a base branch")
        (assert (and stubGone (listEmpty? (fr/stubDirsOwnedBy (procSelf)))) "the stand-in host dir of this run is removed")
        (assert (and (= w0.st "merging") (= w0.launched 0)) (str "fixture: W is back in merging after a red and a moved base: " w0.st))
        (assert heldBefore "fixture: two merging units over :maxMerging 1 hold the writers")
        (assert (and (= w1.st "blocked") (= w1.await "trainTimeout")) (str "a train its limit killed parks the unit: " w1.st " " w1.await))
        (assert (and (= w1.sig (kill)) (and (= w1.epoch 0) (stringEmpty? leaseW))) (str "it keeps the kill signature and drops its lease: " w1.sig " " leaseW))
        (assert (= w1.fails w0.fails) (str "no fail is charged: " (n w0.fails) " -> " (n w1.fails)))
        (assert (= (listLength tW) 1) (str "one transition names the limit and the unfinished suites: " (stringJoin tW "|")))
        (assert (= (listLength eW) 1) "one escalation row for the lead")
        (assert (= (cd/mergingCount cusAfter) 1) (str "the parked unit is not merging: " (n (cd/mergingCount cusAfter))))
        (assert (not (cd/mergeHeld? 1 cusAfter)) "back-pressure no longer holds the writers")
        (assert (and (= a1.st "merging") (= a1.launched 1)) (str "the next tick starts the other unit's train: " a1.st " " (n a1.launched) " " tA))
        (assert (= wokeW 0) "a moved base does not wake it")
        (assert (and (= w2.st "blocked") (= w2.await "trainTimeout")) (str "still parked after the base moved and the blocked retry ran: " w2.st " " w2.await))
        (assert (and (= w3.st "queued") (stringEmpty? w3.await)) (str "a requeue takes it back: " w3.st " " w3.await))
        (assert (and (= s1.st "blocked") (= s1.await "trainTimeout")) (str "a merge stage timeout parks the same way: " s1.st " " s1.await))
        (assert (listEmpty? keyProblems) (str ":trainTimeoutRetry is a valid conductor key: " (stringJoin keyProblems "; ")))
        (assert (and (= k1.st "merging") (and (= k1.fails 1) (stringEmpty? k1.await))) (str "with the key the kill is retried as before: " k1.st " " (n k1.fails) " " k1.await))
        (assert (and (= m1w.st "merging") (= m1w.launched 0)) (str "fixture: M1 waits in merging after two reds: " m1w.st))
        (assert (= (stringJoin triesB " ") "2 0 0") (str "merge outcomes so far: " (stringJoin triesB " ")))
        (assert (= fair "M2 M3 M1") (str "fresh units first, store order among equals: " fair))
        (assert (and (= m2.st "merging") (= m2.launched 1)) (str "the tick starts a fresh unit's train: " m2.st " " (n m2.launched)))
        (assert (and (= m1.st "merging") (= m1.launched 0)) (str "the unit with two reds waits: " m1.st " " (n m1.launched)))
        (assert (= m3.launched 0) "one train at a time")
        (assert (and (= r1.st "merging") (and (= r2.st "merging") (= r3.st "merging"))) (str "three redWakes go back to merging: " r1.st " " r2.st " " r3.st))
        (assert (and (= r4.st "blocked") (= r4.await "redWakeBound")) (str "the fourth parks the unit: " r4.st " " r4.await))
        (assert (= wakes 3) (str "three returns to merging journalled: " (n wakes)))
        (assert (= (listLength boundRows) 1) "one transition names the bound")
        (assert (= (listLength boundEsc) 1) "one escalation names the bound")
        (assert (and (= woke5 0) (and (= r5.st "blocked") (= r5.await "redWakeBound"))) (str "a later base move wakes nothing: " r5.st " " r5.await))
        (assert (and (= countBefore 3) (= countAfter 0)) (str "a requeue resets the count: " (n countBefore) " " (n countAfter)))
        true))
