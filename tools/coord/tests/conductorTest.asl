(module asl-tools/coord/tests/conductorTest
  :x [runTests]
  :i [(asl-tools/coord/conductor :a cd) (asl-tools/coord/store :a st) (asl-tools/fleet/run :a fr)])

; (:m :ref CONDUCTOR :do "every store dir is a scratch dir under this worktree's .asl/cache, never ~/.asl; stages are real detached children of a prepared native fixture binary (conductorStage.asl) whose write, review and merge are fakes and whose gates are the conductor's own; every child is deadline-bound by stageSec and killed by stopAll! at the end of its test")
fn ! scratch name: String -> String
  (str (resultOr (realPath ".") ".") "/.asl/cache/conductorTest-" (stringFromInt64 (procSelf)) "-" name)

fn ! cleanup dir: String -> Unit
  (let [(_ (fr/runOneLimited (fr/job (list "rm" "-rf" dir) "." (fr/childEnv (list))) (fr/limits 60 4)))] ())

fn ! fixtureBinary! -> String
  (let [(d (fr/runOneLimited (fr/job (list (fr/nativeCli!) "run" "asl/tools/nativeTest.asl" "prepare" "asl/tools/coord/tests/conductorStage.asl") "." (fr/childEnv (list)))
                             (fr/limits 600 64)))
        (lines (filter (fn [(l String)] -> Bool (stringStartsWith? l "/")) (map stringTrim (stringLines d.out))))]
    (if (= d.exit 0) (optionOr (listGet lines (- (listLength lines) 1)) "") ""))

fn greenGate -> String
  "echo '3 assertion(s) executed (3 passed)'"

fn redGate -> String
  "echo 'suite: ERR_TYPE boom in conductorTest'; echo 'FAIL 1 of 3'; exit 1"

fn task id: String owns: (List String) after: (List String) gate: String lane: String -> st/Task
  (st/Task :id id :owns owns :reads (list) :gate gate :channel lane :model "fake" :base "main" :after after :st "queued" :epoch 0 :receipt "")

fn noExtra stage: String id: String -> (List String)
  (list)

; (:m :do "extra: argv additions per stage and unit, the steering of the fixture")
fn ! ctxWith dir: String bin: String extra: (fn [String String] -> (List String)) tokens: Int64 perLane: Int64 maxWait: Int64 stageSec: Int64 -> cd/Ctx
  (cd/Ctx :dir dir :holder "conductorTest" :ttlMs 600000 :maxWait maxWait :maxSame 3 :stageSec stageSec :maxDesc 50
          :launch (fn [(stage String) (u st/Task) (c cd/CUnit)] -> (List String) (listAppend (list bin "stage" stage u.id "--store" dir) (extra stage u.id)))
          :pace (cd/fixedPace tokens perLane))

fn ! ctxOf dir: String bin: String tokens: Int64 perLane: Int64 maxWait: Int64 -> cd/Ctx
  (ctxWith dir bin noExtra tokens perLane maxWait 60)

fn ! journalLines dir: String -> (List String)
  (match (fileReadString (cd/journalPath dir)) ((ok t) (filter (fn [(l String)] -> Bool (not (stringEmpty? l))) (stringLines t))) ((err _) (list)))

fn ! tosOf dir: String id: String -> (List String)
  (map (fn [(l String)] -> String (optionOr (listHead (stringSplit (optionOr (listGet (stringSplit l ":to ") 1) "") " ")) ""))
       (filter (fn [(l String)] -> Bool (stringContains? l (str "(:t :unit \"" id "\" "))) (journalLines dir)))

fn ! posOf dir: String id: String to: String -> Int64
  (let [(lines (journalLines dir))]
    (optionOr (listFind (fn [(i Int64)] -> Bool (let [(l (optionOr (listGet lines i) ""))] (and (stringContains? l (str "(:t :unit \"" id "\" ")) (stringContains? l (str " :to " to " "))))) (range 0 (listLength lines))) -1))

fn ! fromCount dir: String from: String -> Int64
  (listLength (filter (fn [(l String)] -> Bool (stringContains? l (str " :from " from " "))) (journalLines dir)))

fn ! stOf dir: String id: String -> String
  (match (listFind (fn [(c cd/CUnit)] -> Bool (= c.id id)) (cd/readCUnits! dir)) ((some c) c.st) ((none) "absent"))

fn ! cuOf dir: String id: String -> cd/CUnit
  (optionOr (listFind (fn [(c cd/CUnit)] -> Bool (= c.id id)) (cd/readCUnits! dir)) (cd/CUnit :id "" :st "absent" :lane "" :fails -1 :sig "" :waited 0 :parked 0 :epoch 0 :branch "" :wt "" :model "" :tokens 0 :costMicro 0 :esc 0 :launched 0 :await ""))

fn ! tickUntil! ctx: cd/Ctx dir: String id: String st: String fails: Int64 max: Int64 -> Bool
  (let [(c (cuOf dir id))]
    (cond
      ((and (= c.st st) (= c.fails fails)) true)
      ((<= max 0) false)
      (else (let [(_ (cd/tick! ctx)) (_ (sleepMs 50))] (tickUntil! ctx dir id st fails (- max 1))))))

fn ! putAll! dir: String units: (List st/Task) -> Bool
  (listAll? (fn [(u st/Task)] -> Bool (ok? (st/put! dir u))) units)

fn ! readOr dir: String name: String -> String
  (resultOr (fileReadString (str dir "/" name)) "")

fn ! pidOf dir: String id: String stage: String -> Int64
  (match (cd/runRow dir id stage) ((some r) (pairFirst r)) ((none) -1))

fn ! up? pid: Int64 -> Bool
  (and (> pid 0) (resultOr (procAlive? pid) false))

; (:m :ref CONDUCTOR :do "a DAG A -> (B C) -> D drains to merged in dependency order, and each unit's journal is exactly the transition chain with the spend of its stages")
fn ! testDag bin: String -> Bool
  (let [(dir (scratch "dag"))
        (_ (cleanup dir))
        (put (putAll! dir (list (task "A" (list "p/a") (list) (greenGate) "leon") (task "B" (list "p/b") (list "A") (greenGate) "leon")
                                (task "C" (list "p/c") (list "A") (greenGate) "leon") (task "D" (list "p/d") (list "B" "C") (greenGate) "leon"))))
        (ctx (ctxOf dir bin 4 4 400))
        (ticks (cd/drain! ctx 600))
        (chain (list "ready" "writing" "gating" "awaitReview" "reviewing" "merging" "merged"))
        (a (cuOf dir "A"))
        (rows (resultOr (st/readUnits! dir) (list)))
        (tosA (tosOf dir "A")) (tosD (tosOf dir "D")) (stD (stOf dir "D"))
        (mA (posOf dir "A" "merged")) (mB (posOf dir "B" "merged")) (mC (posOf dir "C" "merged"))
        (wB (posOf dir "B" "writing")) (wC (posOf dir "C" "writing")) (wD (posOf dir "D" "writing"))
        (log (readOr dir "merged.log"))
        (_ (cleanup dir))]
    (do (assert put "four units put")
        (assert (= tosA chain) (str "A journal is the full transition chain: " (stringJoin tosA ",")))
        (assert (= tosD chain) (str "D journal is the full transition chain: " (stringJoin tosD ",")))
        (assert (= stD "merged") "D merged")
        (assert (and (< mA wB) (< mA wC)) "B and C start writing only after A is merged")
        (assert (and (< mB wD) (< mC wD)) "D starts writing only after both B and C are merged")
        (assert (and (stringStartsWith? log "A\n") (stringEndsWith? log "D\n") (stringContains? log "\nB\n") (stringContains? log "\nC\n")) (str "the merge stage saw A first, B and C between, D last: " log))
        (assert (and (= a.tokens 150) (= a.costMicro 3500)) (str "A spend is write plus review: " a.tokens " " a.costMicro))
        (assert (listAll? (fn [(u st/Task)] -> Bool (= u.st "done")) rows) "every store row is done after the merges")
        true))

; (:m :ref CONDUCTOR :do "units whose :owns overlap are serialised: the second does not leave ready before the first is merged; a disjoint third runs alongside")
fn ! testOwnsSerialised bin: String -> Bool
  (let [(dir (scratch "owns"))
        (_ (cleanup dir))
        (put (putAll! dir (list (task "X" (list "pkg/a") (list) (greenGate) "leon") (task "Y" (list "pkg/a/sub") (list) (greenGate) "leon") (task "Z" (list "pkg/z") (list) (greenGate) "leon"))))
        (ctx (ctxOf dir bin 4 4 400))
        (t1 (cd/tick! ctx))
        (t2 (cd/tick! ctx))
        (afterTwo (list (stOf dir "X") (stOf dir "Y") (stOf dir "Z")))
        (ticks (cd/drain! ctx 600))
        (mX (posOf dir "X" "merged")) (wY (posOf dir "Y" "writing")) (stY (stOf dir "Y")) (wZ (posOf dir "Z" "writing"))
        (_ (cleanup dir))]
    (do (assert put "three units put")
        (assert (= afterTwo (list "writing" "ready" "writing")) (str "after two ticks X and Z write, overlapping Y still waits: " (stringJoin afterTwo ",")))
        (assert (< mX wY) "Y starts writing only after X is merged")
        (assert (= stY "merged") "Y merges eventually")
        (assert (< wZ mX) "the disjoint Z did not wait for X")
        true))

; (:m :ref CONDUCTOR :do "admission = min(ready, capacity, lane allowance): capacity 1 admits only P; allowance 0 keeps S ready with capacity to spare; maxWait 0 proves a capacity wait never escalates (ADMITWAIT)")
fn ! admitted2 bin: String name: String tokens: Int64 slowAllow: Int64 -> (List String)
  (let [(dir (scratch name))
        (_ (cleanup dir))
        (put (putAll! dir (list (task "P" (list "p/p") (list) (greenGate) "leon") (task "Q" (list "p/q") (list) (greenGate) "leon") (task "S" (list "p/s") (list) (greenGate) "slow"))))
        (base (ctxOf dir bin tokens 5 50))
        (ctx (cd/Ctx :dir dir :holder "conductorTest" :ttlMs 600000 :maxWait 0 :maxSame 3 :stageSec 60 :maxDesc 50 :launch base.launch
                     :pace (cd/Pace :tokens (fn [] -> Int64 tokens) :allowance (fn [(lane String)] -> Int64 (if (= lane "slow") slowAllow 5)))))
        (t1 (cd/tick! ctx))
        (t2 (cd/tick! ctx))
        (afterTwo (list (stOf dir "P") (stOf dir "Q") (stOf dir "S")))
        (_ (cd/stopAll! ctx))
        (_ (cleanup dir))]
    afterTwo)

; (:m :ref DEPWAIT :do "a dependency in a stage or ready is no stall; a missing, blocked or failed one is")
fn cuSt id: String st: String -> cd/CUnit
  (cd/CUnit :id id :st st :lane "free" :fails 0 :sig "" :waited 0 :parked 0 :epoch 0 :branch "" :wt "" :model "" :tokens 0 :costMicro 0 :esc 0 :launched 0 :await "")

fn testDepStalled -> Bool
  (let [(u (task "T" (list "p/t") (list "D") (greenGate) "leon"))]
    (do (assert (not (cd/depStalled? u (list (cuSt "D" "writing")))) "a writing dependency is not a stall")
        (assert (not (cd/depStalled? u (list (cuSt "D" "ready")))) "a ready dependency is not a stall")
        (assert (cd/depStalled? u (list (cuSt "D" "blocked"))) "a blocked dependency is a stall")
        (assert (cd/depStalled? u (list (cuSt "X" "writing"))) "a missing dependency is a stall")
        true))

fn ! testAdmission bin: String -> Bool
  (let [(byTokens (admitted2 bin "admTok" 1 5))
        (byAllowance (admitted2 bin "admAllow" 9 0))]
    (do (assert (= byTokens (list "writing" "ready" "ready")) (str "one slot admits only P: " (stringJoin byTokens ",")))
        (assert (= byAllowance (list "writing" "writing" "ready")) (str "allowance 0 keeps S ready with slots to spare: " (stringJoin byAllowance ",")))
        true))

; (:m :ref CONDUCTOR :do "a gate failing with the same signature 3 times escalates once and blocks; the retries go back through ready")
fn ! testGateEscalates bin: String -> Bool
  (let [(dir (scratch "esc"))
        (_ (cleanup dir))
        (put (putAll! dir (list (task "G" (list "p/g") (list) (redGate) "leon"))))
        (ctx (ctxOf dir bin 4 4 400))
        (ticks (cd/drain! ctx 600))
        (g (cuOf dir "G"))
        (esc (readOr dir "escalations.asn"))
        (tos (tosOf dir "G"))
        (status (cd/status! ctx))
        (_ (cleanup dir))]
    (do (assert put "unit put")
        (assert (and (= g.st "blocked") (= g.fails 3)) (str "G blocked after 3 same-signature gate failures: " g.st " " (stringFromInt64 g.fails)))
        (assert (stringContains? g.sig "ERR_TYPE boom") (str "the signature carries the first ERR line: " g.sig))
        (assert (and (stringStartsWith? esc "(:escalate :unit \"G\" :seen \"ERR_TYPE boom") (= (listLength (stringSplit esc "(:escalate")) 2)) (str "exactly one escalate row naming the unit and the signature: " esc))
        (assert (stringContains? esc ":tried") "the escalate row says what was tried")
        (assert (= tos (list "ready" "writing" "gating" "ready" "writing" "gating" "ready" "writing" "gating" "blocked")) (str "failures retry through ready: " (stringJoin tos ",")))
        (assert (stringContains? status "(:blocked (\"G\"))") (str "status lists G blocked: " status))
        (assert (stringContains? status "(:escalations 1)") "status counts the escalation")
        true))

; (:m :ref CONDUCTOR :do "a different failure signature restarts the count: two failures with sig 1 then one with sig 2 do not escalate")
fn ! testSignatureReset bin: String -> Bool
  (let [(dir (scratch "sig"))
        (_ (cleanup dir))
        (put (putAll! dir (list (task "H" (list "p/h") (list) (redGate) "leon"))))
        (ctx (ctxOf dir bin 4 4 400))
        (reached (tickUntil! ctx dir "H" "ready" 2 600))
        (h1 (cuOf dir "H"))
        (swapped (st/put! dir (task "H" (list "p/h") (list) "echo 'suite: ERR_OTHER different'; exit 1" "leon")))
        (second (tickUntil! ctx dir "H" "ready" 1 600))
        (h2 (cuOf dir "H"))
        (_ (cd/stopAll! ctx))
        (_ (cleanup dir))]
    (do (assert (and reached (ok? swapped)) (str "H reached two failures and its gate was swapped: " (match swapped ((err e) e) ((ok _) ""))))
        (assert (and (= h1.fails 2) (not (= h1.st "blocked"))) (str "two same failures so far, not blocked: " h1.st " " (stringFromInt64 h1.fails)))
        (assert (and second (stringContains? h2.sig "ERR_OTHER")) (str "a new signature restarts the count at 1: " (stringFromInt64 h2.fails) " " h2.sig))
        true))

; (:m :ref CONDUCTOR :do "a review that defers (quota) parks the unit in awaitReview; ticks leave it there; wake of another lane does nothing; wake of its lane makes it reviewable and it merges")
fn ! testWake bin: String -> Bool
  (let [(dir (scratch "wake"))
        (_ (cleanup dir))
        (put (putAll! dir (list (task "W" (list "p/w") (list) (greenGate) "kimi"))))
        (marker (str dir "/deferred"))
        (extra (fn [(stage String) (id String)] -> (List String)
                 (if (= stage "review")
                   (if (fileExists? marker) (list) (let [(_ (fileWrite marker "1"))] (list "--verdict" "defer" "--tokens" "5" "--cost" "100")))
                   (list))))
        (ctx (ctxWith dir bin extra 4 4 400 60))
        (_ (cd/drain! ctx 600))
        (parked (cuOf dir "W"))
        (idle (cd/tick! ctx))
        (other (cd/wake! ctx "leon"))
        (still (cuOf dir "W"))
        (woken (cd/wake! ctx "kimi"))
        (ready (cuOf dir "W"))
        (_ (cd/drain! ctx 600))
        (done (cuOf dir "W"))
        (wakeLogged (stringContains? (stringJoin (journalLines dir) "\n") ":stage wake "))
        (_ (cleanup dir))]
    (do (assert put "unit put")
        (assert (and (= parked.st "awaitReview") (= parked.parked 1)) (str "deferred review parks W: " parked.st " " (stringFromInt64 parked.parked)))
        (assert (= (match idle ((ok c) c) ((err _) -1)) 0) "a tick over a parked unit changes nothing")
        (assert (and (= other 0) (= still.parked 1)) "waking another lane leaves W parked")
        (assert (and (= woken 1) (= ready.parked 0) (= ready.st "awaitReview")) (str "wake kimi unparks W for review: " (stringFromInt64 woken) " " (stringFromInt64 ready.parked)))
        (assert (= done.st "merged") (str "W merges after the wake: " done.st))
        (assert wakeLogged "the wake is journalled")
        true))

; (:m :ref CONDUCTOR :do "the writer's claim is never trusted: a writer reporting green with red gates is not merged, the merge stage is never started, and the unit ends blocked")
fn ! testWriterClaimIgnored bin: String -> Bool
  (let [(dir (scratch "claim"))
        (_ (cleanup dir))
        (put (putAll! dir (list (task "L" (list "p/l") (list) (redGate) "leon"))))
        (ctx (ctxWith dir bin (fn [(stage String) (id String)] -> (List String) (if (= stage "write") (list "--claim" "1") (list))) 4 4 400 60))
        (_ (cd/drain! ctx 600))
        (l (cuOf dir "L"))
        (lines (journalLines dir))
        (claimed (filter (fn [(x String)] -> Bool (stringContains? x ":verdict \"claimedGreen\"")) lines))
        (starts (readOr dir "starts.log"))
        (storeRows (resultOr (st/readUnits! dir) (list)))
        (tos (tosOf dir "L"))
        (_ (cleanup dir))]
    (do (assert put "unit put")
        (assert (not (listEmpty? claimed)) "the writer did claim green, journalled")
        (assert (not (= l.st "merged")) (str "L is not merged: " l.st))
        (assert (not (stringContains? starts "L merge")) (str "the merge stage was never started: " starts))
        (assert (and (listContains? tos "gating") (not (listContains? tos "awaitReview")) (not (listContains? tos "merging"))) (str "L was gated, never reviewed or merged: " (stringJoin tos ",")))
        (assert (listAll? (fn [(u st/Task)] -> Bool (not (= u.st "done"))) storeRows) "the store row is not done")
        true))

; (:m :ref CONDUCTOR-VACUOUS-GATE :do "a write whose unit gate already passed on the base is not proven by any edit: it blocks with one escalate row on the first write, no retry, no tier hop, never gated")
fn ! testVacuousBlocks bin: String -> Bool
  (let [(dir (scratch "vacuous"))
        (_ (cleanup dir))
        (put (putAll! dir (list (task "V" (list "p/v") (list) (greenGate) "free"))))
        (ctx (ctxWith dir bin (fn [(stage String) (id String)] -> (List String) (if (= stage "write") (list "--failsig" "vacuousGate: echo green") (list))) 4 4 400 60))
        (_ (cd/drain! ctx 600))
        (v (cuOf dir "V"))
        (esc (readOr dir "escalations.asn"))
        (tos (tosOf dir "V"))
        (_ (cleanup dir))]
    (do (assert put "unit put")
        (assert (= tos (list "ready" "writing" "blocked")) (str "V blocks on its first vacuous write: " (stringJoin tos ",")))
        (assert (= v.lane "free") (str "a vacuous gate does not hop tiers: " v.lane))
        (assert (stringStartsWith? esc "(:escalate :unit \"V\" :seen \"vacuousGate") (str "one escalate row names the vacuous gate: " esc))
        true))

; (:m :ref CONDUCTOR :do "a unit waiting on a dependency that never merges escalates after maxWait ticks and blocks")
fn ! testWaitEscalates bin: String -> Bool
  (let [(dir (scratch "wait"))
        (_ (cleanup dir))
        (put (putAll! dir (list (task "T" (list "p/t") (list "NOPE") (greenGate) "leon"))))
        (ctx (ctxOf dir bin 4 4 3))
        (_ (cd/drain! ctx 20))
        (t (cuOf dir "T"))
        (esc (readOr dir "escalations.asn"))
        (_ (cleanup dir))]
    (do (assert put "unit put")
        (assert (= t.st "blocked") (str "T blocked after waiting: " t.st))
        (assert (stringStartsWith? esc "(:escalate :unit \"T\" :seen \"deps not merged\"") (str "escalate row names the wait cause: " esc))
        true))

; (:m :ref CONDUCTOR :do "stages overlap: with 3 slots and 3 disjoint units whose write stage sleeps 3 s, the third tick still finds all three in writing, each with its own live child pid, and the journal has no unit leaving writing yet; then all three merge")
fn ! testParallel bin: String -> Bool
  (let [(dir (scratch "par"))
        (_ (cleanup dir))
        (put (putAll! dir (list (task "U1" (list "p/1") (list) (greenGate) "leon") (task "U2" (list "p/2") (list) (greenGate) "leon") (task "U3" (list "p/3") (list) (greenGate) "leon"))))
        (ctx (ctxWith dir bin (fn [(stage String) (id String)] -> (List String) (if (= stage "write") (list "--sleep" "3000") (list))) 3 3 400 60))
        (t1 (cd/tick! ctx))
        (t2 (cd/tick! ctx))
        (t3 (cd/tick! ctx))
        (states (list (stOf dir "U1") (stOf dir "U2") (stOf dir "U3")))
        (p1 (pidOf dir "U1" "write")) (p2 (pidOf dir "U2" "write")) (p3 (pidOf dir "U3" "write"))
        (live (list (up? p1) (up? p2) (up? p3)))
        (left (fromCount dir "writing"))
        (_ (cd/drain! ctx 600))
        (final (list (stOf dir "U1") (stOf dir "U2") (stOf dir "U3")))
        (_ (cd/stopAll! ctx))
        (_ (cleanup dir))]
    (do (assert put "three units put")
        (assert (= states (list "writing" "writing" "writing")) (str "all three are in writing at the third tick: " (stringJoin states ",")))
        (assert (and (!= p1 p2) (and (!= p2 p3) (!= p1 p3)) (> p1 0)) (str "three distinct child pids: " (stringFromInt64 p1) " " (stringFromInt64 p2) " " (stringFromInt64 p3)))
        (assert (= live (list true true true)) "all three children are alive at once")
        (assert (= left 0) "no unit has left writing in the journal yet")
        (assert (= final (list "merged" "merged" "merged")) (str "all three merge: " (stringJoin final ",")))
        true))

; (:m :ref CONDUCTOR :do "a stage child killed from outside is a failed stage with a signature and the unit retries through ready")
fn ! testKilledChild bin: String -> Bool
  (let [(dir (scratch "kill"))
        (_ (cleanup dir))
        (put (putAll! dir (list (task "K" (list "p/k") (list) (greenGate) "leon"))))
        (ctx (ctxWith dir bin (fn [(stage String) (id String)] -> (List String) (if (= stage "write") (list "--sleep" "30000") (list))) 2 2 400 60))
        (_ (cd/tick! ctx))
        (_ (cd/tick! ctx))
        (pid (pidOf dir "K" "write"))
        (aliveBefore (up? pid))
        (_ (fr/killTree! pid))
        (failed (tickUntil! ctx dir "K" "ready" 1 200))
        (k (cuOf dir "K"))
        (_ (cd/stopAll! ctx))
        (_ (cleanup dir))]
    (do (assert put "unit put")
        (assert aliveBefore "the write child was alive before the kill")
        (assert failed (str "K failed once and is back in ready: " k.st " " (stringFromInt64 k.fails)))
        (assert (stringContains? k.sig "stage died") (str "the signature says the stage died: " k.sig))
        true))

; (:m :ref CONDUCTOR :do "a stage child past its deadline is killed with its tree and fails with a timeout signature")
fn ! testStageTimeout bin: String -> Bool
  (let [(dir (scratch "tmo"))
        (_ (cleanup dir))
        (put (putAll! dir (list (task "O" (list "p/o") (list) (greenGate) "leon"))))
        (ctx (ctxWith dir bin (fn [(stage String) (id String)] -> (List String) (if (= stage "write") (list "--sleep" "30000") (list))) 2 2 400 1))
        (_ (cd/tick! ctx))
        (_ (cd/tick! ctx))
        (pid (pidOf dir "O" "write"))
        (failed (tickUntil! ctx dir "O" "ready" 1 200))
        (o (cuOf dir "O"))
        (gone (not (up? pid)))
        (_ (cd/stopAll! ctx))
        (_ (cleanup dir))]
    (do (assert put "unit put")
        (assert failed (str "O failed once: " o.st " " (stringFromInt64 o.fails)))
        (assert (stringContains? o.sig "stage timeout") (str "timeout signature: " o.sig))
        (assert gone "the timed-out child is dead")
        true))

; (:m :ref CONDUCTOR :do "a restarted conductor resumes from the store rows: a fresh Ctx after the write child was started finishes the unit without starting the stage again")
fn ! testResume bin: String -> Bool
  (let [(dir (scratch "res"))
        (_ (cleanup dir))
        (put (putAll! dir (list (task "R" (list "p/r") (list) (greenGate) "leon"))))
        (extra (fn [(stage String) (id String)] -> (List String) (if (= stage "write") (list "--sleep" "1500") (list))))
        (ctx1 (ctxWith dir bin extra 2 2 400 60))
        (_ (cd/tick! ctx1))
        (_ (cd/tick! ctx1))
        (mid (cuOf dir "R"))
        (pidMid (pidOf dir "R" "write"))
        (ctx2 (ctxWith dir bin extra 2 2 400 60))
        (_ (cd/drain! ctx2 600))
        (r (cuOf dir "R"))
        (starts (readOr dir "starts.log"))
        (tos (tosOf dir "R"))
        (_ (cd/stopAll! ctx2))
        (_ (cleanup dir))]
    (do (assert put "unit put")
        (assert (and (= mid.st "writing") (= mid.launched 1) (> pidMid 0)) (str "the first conductor left R writing with a child: " mid.st " " (stringFromInt64 pidMid)))
        (assert (= r.st "merged") (str "the second conductor finished R: " r.st))
        (assert (= (listLength (stringSplit starts "R write")) 2) (str "the write stage started exactly once: " starts))
        (assert (= tos (list "ready" "writing" "gating" "awaitReview" "reviewing" "merging" "merged")) (str "one clean chain: " (stringJoin tos ",")))
        true))

; (:m :ref CONDUCTOR :do "capacity counts the units already in flight: with 2 slots and 3 disjoint units, ticks after the first admission leave the third in ready until a slot frees, then all three merge")
fn ! testCapacity bin: String -> Bool
  (let [(dir (scratch "cap"))
        (_ (cleanup dir))
        (put (putAll! dir (list (task "V1" (list "p/1") (list) (greenGate) "leon") (task "V2" (list "p/2") (list) (greenGate) "leon") (task "V3" (list "p/3") (list) (greenGate) "leon"))))
        (ctx (ctxWith dir bin (fn [(stage String) (id String)] -> (List String) (if (= stage "write") (list "--sleep" "2000") (list))) 2 9 400 60))
        (t1 (cd/tick! ctx))
        (t2 (cd/tick! ctx))
        (t3 (cd/tick! ctx))
        (t4 (cd/tick! ctx))
        (states (list (stOf dir "V1") (stOf dir "V2") (stOf dir "V3")))
        (_ (cd/drain! ctx 600))
        (final (list (stOf dir "V1") (stOf dir "V2") (stOf dir "V3")))
        (_ (cd/stopAll! ctx))
        (_ (cleanup dir))]
    (do (assert put "three units put")
        (assert (= states (list "writing" "writing" "ready")) (str "two slots in flight, the third waits: " (stringJoin states ",")))
        (assert (= final (list "merged" "merged" "merged")) (str "all three merge in the end: " (stringJoin final ",")))
        true))

; (:m :ref COND3 :do "a merge failure retries the merge, not the write; the journal row carries the reason; the same failure three times escalates; a merge that succeeds on the retry lands")
fn ! testMergeRetry bin: String -> Bool
  (let [(dirA (scratch "mergeA"))
        (dirB (scratch "mergeB"))
        (_ (cleanup dirA))
        (_ (cleanup dirB))
        (ex (fn [(n String)] -> (fn [String String] -> (List String)) (fn [(stage String) (id String)] -> (List String) (if (= stage "merge") (list "--mergefail" n "--failsig" "train red: suite X exit 1") (list)))))
        (_ (putAll! dirA (list (task "M" (list "p/m") (list) (greenGate) "leon"))))
        (_ (putAll! dirB (list (task "M" (list "p/m") (list) (greenGate) "leon"))))
        (ctxA (ctxWith dirA bin (ex "9") 4 4 400 60))
        (ctxB (ctxWith dirB bin (ex "1") 4 4 400 60))
        (_ (cd/drain! ctxA 800))
        (_ (cd/drain! ctxB 800))
        (a (cuOf dirA "M"))
        (b (cuOf dirB "M"))
        (jA (stringJoin (journalLines dirA) "\n"))
        (startsA (readOr dirA "starts.log"))
        (startsB (readOr dirB "starts.log"))
        (_ (cleanup dirA))
        (_ (cleanup dirB))]
    (do (assert (and (= a.st "blocked") (= a.fails 3)) (str "M blocked after 3 merge failures: " a.st " " (stringFromInt64 a.fails)))
        (assert (stringContains? jA ":verdict \"retry: train red: suite X exit 1\"") (str "the journal keeps the merge reason: " jA))
        (assert (stringContains? jA ":verdict \"escalated: train red: suite X exit 1\"") "the escalation row keeps it too")
        (assert (= (listLength (filter (fn [(l String)] -> Bool (= l "M write")) (stringLines startsA))) 1) (str "the write ran once, not again after a merge failure: " startsA))
        (assert (= (listLength (filter (fn [(l String)] -> Bool (= l "M merge")) (stringLines startsA))) 3) "three merge starts")
        (assert (= b.st "merged") (str "a merge that fails once then succeeds lands: " b.st))
        (assert (= (listLength (filter (fn [(l String)] -> Bool (= l "M write")) (stringLines startsB))) 1) "one write")
        true))

; (:m :ref COND4 :do "a stage cost of -1 (unpriced) journals :priced false and adds nothing to the unit's spend; a priced cost adds and journals no marker")
fn ! testUnpriced bin: String -> Bool
  (let [(dir (scratch "unpriced"))
        (_ (cleanup dir))
        (ex (fn [(stage String) (id String)] -> (List String) (if (= stage "review") (list "--cost" "-1" "--tokens" "10") (list "--cost" "700"))))
        (_ (putAll! dir (list (task "C" (list "p/c") (list) (greenGate) "leon"))))
        (ctx (ctxWith dir bin ex 4 4 400 60))
        (_ (cd/drain! ctx 800))
        (c (cuOf dir "C"))
        (j (stringJoin (journalLines dir) "\n"))
        (_ (cleanup dir))]
    (do (assert (= c.st "merged") (str "C merged: " c.st))
        (assert (stringContains? j ":stage review :model \"fakeReviewer\" :tokens 10 :costUsd 0.000000 :priced false") (str "the unpriced review row says so: " j))
        (assert (= c.costMicro 700) (str "only the priced write counts: " (stringFromInt64 c.costMicro)))
        true))

fn offerExtra v: String t: String -> (fn [String String] -> (List String))
  (fn [(stage String) (id String)] -> (List String) (if (= stage "review") (list "--verdict" v "--tiers" (if (= id "K") "claude" t)) (list)))

fn strongSnap n: Int64 -> (fn [] -> (List (Pair String Int64)))
  (fn [] -> (List (Pair String Int64)) (list (pair "strong" n)))

; (:m :ref COND4 :do "the queue reads escalate :tiers: a unit blocked with (strong claude) is offered to the strong lane when that tier has allowance, goes back to awaitReview with a fresh lease and an offer the review consumes once, and merges after a pass; (claude) only rows and a strong tier without allowance leave the unit blocked")
fn ! testOfferStrong bin: String -> Bool
  (let [(dir (scratch "offer"))
        (_ (cleanup dir))
        (_ (putAll! dir (list (task "S" (list "p/s") (list) (greenGate) "leon") (task "K" (list "p/k") (list) (greenGate) "leon"))))
        (ctx1 (ctxWith dir bin (offerExtra "block" "strong claude") 4 4 400 60))
        (_ (cd/drain! ctx1 800))
        (s0 (cuOf dir "S"))
        (k0 (cuOf dir "K"))
        (rows (readOr dir "escalations.asn"))
        (none (cd/offerStrong! ctx1 (strongSnap 0)))
        (s1 (cuOf dir "S"))
        (one (cd/offerStrong! ctx1 (strongSnap 5)))
        (s2 (cuOf dir "S"))
        (k2 (cuOf dir "K"))
        (offerThere (fileExists? (cd/offerPath dir "S")))
        (ctx2 (ctxWith dir bin (offerExtra "pass" "") 4 4 400 60))
        (_ (cd/drain! ctx2 800))
        (s3 (cuOf dir "S"))
        (first (cd/offeredRung! dir "S"))
        (second (cd/offeredRung! dir "S"))
        (_ (cleanup dir))]
    (do (assert (and (= s0.st "blocked") (= k0.st "blocked")) "both units blocked by the review")
        (assert (and (stringContains? rows ":tiers (strong claude)") (stringContains? rows ":tiers (claude)")) (str "the rows carry their tiers: " rows))
        (assert (and (= none 0) (= s1.st "blocked")) "no strong allowance, no offer")
        (assert (= one 1) (str "one unit offered: " (stringFromInt64 one)))
        (assert (and (= s2.st "awaitReview") (> s2.epoch 0) offerThere) (str "S back in awaitReview with a lease and an offer: " s2.st))
        (assert (= k2.st "blocked") "the claude-only unit stays blocked")
        (assert (= s3.st "merged") (str "S merges after the strong review passes: " s3.st))
        (assert (and (= first "R3") (= second "")) (str "the offer starts the ladder at R3 once: " first "/" second))
        true))

; (:m :ref COND5 :do "the service cycle imports the plan ledger named in <store>/ledger.path: complete rows become units, a row without :owns is parked and written once as a (:need ...) escalation row (deduped over cycles), status lists it; no ledger.path means no import")
fn ! testIntake bin: String -> Bool
  (let [(dir (scratch "intake"))
        (_ (cleanup dir))
        (_ (dirCreate dir))
        (ledger (str dir "/plan.fixture.asn"))
        (_ (fileWrite ledger "(:u :id N1 :auto true :do \"new unit\" :owns (\"p/n1\") :gate \"echo '3 assertion(s) executed (3 passed)'\")\n(:u :id P1 :queue conductor :do \"no owns yet\" :gate \"true\")\n"))
        (ctx (ctxOf dir bin 4 4 400))
        (_ (cd/loopOnce! ctx (strongSnap 0) (fn [] -> Unit ()) false))
        (noCfg (listLength (cd/readCUnits! dir)))
        (_ (fileWrite (cd/ledgerPath dir) (str ledger "\ndev\n")))
        (_ (cd/loopOnce! ctx (strongSnap 0) (fn [] -> Unit ()) false))
        (_ (cd/loopOnce! ctx (strongSnap 0) (fn [] -> Unit ()) false))
        (esc (readOr dir "escalations.asn"))
        (status (cd/status! ctx))
        (n1 (cuOf dir "N1"))
        (_ (cleanup dir))]
    (do (assert (= noCfg 0) "no ledger.path, nothing imported")
        (assert (not (= n1.st "absent")) (str "N1 imported and stepped: " n1.st))
        (assert (and (stringContains? esc "(:need :unit \"P1\" :needs owns :do \"no owns yet\")") (= (listLength (stringSplit esc "(:need ")) 2)) (str "one need row for P1: " esc))
        (assert (stringContains? status "(:parked (\"P1:owns\"))") (str "status lists the parked row: " status))
        true))

; (:m :ref WRITEESC :do "a unit failing the write stage maxSame times on lane free is admitted again on paid (count reset, tierHop journalled) and merges there; with every lane failing it blocks only after the last lane, with exactly one escalate row")
fn ! laneCtx dir: String bin: String failing: (List String) -> cd/Ctx
  (cd/Ctx :dir dir :holder "conductorTest" :ttlMs 600000 :maxWait 400 :maxSame 3 :stageSec 60 :maxDesc 50
          :launch (fn [(stage String) (u st/Task) (c cd/CUnit)] -> (List String)
                    (listAppend (list bin "stage" stage u.id "--store" dir) (if (and (= stage "write") (listContains? failing c.lane)) (list "--failsig" (str "writer boom on " c.lane)) (list))))
          :pace (cd/fixedPace 4 4))

fn ! testWriteTierHop bin: String -> Bool
  (let [(dir (scratch "hop"))
        (_ (cleanup dir))
        (put (putAll! dir (list (task "T" (list "p/t") (list) (greenGate) "free"))))
        (ctx (laneCtx dir bin (list "free")))
        (ticks (cd/drain! ctx 900))
        (t (cuOf dir "T"))
        (j (stringJoin (journalLines dir) "\n"))
        (esc (readOr dir "escalations.asn"))
        (dir2 (scratch "hop2"))
        (_ (cleanup dir2))
        (put2 (putAll! dir2 (list (task "U" (list "p/u") (list) (greenGate) "free"))))
        (ctx2 (laneCtx dir2 bin (list "free" "paid" "strong")))
        (ticks2 (cd/drain! ctx2 1200))
        (u (cuOf dir2 "U"))
        (j2 (stringJoin (journalLines dir2) "\n"))
        (esc2 (readOr dir2 "escalations.asn"))
        (_ (cleanup dir))
        (_ (cleanup dir2))]
    (do (assert (and put put2) "units put")
        (assert (stringContains? j "tierHop free->paid") (str "free failed 3x and hopped to paid: " j))
        (assert (and (= t.lane "paid") (not (= t.st "blocked")) (stringEmpty? esc)) (str "T runs on paid, not blocked, no escalate row: " t.lane " " t.st " " esc))
        (assert (and (stringContains? j2 "tierHop free->paid") (stringContains? j2 "tierHop paid->strong")) (str "U hopped through every tier: " j2))
        (assert (and (= u.st "blocked") (= u.lane "strong")) (str "U blocked on the last tier: " u.st " " u.lane))
        (assert (= (listLength (stringSplit esc2 "(:escalate")) 2) (str "exactly one escalate row, written after the last tier: " esc2))
        (assert (= (listLength (stringSplit j2 " :to blocked ")) 2) "blocked once")
        true))

; (:m :ref ROTATE :do "a (:writeProfiles :tier T :profiles (..) :weights (..)) lanes row picks a profile per unit id by weight, the same id always the same one; without the row the old profile is used")
fn ! testRotateProfiles -> Bool
  (let [(lanes "(:writeProfiles :tier free :profiles (pA pB pC) :weights (3 2 1))\n(:writeProfile :tier paid :profile pX)\n")
        (ids (map (fn [(i Int64)] -> String (str "UNIT" (stringFromInt64 i))) (range 0 600)))
        (picks (map (fn [(id String)] -> String (cd/pickWriteProfile lanes id "free" "base")) ids))
        (picks2 (map (fn [(id String)] -> String (cd/pickWriteProfile lanes id "free" "base")) ids))
        (cnt (fn [(p String)] -> Int64 (listLength (filter (fn [(x String)] -> Bool (= x p)) picks))))
        (a (cnt "pA")) (b (cnt "pB")) (c (cnt "pC"))
        (none1 (cd/pickWriteProfile "" "UNIT1" "free" "base"))
        (other (cd/pickWriteProfile lanes "UNIT1" "strong" "base"))]
    (do (assert (= (+ a (+ b c)) 600) (str "every id got a listed profile: " (stringFromInt64 a) " " (stringFromInt64 b) " " (stringFromInt64 c)))
        (assert (and (> a 250) (< a 350)) (str "pA near half: " (stringFromInt64 a)))
        (assert (and (> b 160) (< b 240)) (str "pB near a third: " (stringFromInt64 b)))
        (assert (and (> c 60) (< c 140)) (str "pC near a sixth: " (stringFromInt64 c)))
        (assert (= picks picks2) "the same id always gets the same profile")
        (assert (= none1 "base") "no row keeps the old profile")
        (assert (= other "base") "a row of another tier keeps the old profile")
        true))

; (:m :ref SCHED :do "with no sched.asn the light pool is the jobserver token count as before; a sched.asn without a state file starts at its :start")
fn ! testNoSchedFile -> Bool
  (let [(home (scratch "nosched"))
        (_ (cleanup home))
        (dir (str home "/store"))
        (_ (dirCreate home))
        (_ (dirCreate dir))
        (tokens ((cd/realPace).tokens))
        (plain ((cd/schedPace dir home).tokens))
        (_ (dirCreate (str home "/.asl")))
        (_ (dirCreate (str home "/.asl/conductor")))
        (_ (fileWrite (str home "/.asl/conductor/sched.asn") "(:sched :min 2 :max 9 :step 1 :start 7)\n"))
        (started ((cd/schedPace dir home).tokens))
        (_ (cleanup home))]
    (do (assert (= plain tokens) (str "no sched.asn: admission equals the token count: " (stringFromInt64 plain) " " (stringFromInt64 tokens)))
        (assert (= started 7) (str "sched.asn without ledger and state starts at :start: " (stringFromInt64 started)))
        true))

fn ! runTests -> Bool
  (let [(bin (fixtureBinary!))]
    (do (assert (not (stringEmpty? bin)) "the fixture stage binary is prepared")
        (assert (testNoSchedFile) "the light pool equals the token count without sched.asn")
        (assert (testRotateProfiles) "writer profiles rotate per unit by weight")
        (assert (testDag bin) "dag order")
        (assert (testOwnsSerialised bin) "overlapping owns serialised")
        (assert (testAdmission bin) "admission = min(ready, capacity, allowance)")
        (assert (testDepStalled) "dependency waits count only when stalled")
        (assert (testGateEscalates bin) "3 same-signature gate failures escalate")
        (assert (testWriteTierHop bin) "write failures hop free to paid to strong before blocking")
        (assert (testSignatureReset bin) "a new signature resets the count")
        (assert (testWake bin) "wake moves a parked unit")
        (assert (testWriterClaimIgnored bin) "writer's green claim is not trusted")
        (assert (testWaitEscalates bin) "waiting past maxWait escalates")
        (assert (testVacuousBlocks bin) "a vacuous-gate write blocks at once")
        (assert (testParallel bin) "stages overlap")
        (assert (testCapacity bin) "capacity counts units in flight")
        (assert (testKilledChild bin) "killed child is a failed stage")
        (assert (testStageTimeout bin) "stage deadline kills and fails")
        (assert (testResume bin) "restart resumes from rows")
        (assert (testUnpriced bin) "an unpriced stage journals :priced false")
        (assert (testOfferStrong bin) "the queue offers a blocked unit to the strong lane")
        (assert (testIntake bin) "the service cycle imports the ledger and queues need rows for parked ones")
        (assert (testMergeRetry bin) "a merge failure retries the merge with its reason journalled")
        true))
