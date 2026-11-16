(module asl-tools/coord/tests/trainDeadlineTest
  :x [runTests]
  :i [(asl-tools/coord/conductor :a cd) (asl-tools/coord/store :a st) (asl-tools/coord/tests/fixtures/pipeFix :a pf)])

; (:m :ref MERGE-SPEED-COND :do "a tiered train's heavy phase counts for a kill's :running tail and progress, and a train ended by its phase deadline (:trainDeadline) charges no unit a fail: it retries while its unfinished suites fit the train limit and progress, else blocks await trainDeadline until the limit grows; solo and batch")

fn ctxFor root: String -> cd/Ctx
  (cd/Ctx :dir (str root "/store") :holder "deadlineTest" :ttlMs 3600000 :maxWait 5 :maxSame 3 :stageSec 60 :maxDesc 50
          :launch (fn [(stage String) (u st/Task) (c cd/CUnit)] -> (List String) (list "/usr/bin/true")) :pace (cd/fixedPace 8 8))

fn ! cuNow root: String id: String -> cd/CUnit
  (optionOr (listFind (fn [(x cd/CUnit)] -> Bool (= x.id id)) (cd/readCUnits! (str root "/store"))) (pf/cuIn id "absent" "" ""))

fn resOf sig: String verdict: String -> cd/Res
  (cd/Res :ok 0 :wt "" :branch "" :model "" :tokens 0 :costMicro 0 :claimedGreen 0 :sig sig :ms 0 :exit 1 :asserts 0 :verdict verdict :tiers "")

; (:m :do "the unit merging with a live lease, the fail count and signature of its last merge, then one merge result")
fn ! fin! root: String u: st/Task fails: Int64 prev: String res: cd/Res -> cd/CUnit
  (let [(store (str root "/store"))
        (c0 (cuNow root u.id))
        (epoch (if (> c0.epoch 0) c0.epoch (match (st/claim! store u.id "deadlineTest" 3600000) ((ok t) (match (st/parseLease t) ((ok l) l.epoch) ((err _) 0))) ((err _) 0))))
        (c (with c0 :st "merging" :epoch epoch :launched 1 :fails fails :sig prev :await ""))
        (_ (cd/writeCUnit! store c))
        (_ (cd/finish! (ctxFor root) u c res))]
    (cuNow root u.id))

fn ! seeded! root: String id: String -> st/Task
  (let [(u (pf/unitIn id "true"))
        (_ (pf/seedUnit! root u "merging" (str id ".txt")))]
    u)

fn ! attempt! root: String id: String sig: String out: String -> Bool
  (let [(store (str root "/store"))
        (tdir (cd/trainsDir store id))
        (_ (dirCreate (str store "/trains")))
        (_ (dirCreate tdir))]
    (ok? (fileWrite (str tdir "/000001.out")
                    (str "(:trainAttempt :unit " (st/q id) " :n 1 :branch " (st/q (str "sh/" id)) " :at 1 :exit 1 :ms 5 :verdict \"exit\" :sig " (st/q sig) ")\n" out))))

fn estimate estS: Int64 -> String
  (str "(:trainEstimate :tier (:estimateS " (n estS) " :heavyS 600 :deadlineFactorPct 150 :deadlineFloorS 300 :unknownS 60 :split true :light (:n 2 :estimateS 100 :deadlineS 300) :heavy (:n 2 :estimateS " (n (- estS 100)) " :deadlineS 900) :unrecorded 0))")

fn n i: Int64 -> String
  (stringFromInt64 i)

fn lightRows -> (List String)
  (list "(:trainRunning :items (\"a\" \"b\"))" "(:itemDone \"a\" 0)" "(:itemDone \"b\" 0)" "(:trainPhase :name \"light\" :ms 90000)")

fn deadlineOut estS: Int64 left: (List String) -> String
  (stringJoin (listAppend (cons (estimate estS) (lightRows))
                          (list "(:trainRunning :items (\"h1\" \"h2\"))" "(:itemDone \"h1\" 0)"
                                (str "(:trainDeadline :phase \"heavy\" :deadlineS 900 :elapsedS 950 :nextSuite \"h2\" :unstarted " (n (listLength left)) ")")
                                "(:trainPhase :name \"heavy\" :ms 950000)"
                                "(:train :head \"abc\" :merged \"def\" :branches (\"sh/D1\" \"sh/D2\") :changed 1 :selected 4 :cached 0 :ran 3 :green 3 :invariants 0 :red () :preexisting () :assertLoss () :baseKnown 0 :knownRed () :blocked (:fresh 0 :preexisting 0) :unrunN 1 :deadline (:unrun (\"h2\")) :seconds 990)"))
              "\n")

fn ! runTests -> Bool
  (let [(root (pf/scratch "trainDeadline" "w"))
        (_ (pf/cleanup root))
        (store (str root "/store"))
        (repo (pf/repoIn root))
        (_ (fileWrite (cd/repoPath store) repo))
        (ctx (ctxFor root))
        ; (:m :do "a kill in the heavy phase names the heavy suite it had not finished; a kill in the light phase counts the heavy tier not yet listed")
        (heavyKill (cd/trainSig (listAppend (cons (estimate 1000) (lightRows)) (list "(:trainRunning :items (\"h1\" \"h2\"))" "(:itemDone \"h1\" 0)" "(:fleetRun :verdict :timeout :timeoutMs 3600000)"))))
        (lightKill (cd/trainSig (list (estimate 1000) "(:trainRunning :items (\"a\" \"b\"))" "(:itemDone \"a\" 0)" "(:fleetRun :verdict :timeout :timeoutMs 3600000)")))
        (untiered (cd/heavyPending (list "(:trainEstimate :tier (:estimateS 50 :split false :light (:n 3 :estimateS 50 :deadlineS 300) :heavy (:n 0 :estimateS 0 :deadlineS 300)))")))
        (afterRerun (cd/stillRunning (list "(:trainRunning :items (\"a\"))" "(:itemDone \"a\" 0)" "(:trainRunning :items (\"x\"))")))
        ; (:m :do "the deadline row gives an infra signature with the unfinished tail")
        (out (deadlineOut 1001 (list "h2")))
        (sig (cd/trainSig (stringLines out)))
        (gate (cd/gateSig out))
        (bv (cd/batchVerdicts (list "sh/D1" "sh/D2") 1 out (list)))
        (bres (cd/batchRes "deadline" sig 7))
        (leftS (cd/deadlineLeftS out 1))
        ; (:m :do "solo: the unit's earlier fails stay, no new one is charged, the next train starts")
        (u1 (seeded! root "D1"))
        (_ (attempt! root "D1" sig out))
        (a1 (fin! root u1 2 "killed: timeout after 3600 s" (resOf sig "fail")))
        (j1 (stringJoin (filter (fn [(l String)] -> Bool (stringStartsWith? l "(:trainDeadline ")) (pf/journalLines store)) "|"))
        ; (:m :do "batch: a passenger result with the deadline verdict takes the same path")
        (u2 (seeded! root "D2"))
        (_ (attempt! root "D2" sig out))
        (a2 (fin! root u2 1 "rebatch: x" bres))
        (_ (st/release! store "D2" a2.epoch))
        ; (:m :do "the same deadline again with no fewer unfinished suites blocks await trainDeadline, still with no fail")
        (a3 (fin! root u1 2 sig (resOf sig "fail")))
        (lease3 (resultOr (fileReadString (st/leasePath store "D1")) ""))
        ; (:m :do "unfinished suites over the train limit block at once")
        (_ (fileWrite (str store "/ladder.asn") "(:train :limitS 600)\n"))
        (u4 (seeded! root "D4"))
        (bigOut (deadlineOut 8001 (list "h2")))
        (bigSig (cd/trainSig (stringLines bigOut)))
        (_ (attempt! root "D4" bigSig bigOut))
        (a4 (fin! root u4 1 "killed: timeout after 3600 s" (resOf bigSig "fail")))
        (note4 (resultOr (fileReadString (cd/deadlinePath store "D4")) ""))
        (stay4 (cd/retryBlocked! ctx (list u4)))
        (still4 (cuNow root "D4"))
        ; (:m :do "a larger limit that fits wakes it back to merging")
        (_ (fileWrite (str store "/ladder.asn") "(:train :limitS 3000)\n"))
        (stay1 (cd/retryBlocked! ctx (list u1)))
        (still1 (cuNow root "D1"))
        (woke4 (cd/retryBlocked! ctx (list u4)))
        (back4 (cuNow root "D4"))
        (_ (pf/cleanup root))]
    (do (assert (stringContains? heavyKill ":running 1 h2") (str "a heavy-phase kill names its unfinished heavy suite: " heavyKill))
        (assert (stringContains? lightKill ":running 3 b") (str "a light-phase kill counts the unlisted heavy tier: " lightKill))
        (assert (cd/progressed? lightKill heavyKill) "a heavy-phase kill after a light-phase kill is progress")
        (assert (= (cd/mergeFailsAfter lightKill 2 heavyKill) 2) "progress across phases charges no new fail")
        (assert (= untiered 0) "an untiered train has no pending heavy suites")
        (assert (= (stringJoin afterRerun "|") "") (str "a row after the main run that is not the heavy phase is not unfinished work: " (stringJoin afterRerun "|")))
        (assert (= sig "trainDeadline: heavy :running 1 h2") (str "the deadline signature: " sig))
        (assert (= gate sig) (str "gateSig takes the deadline signature: " gate))
        (assert (cd/deadlineSig? sig) "the signature reads as a deadline")
        (assert (= (stringJoin bv " ") "deadline deadline") (str "a batch deadline charges no member: " (stringJoin bv " ")))
        (assert (= bres.verdict "deadline") "the batch Res carries the deadline verdict")
        (assert (= leftS 251) (str "the unfinished share of the estimate, rounded up: " (n leftS)))
        (assert (= a1.st "merging") (str "solo deadline retries: " a1.st))
        (assert (= a1.fails 2) (str "solo deadline keeps the fail count: " (n a1.fails)))
        (assert (= a1.sig sig) "the unit carries the deadline signature")
        (assert (stringContains? j1 ":action retry :unit \"D1\" :why fits") (str "one retry row: " j1))
        (assert (= a2.st "merging") (str "batch deadline retries: " a2.st))
        (assert (= a2.fails 1) (str "batch deadline keeps the fail count: " (n a2.fails)))
        (assert (= a3.st "blocked") (str "a repeat without progress blocks: " a3.st))
        (assert (= a3.await "trainDeadline") (str "it waits on the deadline: " a3.await))
        (assert (= a3.fails 2) (str "the block charges no fail: " (n a3.fails)))
        (assert (stringEmpty? lease3) (str "the lease is dropped: " lease3))
        (assert (= a4.st "blocked") (str "unfinished suites over the limit block: " a4.st))
        (assert (= a4.fails 1) "the no-fit block charges no fail")
        (assert (stringContains? note4 ":why noFit :leftS 2001 :limitS 600") (str "the block note: " note4))
        (assert (= stay4 0) "the same limit does not wake it")
        (assert (= still4.st "blocked") "still blocked under the same limit")
        (assert (= woke4 1) "a larger limit wakes it")
        (assert (= back4.st "merging") (str "back to merging: " back4.st))
        (assert (> back4.epoch 0) "with its lease claimed again")
        (assert (= stay1 0) "a limit no larger than the one it was blocked under does not wake a unit whose suites fit")
        (assert (= still1.st "blocked") (str "the no-progress block stays: " still1.st))
        true))
