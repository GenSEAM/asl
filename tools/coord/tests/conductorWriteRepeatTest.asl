(module asl-tools/coord/tests/conductorWriteRepeatTest
  :x [runTests]
  :i [(asl-tools/coord/conductor :a cd) (asl-tools/coord/store :a st) (asl-tools/fleet/run :a fr) (asl-tools/coord/tests/fixtures/pipeFix :a pf)])

; (:m :ref COND-WRITE-REPEAT-STOP :do "the same write stop (stop word and lastStep turn and op) three times in a row parks the unit across tier hops, which reset the fails count; another stop, a requeue or the (:writeRepeat :n N) row change the outcome")
fn ! scratch name: String -> String
  (str (resultOr (realPath ".") ".") "/.asl/cache/conductorWriteRepeatTest-" (stringFromInt64 (procSelf)) "/" name)

fn ! cleanup dir: String -> Unit
  (let [(_ (fr/runOneLimited (fr/job (list "rm" "-rf" dir) "." (fr/childEnv (list))) (fr/limits 60 4)))] ())

fn ctxIn dir: String -> cd/Ctx
  (cd/Ctx :dir dir :holder "conductorWriteRepeatTest" :ttlMs 600000 :maxWait 30 :maxSame 3 :stageSec 300 :maxDesc 50
          :launch (fn [(stage String) (u st/Task) (c cd/CUnit)] -> (List String) (list "none"))
          :pace (cd/fixedPace 0 0))

fn unitOn id: String lane: String -> cd/CUnit
  (cd/CUnit :id id :st "writing" :lane lane :fails 0 :sig "" :waited 0 :parked 0 :epoch 0 :branch "" :wt "" :model "" :tokens 0 :costMicro 0 :esc 0 :launched 1 :await "")

fn stopSig stop: String turn: Int64 -> String
  (str "(:agent :status :failed :receipt (:agentReceipt :status :failed :stop " stop " :lastStep (:turn " (stringFromInt64 turn) " :op \"gate\") :usage (:input 0)))")

fn hit j: String id: String -> Bool
  (stringContains? j (str "(:witness :unit " (st/q id) " "))

fn ! readOr p: String -> String
  (resultOr (fileReadString p) "")

fn ! fire ctx: cd/Ctx c: cd/CUnit sig: String -> cd/CUnit
  (cd/fail! ctx (with c :st "writing") "write" "m" sig 1)

fn ! testRepeat -> Bool
  (let [(dir (scratch "a"))
        (_ (cleanup dir))
        (_ (dirCreate dir))
        (ctx (ctxIn dir))
        (s (stopSig "gateIntegrity" 1))
        (o (stopSig "readStreak" 1))
        (a1 (fire ctx (unitOn "R1" "paid") s))
        (a2 (fire ctx a1 s))
        (a3 (fire ctx a2 s))
        (b1 (fire ctx (unitOn "R2" "paid") s))
        (b2 (fire ctx b1 s))
        (b3 (fire ctx b2 o))
        (c1 (fire ctx (unitOn "R3" "paid") s))
        (c2 (fire ctx c1 o))
        (c3 (fire ctx c2 s))
        (d1 (fire ctx (unitOn "R4" "paid") s))
        (d2 (fire ctx d1 s))
        (d3 (fire ctx d2 (stopSig "gateIntegrity" 2)))
        (j (readOr (str dir "/journal.asn")))
        (esc (readOr (str dir "/escalations.asn")))
        (_ (cleanup dir))]
    (do (assert (and (= a1.st "ready") (= a2.st "ready") (= a2.lane "strong")) (str "two stops still hop and retry: " a1.st " " a2.st " " a2.lane))
        (assert (and (= a3.st "blocked") (stringStartsWith? a3.sig "writeRepeat: 3x (:agent")) (str "the third identical stop parks across the hop: " a3.st " " a3.sig))
        (assert (and (hit j "R1") (and (stringContains? j "(:witness :unit \"R1\" :kind writeRepeat :n 3 :key \"stop gateIntegrity step :turn 1 :op \\\"gate\\\"\"") (stringContains? esc "(:escalate :unit \"R1\" :seen \"writeRepeat: 3x"))) "the park writes a witness row and an escalate row")
        (assert (not (cd/ladderHopSig? a3.sig)) "a writeRepeat park is no writer failure the ladder hops again")
        (assert (and (= b3.st "ready") (not (hit j "R2"))) (str "two equal stops and another one claim again: " b3.st))
        (assert (and (= c3.st "ready") (not (hit j "R3"))) (str "an other stop in between resets the run: " c3.st))
        (assert (and (= d3.st "ready") (not (hit j "R4"))) (str "the same stop at another turn is another signature: " d3.st))
        (assert (stringContains? j "tierHop paid->strong") "the fixture passed through the tier hop that reset the fail count")
        true))

fn ! testRow -> Bool
  (let [(dir (scratch "b"))
        (_ (cleanup dir))
        (_ (dirCreate dir))
        (_ (fileWrite (str dir "/ladder.asn") "(:writeRepeat :n 2)\n"))
        (ctx (ctxIn dir))
        (s (stopSig "gateIntegrity" 1))
        (a1 (fire ctx (unitOn "R5" "paid") s))
        (a2 (fire ctx a1 s))
        (_ (cleanup dir))]
    (do (assert (and (= a1.st "ready") (= a2.st "blocked") (stringStartsWith? a2.sig "writeRepeat: 2x")) (str "the row lowers the limit to 2: " a1.st " " a2.st " " a2.sig))
        (assert (and (= (cd/writeRepeatMax "(:writeRepeat :n 5)") 5) (= (cd/writeRepeatMax "") 3) (= (cd/writeRepeatMax "(:writeRepeat :n 0)") 3)) "row value, default 3, a rejected row falls back to 3")
        (assert (not (listEmpty? (cd/writeRepeatErrors "(:writeRepeat :n 2 :x 1)"))) "an unknown key is rejected")
        (assert (= (cd/writeStopKey "x :stop gateIntegrity :lastStep (:turn 1 :op \\\"gate\\\") y") "stop gateIntegrity step :turn 1 :op \"gate\"") "the key drops quoting backslashes")
        true))

fn ! bump! repo: String msg: String -> Bool
  (= (fr/runOneLimited (fr/job (list "git" "-C" repo "-c" "user.name=t" "-c" "user.email=t@t" "commit" "-q" "--allow-empty" "-m" msg) repo (fr/childEnv (list))) (fr/limits 60 4)).exit 0)

fn ! again ctx: cd/Ctx c: cd/CUnit -> Bool
  (cd/writeRepeatReturn! ctx c (stringLines (readOr (str ctx.dir "/journal.asn"))) (cd/writeRepeatHead! ctx))

fn ! testReturn -> Bool
  (let [(dir (scratch "c"))
        (_ (cleanup dir))
        (repo (pf/repoIn dir))
        (ok0 (not (stringEmpty? repo)))
        (_ (fileWrite (str dir "/repo.path") (str repo "\n")))
        (ctx (ctxIn dir))
        (s (stopSig "gateIntegrity" 1))
        (p1 (fire ctx (fire ctx (fire ctx (unitOn "R6" "paid") s) s) s))
        (same (again ctx p1))
        (c2 (bump! repo "two"))
        (back1 (again ctx p1))
        (q1 (fire ctx (with p1 :st "ready" :sig "" :esc 0 :fails 0) s))
        (c3 (bump! repo "three"))
        (back2 (again ctx q1))
        (q2 (fire ctx (with q1 :st "ready" :sig "" :esc 0 :fails 0) s))
        (c4 (bump! repo "four"))
        (back3 (again ctx q2))
        (j (readOr (str dir "/journal.asn")))
        (_ (cleanup dir))]
    (do (assert (and ok0 c2 c3 c4) "fixture: a temp repo with four commits")
        (assert (and (= p1.st "blocked") (stringContains? j ":kind writeRepeat :n 3 :key")) (str "parked first: " p1.st))
        (assert (not same) "the same head leaves the unit blocked")
        (assert back1 "a new head returns it to the queue once")
        (assert (and (= q1.st "blocked") (stringStartsWith? q1.sig "writeRepeat: 3x")) (str "the same stop on the new head parks it again after one failure, counter kept: " q1.st " " q1.sig))
        (assert back2 "a second new head returns it again")
        (assert (and (= q2.st "blocked") (not back3)) (str "the returns are used up (default 2): it stays blocked on a third new head: " q2.st))
        (assert (and (stringContains? j "(:writeRepeatReturn :unit \"R6\" ") (stringContains? j " :n 2 ")) "two return rows are journalled")
        (assert (and (= (cd/writeRepeatReturns "(:writeRepeat :n 3 :returns 1)") 1) (= (cd/writeRepeatReturns "(:writeRepeat :n 3)") 2) (= (cd/writeRepeatReturns "(:writeRepeat :n 3 :returns 101)") 2)) "the returns limit comes from the row, default 2, a rejected row falls back")
        (assert (not (listEmpty? (cd/writeRepeatErrors "(:writeRepeat :n 3 :returns -1)"))) "a negative returns limit is rejected")
        true))

; (:m :ref COND-WRITE-REPEAT-STOP :do "the blocked-unit pass itself (retryBlocked!) returns a parked unit on a new head and leaves it on the same head")
fn ! wireCase name: String move: Bool -> String
  (let [(dir (scratch name))
        (_ (cleanup dir))
        (repo (pf/repoIn dir))
        (_ (fileWrite (str dir "/repo.path") (str repo "\n")))
        (ctx (ctxIn dir))
        (_ (st/put! dir (pf/unitIn "R7" "true")))
        (_ (cd/writeCUnit! dir (with (pf/cuIn "R7" "writing" "" "") :lane "paid")))
        (s (stopSig "gateIntegrity" 1))
        (a1 (fire ctx (unitOn "R7" "paid") s))
        (a2 (fire ctx a1 s))
        (a3 (fire ctx a2 s))
        (_ (if move (bump! repo "two") true))
        (_ (cd/retryBlocked! ctx (resultOr (st/readUnits! dir) (list))))
        (now (optionOr (listFind (fn [(c cd/CUnit)] -> Bool (= c.id "R7")) (cd/readCUnits! dir)) a3))
        (_ (cleanup dir))]
    now.st)

fn ! testWire -> Bool
  (let [(same (wireCase "d" false))
        (moved (wireCase "e" true))]
    (do (assert (= same "blocked") (str "retryBlocked! leaves a writeRepeat park on the same head: " same))
        (assert (= moved "ready") (str "retryBlocked! returns it to the queue on a new head: " moved))
        true))

; (:m :ref COND-WRITE-REPEAT-STOP :do "the ladder survives: a model-dependent stop (readStreak at turn 12) climbs free to paid as on main and blocks only when the same key spans two rungs; provider and wallBudget never block here; the deterministic list may come from the row")
fn ! testLadder -> Bool
  (let [(dir (scratch "f"))
        (_ (cleanup dir))
        (_ (dirCreate dir))
        (ctx (ctxIn dir))
        (rs (stopSig "readStreak" 12))
        (f1 (fire ctx (unitOn "L1" "free") rs))
        (f2 (fire ctx f1 rs))
        (f3 (fire ctx f2 rs))
        (f4 (fire ctx f3 rs))
        (f5 (fire ctx f4 rs))
        (f6 (fire ctx f5 rs))
        (f7 (fire ctx f6 rs))
        (pv (stopSig "provider" 1))
        (v1 (fire ctx (unitOn "L3" "paid") pv))
        (v2 (fire ctx v1 pv))
        (v3 (fire ctx v2 pv))
        (wb (stopSig "wallBudget" 1))
        (w1 (fire ctx (unitOn "L4" "paid") wb))
        (w2 (fire ctx w1 wb))
        (w3 (fire ctx w2 wb))
        (j (readOr (str dir "/journal.asn")))
        (_ (cleanup dir))]
    (do (assert (and (= f3.st "ready") (= f3.lane "paid")) (str "three readStreak at turn 12 on free climb to paid as on main: " f3.st " " f3.lane))
        (assert (and (= f4.st "ready") (= f4.lane "paid") (= f5.st "ready") (= f5.lane "strong") (= f6.st "ready")) (str "the same key on free, paid and strong keeps climbing, no writeRepeat park: " f4.st " " f5.lane " " f6.st))
        (assert (and (= f7.st "blocked") (not (stringStartsWith? f7.sig "writeRepeat: ")) (not (hit j "L1"))) (str "it ends as the ordinary ladder ends, not as a writeRepeat park: " f7.st " " f7.sig))
        (assert (and (= v3.st "ready") (= v3.lane "strong") (not (hit j "L3"))) (str "provider stops never block here: " v3.st " " v3.lane))
        (assert (and (= w3.st "ready") (not (hit j "L4"))) (str "wallBudget stops never block here: " w3.st))
        (assert (and (cd/writeRepeatBlocks? "" "stop gateIntegrity step :turn 1 :op \"gate\"" 3) (not (cd/writeRepeatBlocks? "" "stop readStreak step :turn 12 :op \"read\"" 9)) (not (cd/writeRepeatBlocks? "" "stop readStreak step :turn 1 :op \"read\"" 9)) (not (cd/writeRepeatBlocks? "" "stop provider step :turn 1 :op \"gate\"" 9)) (not (cd/writeRepeatBlocks? "" "stop gateIntegrity step :turn 2 :op \"gate\"" 3)) (not (cd/writeRepeatBlocks? "" "stop gateIntegrity step :turn 1 :op \"gate\"" 2))) "blocking decision: only a listed stop at turn 1 at the limit, never readStreak or provider")
        (assert (and (cd/writeRepeatBlocks? "(:writeRepeat :n 3 :stops (customStop))" "stop customStop step :turn 1 :op \"x\"" 3) (not (cd/writeRepeatBlocks? "(:writeRepeat :n 3 :stops (customStop))" "stop gateIntegrity step :turn 1 :op \"x\"" 3))) "the stop list comes from the row")
        (assert (and (listEmpty? (cd/writeRepeatErrors "(:writeRepeat :n 3 :stops (a b))")) (not (listEmpty? (cd/writeRepeatErrors "(:writeRepeat :n 3 :stops ())"))) (not (listEmpty? (cd/writeRepeatErrors "(:writeRepeat :n 3 :stops)")))) "a stops list needs words")
        true))

; (:m :ref COND-WRITE-REPEAT-STOP :do "what ends a run: another key starts it again at one, a requeue or reload, a successful write; and a requeue or reload ends the count of returns")
fn ! rowAt dir: String id: String stage: String from: String to: String -> Bool
  (ok? (fileAppend (str dir "/journal.asn") (str "(:t :unit " (st/q id) " :from " from " :to " to " :stage " stage " :model \"m\" :tokens 0 :costUsd 0.000000 :verdict \"x\" :ms 1 :at 1)\n")))

fn ! testReset -> Bool
  (let [(dir (scratch "g"))
        (_ (cleanup dir))
        (_ (dirCreate dir))
        (ctx (ctxIn dir))
        (a (stopSig "gateIntegrity" 1))
        (b (stopSig "gateVacuous" 1))
        (o1 (fire ctx (fire ctx (fire ctx (unitOn "K1" "free") a) b) b))
        (rq0 (fire ctx (fire ctx (unitOn "K2" "free") a) a))
        (_ (rowAt dir "K2" "requeue" "blocked" "ready"))
        (rq (fire ctx rq0 a))
        (rl0 (fire ctx (fire ctx (unitOn "K3" "free") a) a))
        (_ (rowAt dir "K3" "reload" "blocked" "ready"))
        (rl (fire ctx rl0 a))
        (okw0 (fire ctx (fire ctx (unitOn "K4" "free") a) a))
        (_ (rowAt dir "K4" "write" "writing" "gating"))
        (okw (fire ctx okw0 a))
        (nostop (fire ctx (fire ctx (fire ctx (fire ctx (unitOn "K8" "free") a) a) "ERR_OTHER: no stop word here") a))
        (rr (list "(:writeRepeatReturn :unit \"K6\" :n 1)" "(:writeRepeatReturn :unit \"K6\" :n 2)"))
        (_ (cleanup dir))]
    (do (assert (= o1.st "ready") (str "A, B, B: another key restarts the run at one, so B has two, not three: " o1.st))
        (assert (= nostop.st "ready") (str "a failure without a stop word between identical stops ends the run: " nostop.st))
        (assert (= rq.st "ready") (str "a requeue row ends the run: " rq.st))
        (assert (= rl.st "ready") (str "a reload row ends the run: " rl.st))
        (assert (= okw.st "ready") (str "a unit that left writing without a failure starts the run again: " okw.st))
        (assert (and (= (cd/writeRepeatReturned rr "K6") 2) (= (cd/writeRepeatReturned (listAppend rr (list "(:t :unit \"K6\" :from blocked :to ready :stage requeue :x 1)")) "K6") 0) (= (cd/writeRepeatReturned (listAppend (listAppend rr (list "(:t :unit \"K6\" :from blocked :to ready :stage reload :x 1)")) (list "(:writeRepeatReturn :unit \"K6\" :n 1)")) "K6") 1) (= (cd/writeRepeatReturned (listAppend rr (list "(:t :unit \"K7\" :from blocked :to ready :stage requeue :x 1)")) "K6") 2)) "a requeue or reload of the unit zeroes its return count, another unit's row does not")
        true))

fn ! runTests -> Bool
  (and (testRepeat) (and (testRow) (and (testReturn) (and (testWire) (and (testLadder) (testReset))))))
