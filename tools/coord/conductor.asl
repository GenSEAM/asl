(module asl-tools/coord/conductor
  :x [CUnit Res Pace Ctx RealCfg
      cuDir cuPath journalPath escalationsPath runsDir runPath runRow renderCUnit parseCUnit readCUnits! writeCUnit! costText renderRes parseRes
      allowanceUnlimited fixedPace jobserverPace gateSig rulingVerdict
      depStalled? armOf writeArm armExtra vacuousWrite? vacuousSig vacuousSig? pickWriteProfile pickWriteProfileH schedPace tick! wake! status! drain! stopAll! gatesRes loadUnit! writeRes! realRes realLaunch attachOrAdd parkedRows! needRows! importCycle! ledgerPath offerStrong! lastTiers tiersOfRows offeredRung! offerPath freshBase! leonTokens leonCost dropRemotes! mergeEnv realPace      settled? realCfg sigKey laneSnapshot refreshWake! startupProblemsFor stopPath requestStop! loopOnce! runLoop! gatesStage
      main]
  :i [(asl-tools/coord/store :a st) (asl-tools/coord/planImport :a pi) (asl-tools/coord/worktree :a w) (asl-tools/coord/sched :a sc) (asl-tools/fleet/run :a fr) (asl-tools/fleet/jobserver :a js) (tools/fleet/freePool :a fp)
      (asl-tools/coord/reviewStage :a rs) (asl-tools/coord/ladder :a l) (asl-tools/coord/gateGuard :a gg) (aslGateway/subPace :a sp) (aslGateway/localTime :a lt) (aslGateway/usageLedger :a ul) (aslGateway/subsRefresh :a sr)])

; (:m :ref CONDUCTOR :do "deterministic scheduler, no model in the loop: units are store rows (:after = deps, :owns, :gate, :channel = lane), the conductor keeps one state row per unit under <dir>/cond and appends one journal row per transition; the store lease is held from writing to merging so owns stay disjoint, and the store row turns done only when the unit is merged")

; (:m :do "states: queued ready writing gating awaitReview reviewing merging merged blocked failed")
(schema CUnit
  (:f id String) (:f st String) (:f lane String) (:f fails Int64) (:f sig String) (:f waited Int64) (:f parked Int64)
  (:f epoch Int64) (:f branch String) (:f wt String) (:f model String) (:f tokens Int64) (:f costMicro Int64) (:f esc Int64) (:f launched Int64) (:f await String))

; (:m :ref CONDUCTOR :do "a stage runs as a detached child process and leaves one Res row at <store>/runs/UNIT-STAGE.asn; fields are the union of the four stages: write sets ok wt branch model tokens costMicro claimedGreen sig, gates sets exit asserts sig, review sets verdict pass|fail|defer|block model tokens costMicro sig, merge sets ok sig; defer parks the unit until wake(lane), block escalates")
(schema Res
  (:f ok Int64) (:f wt String) (:f branch String) (:f model String) (:f tokens Int64) (:f costMicro Int64) (:f claimedGreen Int64)
  (:f sig String) (:f ms Int64) (:f exit Int64) (:f asserts Int64) (:f verdict String) (:f tiers String))

; (:m :ref CONDUCTOR :do "the admission interface SUBPACE plugs into: tokens = how many units may be in flight at once on this machine (jobserver pool size), allowance lane = how many of them may belong to that lane; a tick admits min(ready, tokens - inFlight, allowance lane - inFlight lane)")
(schema Pace
  (:f tokens (fn [] -> Int64))
  (:f allowance (fn [String] -> Int64)))

; (:m :ref CONDUCTOR :do "launch stage unit state -> argv of the detached child that performs the stage and writes its Res row; stageSec is the child deadline recorded in the store run row, maxDesc its descendant limit")
(schema Ctx
  (:f dir String) (:f holder String) (:f ttlMs Int64) (:f maxWait Int64) (:f maxSame Int64) (:f stageSec Int64) (:f maxDesc Int64)
  (:f launch (fn [String st/Task CUnit] -> (List String))) (:f pace Pace))

(schema RealCfg
  (:f repo String) (:f devRepo String) (:f devBranch String) (:f wt w/Cfg) (:f home String) (:f keys String) (:f leaseSec Int64) (:f gateSec Int64) (:f lanes String) (:f writerAlias String) (:f profile String) (:f attractorAb Bool))

fn cuDir dir: String -> String
  (str dir "/cond")

fn cuPath dir: String id: String -> String
  (str (cuDir dir) "/" id ".asn")

fn journalPath dir: String -> String
  (str dir "/journal.asn")

fn escalationsPath dir: String -> String
  (str dir "/escalations.asn")

fn n i: Int64 -> String
  (stringFromInt64 i)

fn renderCUnit c: CUnit -> String
  (str "(:cu :id " (st/q c.id) " :st " c.st " :lane " (st/q c.lane) " :fails " (n c.fails) " :sig " (st/q c.sig) " :waited " (n c.waited)
       " :parked " (n c.parked) " :epoch " (n c.epoch) " :branch " (st/q c.branch) " :wt " (st/q c.wt) " :model " (st/q c.model)
       " :tokens " (n c.tokens) " :costMicro " (n c.costMicro) " :esc " (n c.esc) " :launched " (n c.launched) " :await " (st/q c.await) ")")

fn parseCUnit raw: String -> (Result CUnit String)
  (match (st/rowFields raw "cu")
    ((err e) (err e))
    ((ok fs)
      (ok (CUnit :id (st/textField fs "id") :st (st/textField fs "st") :lane (st/textField fs "lane") :fails (st/intField fs "fails")
                 :sig (st/textField fs "sig") :waited (st/intField fs "waited") :parked (st/intField fs "parked") :epoch (st/intField fs "epoch")
                 :branch (st/textField fs "branch") :wt (st/textField fs "wt") :model (st/textField fs "model")
                 :tokens (st/intField fs "tokens") :costMicro (st/intField fs "costMicro") :esc (st/intField fs "esc") :launched (st/intField fs "launched") :await (st/textField fs "await")))))

fn newCUnit u: st/Task -> CUnit
  (CUnit :id u.id :st "queued" :lane u.channel :fails 0 :sig "" :waited 0 :parked 0 :epoch 0 :branch "" :wt "" :model u.model :tokens 0 :costMicro 0 :esc 0 :launched 0 :await "")

fn ! writeCUnit! dir: String c: CUnit -> (Result Unit String)
  (match (dirCreate (cuDir dir))
    ((err e) (err e))
    ((ok _) (let [(tmp (str (cuPath dir c.id) "." (n (procSelf)) ".tmp"))]
              (match (fileWrite tmp (str (renderCUnit c) "\n"))
                ((err e) (err e))
                ((ok _) (pathRename tmp (cuPath dir c.id)))))))

fn ! readCUnits! dir: String -> (List CUnit)
  (match (dirList (cuDir dir))
    ((err _) (list))
    ((ok names)
      (fold (fn [(acc (List CUnit)) (name String)] -> (List CUnit)
              (if (not (stringEndsWith? name ".asn")) acc
                (match (fileReadString (str (cuDir dir) "/" name))
                  ((err _) acc)
                  ((ok raw) (match (parseCUnit raw) ((ok c) (listAppend acc (list c))) ((err _) acc))))))
            (list) (listSort names))))

fn cuOf cus: (List CUnit) id: String -> (Option CUnit)
  (listFind (fn [(c CUnit)] -> Bool (= c.id id)) cus)

fn costText micro: Int64 -> String
  (let [(frac (str "000000" (n (mod micro 1000000))))]
    (str (n (/ micro 1000000)) "." (optionOr (stringSlice frac (- (stringLength frac) 6) (stringLength frac)) "000000")))

fn ! journal! ctx: Ctx c: CUnit to: String stage: String model: String tokens: Int64 cost: Int64 verdict: String ms: Int64 -> (Result Unit String)
  (fileAppend (journalPath ctx.dir)
    (str "(:t :unit " (st/q c.id) " :from " c.st " :to " to " :stage " stage " :model " (st/q model) " :tokens " (n tokens)
         " :costUsd " (costText (max 0 cost)) (if (< cost 0) " :priced false" "") " :verdict " (st/q verdict) " :ms " (n ms) " :at " (n (/ (nowNs) 1000000)) ")\n"))

; (:m :ref CONDUCTOR :do "every state change goes through move!: the journal row first, then the unit row with the spend added, so a crash between them replays as the same transition")
fn ! move! ctx: Ctx c: CUnit to: String stage: String model: String tokens: Int64 cost: Int64 verdict: String ms: Int64 -> CUnit
  (let [(next (with c :launched 0 :st to :tokens (+ c.tokens tokens) :costMicro (+ c.costMicro (max 0 cost)) :model (if (stringEmpty? model) c.model model)))
        (_ (journal! ctx c to stage model tokens cost verdict ms))
        (_ (writeCUnit! ctx.dir next))]
    next)

fn ! escalateTiered! ctx: Ctx c: CUnit seen: String tried: String tiers: String -> CUnit
  (let [(_ (if (= c.esc 0)
             (fileAppend (escalationsPath ctx.dir) (str "(:escalate :unit " (st/q c.id) " :seen " (st/q seen) " :tried " (st/q tried) (if (stringEmpty? tiers) "" (str " :tiers (" tiers ")")) ")\n"))
             (ok ())))]
    (with c :esc 1))

fn ! escalate! ctx: Ctx c: CUnit seen: String tried: String -> CUnit
  (escalateTiered! ctx c seen tried "")

fn ! dropLease! ctx: Ctx c: CUnit -> Unit
  (let [(_ (if (> c.epoch 0) (st/release! ctx.dir c.id c.epoch) (ok "")))] ())

; (:m :ref COND3 :do "failure signatures compare without their ids: any word with a digit and six or more characters (session ids, pids, timestamps) counts as one placeholder, so the same failure with a fresh session id is still the same failure")
fn idWord? w: String -> Bool
  (and (>= (stringLength w) 6) (listAny? (fn [(ch String)] -> Bool (stringContains? "0123456789" ch)) (stringChars w)))

fn sigKey sig: String -> String
  (let [(spaced (fold (fn [(acc String) (ch String)] -> String (str acc (if (stringContains? "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789" ch) ch " "))) "" (stringChars sig)))]
    (stringJoin (map (fn [(w String)] -> String (if (idWord? w) "#" w)) (filter (fn [(w String)] -> Bool (not (stringEmpty? w))) (stringSplit spaced " "))) " "))

fn verdictSig sig: String -> String
  (let [(one (stringTrim (stringJoin (stringSplit sig "\n") " ")))]
    (optionOr (stringSlice one 0 (if (< (stringLength one) 400) (stringLength one) 400)) one))

; (:m :ref WRITEESC :do "the write tiers in escalation order; a unit on free that fails the write stage maxSame times in a row moves to paid, then strong, and only a last-tier failure blocks")
fn writeTiers -> (List String)
  (list "free" "paid" "strong")

fn nextTier lane: String -> Option String
  (let [(i (optionOr (listFind (fn [(k Int64)] -> Bool (= (optionOr (listGet (writeTiers) k) "") lane)) (range 0 (listLength (writeTiers)))) -1))]
    (if (< i 0) (none) (listGet (writeTiers) (+ i 1))))

; (:m :ref CONDUCTOR :do "a stage failure releases the lease and retries from ready; the same failure signature maxSame times in a row writes one escalate row and parks the unit in blocked; WRITEESC: a write failure with a higher tier left hops the unit to that tier instead, resets the count and journals tierHop")
fn ! fail! ctx: Ctx c: CUnit stage: String model: String sig: String ms: Int64 -> CUnit
  (let [(fails (if (= (sigKey sig) (sigKey c.sig)) (+ c.fails 1) 1))
        (_ (dropLease! ctx c))
        (c1 (with c :fails fails :sig sig :epoch 0))
        (hop (if (= stage "write") (nextTier c.lane) (none)))]
    (if (>= fails ctx.maxSame)
      (match hop
        ((some next) (move! ctx (with c1 :lane next :fails 0 :sig "" :waited 0) "ready" stage model 0 0 (str "tierHop " c.lane "->" next ": " (verdictSig sig)) ms))
        ((none)
          (let [(c2 (escalate! ctx c1 sig (str stage " failed " (n fails) "x with the same signature")))]
            (move! ctx c2 "blocked" stage model 0 0 (str "escalated: " (verdictSig sig)) ms))))
      (move! ctx c1 "ready" stage model 0 0 (str "fail: " (verdictSig sig)) ms)))

; (:m :ref DEPWAIT :do "a dependency wait counts toward maxWait only when a dependency is missing, blocked or failed; one still queued, ready or in a stage is progress, not a stall")
fn depStalled? u: st/Task cus: (List CUnit) -> Bool
  (listAny? (fn [(d String)] -> Bool (match (cuOf cus d) ((some x) (listContains? (list "blocked" "failed") x.st)) ((none) true))) u.after)

fn depsMerged? u: st/Task cus: (List CUnit) -> Bool
  (listAll? (fn [(d String)] -> Bool (match (cuOf cus d) ((some x) (= x.st "merged")) ((none) false))) u.after)

fn active? c: CUnit -> Bool
  (listContains? (list "writing" "gating" "awaitReview" "reviewing" "merging") c.st)

fn laneActive cus: (List CUnit) lane: String -> Int64
  (listLength (filter (fn [(x CUnit)] -> Bool (and (active? x) (= x.lane lane))) cus))

; (:m :do "a unit waiting more than maxWait ticks for deps or a claim escalates and blocks; a wait for lane capacity is backpressure and never counts (ADMITWAIT)")
fn ! waitMore! ctx: Ctx c: CUnit why: String -> CUnit
  (let [(c1 (with c :waited (+ c.waited 1)))]
    (if (> c1.waited ctx.maxWait)
      (let [(c2 (escalate! ctx c1 why (str "waited " (n c1.waited) " ticks")))]
        (move! ctx c2 "blocked" "wait" "" 0 0 "escalated" 0))
      (let [(_ (writeCUnit! ctx.dir c1))] c1)))

fn ! beat? ctx: Ctx c: CUnit -> Bool
  (match (st/heartbeat! ctx.dir c.id c.epoch) ((ok _) true) ((err _) false))

fn runsDir dir: String -> String
  (str dir "/runs")

fn runPath dir: String id: String stage: String ext: String -> String
  (str (runsDir dir) "/" id "-" stage "." ext)

fn renderRes r: Res -> String
  (str "(:res :ok " (n r.ok) " :wt " (st/q r.wt) " :branch " (st/q r.branch) " :model " (st/q r.model) " :tokens " (n r.tokens) " :costMicro " (n r.costMicro)
       " :claimedGreen " (n r.claimedGreen) " :sig " (st/q r.sig) " :ms " (n r.ms) " :exit " (n r.exit) " :asserts " (n r.asserts) " :verdict " (st/q r.verdict) " :tiers " (st/q r.tiers) ")")

fn parseRes raw: String -> (Result Res String)
  (match (st/rowFields raw "res")
    ((err e) (err e))
    ((ok fs)
      (ok (Res :ok (st/intField fs "ok") :wt (st/textField fs "wt") :branch (st/textField fs "branch") :model (st/textField fs "model")
               :tokens (st/intField fs "tokens") :costMicro (st/intField fs "costMicro") :claimedGreen (st/intField fs "claimedGreen")
               :sig (st/textField fs "sig") :ms (st/intField fs "ms") :exit (st/intField fs "exit") :asserts (st/intField fs "asserts")
               :verdict (st/textField fs "verdict") :tiers (st/textField fs "tiers")))))

fn failRes sig: String -> Res
  (Res :tiers "" :ok 0 :wt "" :branch "" :model "" :tokens 0 :costMicro 0 :claimedGreen 0 :sig sig :ms 0 :exit 1 :asserts 0 :verdict "fail")

fn ! writeRes! dir: String id: String stage: String r: Res -> (Result Unit String)
  (match (dirCreate (runsDir dir))
    ((err e) (err e))
    ((ok _) (let [(tmp (str (runPath dir id stage "asn") "." (n (procSelf)) ".tmp"))]
              (match (fileWrite tmp (str (renderRes r) "\n"))
                ((err e) (err e))
                ((ok _) (pathRename tmp (runPath dir id stage "asn")))))))

fn ! runRow dir: String id: String stage: String -> (Option (Pair Int64 Int64))
  (match (fileReadString (runPath dir id stage "run"))
    ((err _) (none))
    ((ok raw) (match (st/rowFields raw "run")
                ((err _) (none))
                ((ok fs) (some (pair (st/intField fs "pid") (st/intField fs "deadlineMs")))))))

fn ! dropRun! dir: String id: String stage: String -> Unit
  (let [(_ (pathRemove (runPath dir id stage "run")))
        (_ (pathRemove (runPath dir id stage "asn")))]
    ())

fn ! nowMs -> Int64
  (/ (nowNs) 1000000)

; (:m :ref CONDUCTOR :do "alive = still running: a child of this process is reaped without blocking (a zombie is not alive), any other pid, after a conductor restart, is asked by signal 0")
fn ! alive? pid: Int64 -> Bool
  (match (procWaitPid pid true)
    ((ok (some _)) false)
    ((ok (none)) true)
    ((err _) (resultOr (procAlive? pid) false)))


; (:m :do "kill a stage's whole tree and reap the child if it is ours, so it is not left a zombie")
fn ! killStage! pid: Int64 -> Unit
  (let [(_ (fr/killTree! pid))
        (_ (procWaitPid pid true))]
    ())

fn stageName st: String -> String
  (cond ((= st "writing") "write") ((= st "gating") "gates") ((= st "reviewing") "review") ((= st "merging") "merge") (else ""))

fn ! killRun! dir: String id: String stage: String -> Unit
  (match (runRow dir id stage)
    ((some r) (killStage! (pairFirst r)))
    ((none) ()))

; (:m :ref CONDUCTOR :do "a stage is a detached child started through run.asl's spawnSep in its own process group; the store keeps its pid and deadline in <store>/runs/UNIT-STAGE.run, the child's only output is the Res row, so a restarted conductor resumes from the rows alone")
fn ! launch! ctx: Ctx u: st/Task c: CUnit -> CUnit
  (let [(stage (stageName c.st))
        (mk ctx.launch)
        (argv (mk stage u c))
        (_ (dirCreate (runsDir ctx.dir)))
        (_ (dropRun! ctx.dir c.id stage))]
    (match (fr/spawnSep argv "." (fr/childEnv (list)))
      ((err po) (fail! ctx c stage "" (str "spawnFailed " (optionOr (stringSlice po.stderr 0 (if (< (stringLength po.stderr) 120) (stringLength po.stderr) 120)) "")) 0))
      ((ok r)
        (let [(_ (fdClose r.outFd))
              (_ (fdClose r.errFd))
              (_ (fileWrite (runPath ctx.dir c.id stage "run")
                            (str "(:run :unit " (st/q c.id) " :stage " stage " :pid " (n r.pid) " :startedMs " (n (nowMs)) " :deadlineMs " (n (+ (nowMs) (* ctx.stageSec 1000))) ")\n")))
              (c1 (with c :launched 1))
              (_ (writeCUnit! ctx.dir c1))]
          c1))))

; (:m :ref COND3 :do "a merge failure retries the merge itself, keeping the lease, the branch and the reviewed work; the same signature maxSame times escalates; the journal row carries the reason because the scratch store is cleaned after a run")
fn ! mergeFail! ctx: Ctx u: st/Task c: CUnit sig: String ms: Int64 -> CUnit
  (let [(fails (if (= (sigKey sig) (sigKey c.sig)) (+ c.fails 1) 1))
        (c1 (with c :fails fails :sig sig))]
    (if (>= fails ctx.maxSame)
      (let [(_ (dropLease! ctx c1))
            (c2 (escalate! ctx (with c1 :epoch 0) sig (str "merge failed " (n fails) "x with the same signature")))]
        (move! ctx c2 "blocked" "merge" "" 0 0 (str "escalated: " (verdictSig sig)) ms))
      (let [(c2 (move! ctx c1 "merging" "merge" "" 0 0 (str "retry: " (verdictSig sig)) ms))]
        (launch! ctx u c2))))

fn ! poll! ctx: Ctx c: CUnit -> (Option Res)
  (let [(stage (stageName c.st))
        (row (runRow ctx.dir c.id stage))
        (isUp (match row ((some r) (alive? (pairFirst r))) ((none) false)))
        (res (match (fileReadString (runPath ctx.dir c.id stage "asn"))
               ((ok raw) (some (resultOr (parseRes raw) (failRes "unreadable stage result"))))
               ((err _) (none))))]
    (cond
      ((some? res) res)
      ((none? row) (some (failRes "stage run row lost")))
      ((not isUp) (some (failRes "stage died without a result")))
      (else
        (let [(r (optionOr row (pair 0 0)))
              (desc (listLength (fr/descendantsOf (fr/psSnapshot) (pairFirst r))))]
          (cond
            ((> (nowMs) (pairSecond r)) (let [(_ (killStage! (pairFirst r)))] (some (failRes (str "stage timeout after " (n ctx.stageSec) " s")))))
            ((> desc ctx.maxDesc) (let [(_ (killStage! (pairFirst r)))] (some (failRes (str "stage runaway: " (n desc) " descendants")))))
            (else (none)))))))

fn admitted c: CUnit epoch: Int64 -> CUnit
  (with c :epoch epoch :waited 0)

fn noEpoch c: CUnit -> CUnit
  (with c :epoch 0)

fn written c: CUnit wt: String branch: String -> CUnit
  (with c :wt wt :branch branch)

fn parkedOf c: CUnit flag: Int64 -> CUnit
  (with c :parked flag)

fn awaiting c: CUnit lane: String -> CUnit
  (with c :parked 1 :await lane)

fn inFlight? c: CUnit -> Bool
  (and (!= c.launched 0) (!= (stageName c.st) ""))

; (:m :do "applies one finished stage result to its unit; the writer's claimedGreen is only journalled")
fn ! finish! ctx: Ctx u: st/Task c: CUnit res: Res -> Unit
  (let [(stage (stageName c.st))
        (_ (dropRun! ctx.dir c.id stage))]
    (cond
      ((= c.st "writing")
        (if (= res.ok 1)
          (let [(c1 (move! ctx (written c res.wt res.branch) "gating" "write" res.model res.tokens res.costMicro (if (= res.claimedGreen 1) "claimedGreen" "written") res.ms))
                (_ (launch! ctx u c1))]
            ())
          (if (vacuousSig? res.sig)
            (let [(_ (dropLease! ctx c))
                  (c1 (escalate! ctx (with c :sig res.sig :epoch 0) res.sig "write: the unit gate passes on the base before any edit, so no write can prove it; make the gate fail on the base or mark the task a regression guard"))
                  (_ (move! ctx c1 "blocked" "write" res.model 0 0 (str "escalated: " (verdictSig res.sig)) res.ms))]
              ())
            (let [(_ (fail! ctx c "write" res.model res.sig res.ms))] ()))))
      ((= c.st "gating")
        (if (and (= res.exit 0) (> res.asserts 0))
          (let [(_ (move! ctx c "awaitReview" "gates" "" 0 0 (str "green " (n res.asserts)) res.ms))] ())
          (let [(_ (fail! ctx c "gates" "" (if (stringEmpty? res.sig) (str "exit " (n res.exit) " asserts " (n res.asserts)) res.sig) res.ms))] ())))
      ((= c.st "reviewing")
        (cond
          ((= res.verdict "pass")
            (let [(c1 (move! ctx c "merging" "review" res.model res.tokens res.costMicro "pass" res.ms))
                  (_ (launch! ctx u c1))]
              ()))
          ((= res.verdict "defer") (let [(_ (move! ctx (awaiting c res.sig) "awaitReview" "review" res.model res.tokens res.costMicro "defer" res.ms))] ()))
          ((= res.verdict "block")
            (let [(c2 (escalateTiered! ctx c res.sig "review blocked" res.tiers))
                  (_ (dropLease! ctx c2))
                  (_ (move! ctx (noEpoch c2) "blocked" "review" res.model res.tokens res.costMicro "block" res.ms))]
              ()))
          (else (let [(_ (fail! ctx c "review" res.model res.sig res.ms))] ()))))
      ((= c.st "merging")
        (if (= res.ok 1)
          (match (st/commit! ctx.dir c.id c.epoch c.branch)
            ((ok _) (let [(_ (move! ctx (noEpoch c) "merged" "merge" "" 0 0 "merged" res.ms))] ()))
            ((err e) (let [(_ (mergeFail! ctx u c e res.ms))] ())))
          (let [(_ (mergeFail! ctx u c res.sig res.ms))] ())))
      (else ())))

; (:m :do "returns the in-flight capacity left for the rest of this tick")
fn ! step! ctx: Ctx u: st/Task cap: Int64 -> Int64
  (let [(cus (readCUnits! ctx.dir))
        (c (optionOr (cuOf cus u.id) (newCUnit u)))]
    (cond
      ((= c.st "queued")
        (if (depsMerged? u cus)
          (let [(_ (move! ctx c "ready" "deps" "" 0 0 "depsMerged" 0))] cap)
          (if (depStalled? u cus) (let [(_ (waitMore! ctx c "deps not merged"))] cap) cap)))
      ((= c.st "ready")
        (let [(pace ctx.pace)
              (allowOf pace.allowance)
              (allow (allowOf c.lane))]
          (if (or (<= cap 0) (>= (laneActive cus c.lane) allow))
            cap
            (match (st/claim! ctx.dir c.id ctx.holder ctx.ttlMs)
              ((err e) (let [(_ (waitMore! ctx c e))] cap))
              ((ok text)
                (let [(epoch (match (st/parseLease text) ((ok l) l.epoch) ((err _) 0)))
                      (c1 (move! ctx (admitted c epoch) "writing" "claim" "" 0 0 "admitted" 0))
                      (_ (launch! ctx u c1))]
                  (- cap 1)))))))
      ((= c.st "awaitReview")
        (if (= c.parked 1) cap
          (let [(c1 (move! ctx c "reviewing" "review" "" 0 0 "start" 0))
                (_ (launch! ctx u c1))]
            cap)))
      ((= (stageName c.st) "") cap)
      ((not (beat? ctx c))
        (let [(_ (killRun! ctx.dir c.id (stageName c.st)))
              (_ (dropRun! ctx.dir c.id (stageName c.st)))
              (_ (move! ctx (noEpoch c) "ready" "lease" "" 0 0 "leaseLost" 0))]
          cap))
      ((= c.launched 0) (let [(_ (launch! ctx u c))] cap))
      (else
        (match (poll! ctx c)
          ((none) cap)
          ((some res) (let [(_ (finish! ctx u c res))] cap))))))

fn ! stepAll! ctx: Ctx units: (List st/Task) cap: Int64 -> Unit
  (match (listHead units)
    ((none) ())
    ((some u)
      (stepAll! ctx (optionOr (listTail units) (list)) (step! ctx u cap))))

fn ! snapshot dir: String -> (List String)
  (map (fn [(c CUnit)] -> String (renderCUnit c)) (readCUnits! dir))

; (:m :ref CONDUCTOR :do "one tick starts, polls and transitions only, never waits for a stage: every unit moves at most one transition in id order; capacity = pace tokens minus the units already in flight; the result is 1 when any unit row changed, 0 when the tick was idle")
fn ! tick! ctx: Ctx -> (Result Int64 String)
  (match (st/readUnits! ctx.dir)
    ((err e) (err e))
    ((ok units)
      (let [(before (snapshot ctx.dir))
            (pace ctx.pace)
            (tokensOf pace.tokens)
            (flying (listLength (filter inFlight? (readCUnits! ctx.dir))))
            (_ (stepAll! ctx units (- (tokensOf) flying)))
            (after (snapshot ctx.dir))]
        (ok (if (= before after) 0 1)))))

; (:m :ref CONDUCTOR :do "settled = every store unit has a state row and none is queued, ready or in a stage; a parked awaitReview unit is settled until wake")
fn ! settled? ctx: Ctx -> Bool
  (let [(cus (readCUnits! ctx.dir))
        (stored (resultOr (st/readUnits! ctx.dir) (list)))]
    (and (= (listLength cus) (listLength stored))
         (listAll? (fn [(c CUnit)] -> Bool (or (listContains? (list "merged" "blocked" "failed") c.st) (and (= c.st "awaitReview") (= c.parked 1)))) cus)))

; (:m :do "ticks, sleeping 50 ms after an idle one, until settled or max ticks; returns the ticks run")
fn ! drain! ctx: Ctx max: Int64 -> Int64
  (if (<= max 0) 0
    (match (tick! ctx)
      ((err _) 0)
      ((ok changed)
        (if (settled? ctx) 1
          (let [(_ (if (= changed 0) (sleepMs 50) ()))]
            (+ 1 (drain! ctx (- max 1))))))))

; (:m :ref CONDUCTOR :do "stopAll! kills the process tree of every in-flight stage and drops its run row; the unit goes back to ready through the lease on the next start")
fn ! stopAll! ctx: Ctx -> Int64
  (let [(flying (filter inFlight? (readCUnits! ctx.dir)))
        (_ (map (fn [(c CUnit)] -> Unit (let [(_ (killRun! ctx.dir c.id (stageName c.st)))] (dropRun! ctx.dir c.id (stageName c.st)))) flying))]
    (listLength flying))

; (:m :ref CONDUCTOR :do "wake LANE: units parked in awaitReview for that lane (quota window reset or refreshed allowance) become ready for review; one journal row per unit")
fn ! wake! ctx: Ctx lane: String -> Int64
  (let [(cus (filter (fn [(c CUnit)] -> Bool (and (= c.st "awaitReview") (and (= c.parked 1) (or (= c.lane lane) (= c.await lane))))) (readCUnits! ctx.dir)))
        (_ (map (fn [(c CUnit)] -> CUnit (move! ctx (parkedOf c 0) "awaitReview" "wake" "" 0 0 lane 0)) cus))]
    (listLength cus))

fn idList cus: (List CUnit) pred: (fn [CUnit] -> Bool) -> String
  (stringJoin (map (fn [(c CUnit)] -> String (st/q c.id)) (filter pred cus)) " ")

fn ! status! ctx: Ctx -> String
  (let [(cus (readCUnits! ctx.dir))
        (lanes (fold (fn [(acc (List String)) (c CUnit)] -> (List String) (if (listContains? acc c.lane) acc (listAppend acc (list c.lane)))) (list) cus))
        (rows (map (fn [(c CUnit)] -> String (str "(:unit :id " (st/q c.id) " :st " c.st " :lane " (st/q c.lane) " :fails " (n c.fails) " :parked " (n c.parked) " :waited " (n c.waited) ")")) cus))
        (spend (map (fn [(l String)] -> String
                      (let [(mine (filter (fn [(c CUnit)] -> Bool (= c.lane l)) cus))]
                        (str "(:spend :lane " (st/q l) " :tokens " (n (fold (fn [(a Int64) (c CUnit)] -> Int64 (+ a c.tokens)) 0 mine))
                             " :costUsd " (costText (fold (fn [(a Int64) (c CUnit)] -> Int64 (+ a c.costMicro)) 0 mine)) ")"))) lanes))
        (esc (match (fileReadString (escalationsPath ctx.dir)) ((ok t) (filter (fn [(l String)] -> Bool (not (stringEmpty? (stringTrim l)))) (stringLines t))) ((err _) (list))))]
    (stringJoin (listAppend (listAppend rows spend)
                  (list (str "(:running (" (idList cus active?) "))")
                        (str "(:blocked (" (idList cus (fn [(c CUnit)] -> Bool (= c.st "blocked"))) "))")
                        (str "(:parked (" (stringJoin (map (fn [(p (Pair String String))] -> String (st/q (str (pairFirst p) ":" (optionOr (listHead (stringSplit (pairSecond p) "\n")) ""))) ) (parkedRows! ctx.dir)) " ") "))")
                        (str "(:escalations " (n (listLength esc)) ")")))
                "\n"))

fn allowanceUnlimited lane: String -> Int64
  1000000

fn fixedPace tokens: Int64 perLane: Int64 -> Pace
  (Pace :tokens (fn [] -> Int64 tokens) :allowance (fn [(lane String)] -> Int64 perLane))

fn ! poolSize dir: String -> Int64
  (js/tokenCount (js/rootDir dir))

fn jobserverPace dir: String allowance: (fn [String] -> Int64) -> Pace
  (Pace :tokens (fn [] -> Int64 (poolSize dir)) :allowance allowance)

; (:m :ref SCHED :do "the light pool: without ~/.asl/conductor/sched.asn it is the jobserver token count and nothing adapts; with one the slots come from the store's slots.asn, sampled at most once a minute from the gateway ledger, free RAM and load; gates and builds keep the jobserver class writer tokens")
fn ! lightSlots! dir: String home: String -> Int64
  (let [(txt (readOr (str home "/.asl/conductor/sched.asn")))]
    (if (stringEmpty? txt)
      (poolSize "")
      (let [(cfg (sc/parseCfg txt))
            (now (/ (nowNs) 1000000))]
        (if (sc/slotsDue? dir now 60000)
          (sc/schedTick! dir cfg now (stringLines (readOr (str home "/.asl/run/usage/gatewayCalls.asn"))) (sc/memFreeMB (readOr "/proc/meminfo")) (sc/loadOne (readOr "/proc/loadavg")) (resultOr (cpuCount) 1))
          (pairFirst (sc/slotsRead! dir))))))

fn schedPace dir: String home: String -> Pace
  (Pace :tokens (fn [] -> Int64 (lightSlots! dir home)) :allowance allowanceUnlimited)

fn realPace -> Pace
  (jobserverPace "" allowanceUnlimited)

; (:m :do "the first ERR line, else the last non-empty line, cut to 160 chars: the same failure gives the same signature")
fn gateSig out: String -> String
  (let [(errs (fr/errorLinesOf out))
        (lines (filter (fn [(l String)] -> Bool (not (stringEmpty? l))) (map stringTrim (stringLines out))))
        (quiet (filter (fn [(l String)] -> Bool (not (or (stringStartsWith? l "(:gateway :usage") (stringStartsWith? l "(:usage")))) lines))
        (marked (filter (fn [(l String)] -> Bool (let [(low (stringLower l))] (or (stringContains? low "fail") (or (stringContains? low "error") (stringContains? low "exit"))))) quiet))
        (pick (match (listHead errs) ((some e) e) ((none) (match (listHead marked) ((some m) m) ((none) (optionOr (listLast quiet) "no output"))))))]
    (optionOr (stringSlice pick 0 (if (< (stringLength pick) 160) (stringLength pick) 160)) pick))

fn ! taskText dir: String u: st/Task -> String
  (match (fileReadString (str dir "/tasks/" u.id ".txt"))
    ((ok t) t)
    ((err _) (str "Implement plan unit " u.id " exactly as its row in .asl/mem/work/SH/plan.asn says; the gate is: " u.gate)))

; (:m :ref CONDHARDEN :do "line count of the owned file at the unit's base and now; -1 when it did not exist there or is gone now")
fn ! baseLinesOf wt: String base: String path: String -> Int64
  (let [(d (fr/runOne (fr/job (list "git" "-C" wt "show" (str base ":" path)) wt (fr/childEnv (list)))))]
    (if (= d.exit 0) (listLength (stringLines d.out)) -1))

fn ! nowLinesOf wt: String path: String -> Int64
  (match (fileReadString (str wt "/" path)) ((ok t) (listLength (stringLines t))) ((err _) 0))

; (:m :ref CONDHARDEN :do "an owned file that existed on the base and lost more than half its lines is refused unless the task text says rewrite; empty when every owned file is fine")
fn ! shrinkRefusal! wt: String u: st/Task task: String -> String
  (optionOr (listHead (filter (fn [(s String)] -> Bool (not (stringEmpty? s)))
    (map (fn [(p String)] -> String (gg/shrinkSig p (baseLinesOf wt u.base p) (nowLinesOf wt p) task)) u.owns))) "")

; (:m :ref CONDHARDEN :do "files in the worktree that import an owned module, found by a literal grep for the module name and confirmed by the import-position check")
fn ! importerFiles! wt: String owned: (List String) -> (List String)
  (let [(mods (map (fn [(p String)] -> String (gg/moduleName (resultOr (fileReadString (str wt "/" p)) ""))) owned))
        (found (fn [(m String)] -> (List String)
                 (filter (fn [(l String)] -> Bool (not (stringEmpty? l)))
                   (map stringTrim (stringLines (fr/runOne (fr/job (list "git" "-C" wt "grep" "-l" "-F" "-e" m "--" "*.asl") wt (fr/childEnv (list)))).out)))))
        (paths (fold (fn [(acc (List String)) (m String)] -> (List String) (if (stringEmpty? m) acc (listAppend acc (found m)))) (list) mods))
        (files (map (fn [(p String)] -> (Pair String String) (pair p (resultOr (fileReadString (str wt "/" p)) ""))) paths))]
    (gg/importers files mods owned))

; (:m :ref CONDHARDEN :do "asl check on every owned .asl file and on every importer of an owned module; the first failure is the signature, empty when all check")
fn ! checkOne! wt: String p: String -> String
  (let [(d (fr/runOneLimited (fr/job (list (str wt "/bin/asl") "check" p) wt (fr/childEnv (list (str "ASL_ROOT=" wt)))) (fr/limits 300 200)))]
    (if (= d.exit 0) "" (str "asl check failed on " p ": " (gateSig d.out))))

fn ! firstCheckSig! wt: String targets: (List String) -> String
  (match (listHead targets)
    ((none) "")
    ((some p) (let [(sig (checkOne! wt p))] (if (stringEmpty? sig) (firstCheckSig! wt (optionOr (listTail targets) (list))) sig))))

fn ! checkSig! wt: String owned: (List String) -> String
  (firstCheckSig! wt (filter (fn [(p String)] -> Bool (and (stringEndsWith? p ".asl") (fileExists? (str wt "/" p)))) (listAppend owned (importerFiles! wt owned))))

; (:m :ref CONDUCTOR :do "the conductor's own gate stage reruns the declared gate in the unit's worktree and never reads the writer's report")
; (:m :ref CONDHARDEN :do "before the declared gate: owned files may not lose more than half their base lines without the word rewrite in the task text, and every owned .asl file and each importer of an owned module must pass asl check; either failure is exit 3 with a :sig naming the file")
fn ! gatesRes gateSec: Int64 task: String u: st/Task c: CUnit -> Res
  (let [(refused (if (stringEmpty? u.gate) "" (shrinkRefusal! c.wt u task)))
        (broken (if (or (stringEmpty? u.gate) (not (stringEmpty? refused))) "" (checkSig! c.wt u.owns)))]
    (cond
      ((stringEmpty? u.gate) (Res :tiers "" :ok 0 :wt "" :branch "" :model "" :tokens 0 :costMicro 0 :claimedGreen 0 :sig "unit declares no gate" :ms 0 :exit 2 :asserts 0 :verdict ""))
      ((not (stringEmpty? refused)) (Res :tiers "" :ok 0 :wt "" :branch "" :model "" :tokens 0 :costMicro 0 :claimedGreen 0 :sig refused :ms 0 :exit 3 :asserts 0 :verdict ""))
      ((not (stringEmpty? broken)) (Res :tiers "" :ok 0 :wt "" :branch "" :model "" :tokens 0 :costMicro 0 :claimedGreen 0 :sig broken :ms 0 :exit 3 :asserts 0 :verdict ""))
      (else
        (let [(d (fr/runShell! u.gate c.wt (fr/childEnv (list)) (fr/heavy (fr/limits gateSec 200) "writer" "")))]
          (Res :tiers "" :ok 0 :wt "" :branch "" :model "" :tokens 0 :costMicro 0 :claimedGreen 0 :sig (gateSig d.out) :ms d.ms :exit d.exit :asserts (optionOr (fr/executedOf d.out) 0) :verdict "")))))

; (:m :ref COND3 :do "a retried write finds its branch sh/UNIT left by an earlier attempt without a worktree and checks it out again instead of failing on the existing branch")
; (:m :ref COND3 :do "a leftover sh/UNIT re-attached for a re-run unit keeps its old base; when the unit's base is not an ancestor of it the branch is rebased onto the base, and when the rebase conflicts it is renamed sh/UNIT-stale-<s> (nothing is lost) and recreated from the base")
fn ! freshBase! rc: RealCfg u: st/Task path: String -> (Result String String)
  (let [(base (gitOut rc.repo (list "rev-parse" "--verify" "--quiet" (str u.base "^{commit}"))))
        (sha (stringTrim base.out))
        (branch (str "sh/" u.id))]
    (if (or (!= base.exit 0) (stringEmpty? sha)) (ok path)
      (if (= (gitOut path (list "merge-base" "--is-ancestor" sha "HEAD")).exit 0) (ok path)
        (let [(rb (gitOut path (list "rebase" sha)))]
          (if (= rb.exit 0) (ok path)
            (let [(_ (gitOut path (list "rebase" "--abort")))
                  (mv (gitOut path (list "branch" "-m" branch (str branch "-stale-" (stringFromInt64 (/ (nowMs) 1000))))))
                  (mk (gitOut path (list "checkout" "--quiet" "-b" branch sha)))]
              (if (and (= mv.exit 0) (= mk.exit 0)) (ok path) (err (str "stale branch recreate failed: " (stringTrim (str mv.out " " mk.out)))))))))))

fn ! attachOrAdd rc: RealCfg u: st/Task path: String -> (Result String String)
  (match (let [(_ (gitOut rc.repo (list "worktree" "prune")))] (w/addWt! rc.wt u.id u.base))
    ((ok p) (ok p))
    ((err e)
      (if (stringContains? e "already exists")
        (let [(a (fr/runOne (fr/job (list "git" "-C" rc.repo "worktree" "add" path (str "sh/" u.id)) rc.repo (fr/childEnv (list)))))]
          (if (= a.exit 0) (freshBase! rc u path) (err (str "worktree attach failed: " (stringTrim a.out)))))
        (err e))))

; (:m :ref COND3 :do "Leon's final receipt row ends with :usage (:input N :cached N :output N); the writer's spend is input plus output of the last such row, 0 when the run printed none")
fn leonTokens out: String -> Int64
  (let [(parts (stringSplit out ":usage (:input "))]
    (if (<= (listLength parts) 1) 0
      (let [(tail (str ":input " (optionOr (listLast parts) "")))
            (num (fn [(k String)] -> Int64 (optionOr (stringToInt64 (sp/tokAfter tail k)) 0)))]
        (+ (num ":input") (num ":output")))))

; (:m :ref COND4 :do "the writer's cost is its model calls (Leon's :batching :turns) times the gateway row's :costMicros per call; no turns count or no price on the row is -1, which the journal prints as :priced false")
fn leonCost out: String prices: (List (Pair String Int64)) model: String -> Int64
  (let [(turns (optionOr (stringToInt64 (sp/tokAfter out ":turns")) 0))
        (price (match (listFind (fn [(pr (Pair String Int64))] -> Bool (= (pairFirst pr) model)) prices) ((some pr) (pairSecond pr)) ((none) -1)))]
    (if (or (<= turns 0) (< price 0)) -1 (* turns price)))

; (:m :ref WRITEESC :do "the gateway profile a write runs with: a (:writeProfile :tier T :profile P) row of the lanes file wins, else paid and strong use the profiles paidCheap and strong, else the configured one")
fn listAfter s: String key: String -> (List String)
  (match (stringIndexOf s (str key " ("))
    ((none) (list))
    ((some i)
      (let [(rest (optionOr (stringSlice s (+ i (stringLength key) 2) (stringLength s)) ""))]
        (filter (fn [(x String)] -> Bool (not (stringEmpty? x))) (stringSplit (optionOr (listHead (stringSplit rest ")")) "") " ")))))

fn idHash id: String -> Int64
  (let [(bs (stringToBytes id))]
    (fold (fn [(h Int64) (i Int64)] -> Int64 (mod (+ (* h 1000003) (bytesGet bs i)) 2147483647)) 7 (range 0 (bytesLength bs))))

fn slotProfile ps: (List String) ws: (List Int64) slot: Int64 -> String
  (match (listHead ps)
    ((none) "")
    ((some p)
      (let [(w (optionOr (listHead ws) 0))]
        (if (< slot w) p (slotProfile (optionOr (listTail ps) (list)) (optionOr (listTail ws) (list)) (- slot w))))))

; (:m :ref ROTATE :do "a (:writeProfiles :tier T :profiles (P..) :weights (w..)) row picks the profile from a stable hash of the unit id mod the weight sum, so every attempt of a unit keeps its profile and units spread by weight; a malformed row or none gives the base")
fn pickWriteProfile lanes: String id: String lane: String base: String -> String
  (pickWriteProfileH lanes id lane base "")

; (:m :ref SCHED :do "with a :leads (provider ..) list parallel to :profiles on the row and a providerHealth text, each weight is scaled by the clamped ok share of its lead provider (0.2..1.0), so new units shift off saturated providers while a unit that already has a profile keeps it")
fn pickWriteProfileH lanes: String id: String lane: String base: String health: String -> String
  (let [(rows (filter (fn [(l String)] -> Bool (and (stringContains? l "(:writeProfiles ") (= (sp/tokAfter l ":tier") lane))) (stringLines lanes)))]
    (match (listHead rows)
      ((none) base)
      ((some l)
        (let [(ps (listAfter l ":profiles"))
              (ws0 (map (fn [(x String)] -> Int64 (max 0 (optionOr (stringToInt64 x) 0))) (listAfter l ":weights")))
              (leads (listAfter l ":leads"))
              (ws (if (and (not (stringEmpty? health)) (= (listLength leads) (listLength ws0)))
                    (map (fn [(i Int64)] -> Int64 (optionOr (float64ToInt64 (* (int64ToFloat64 (* 100 (optionOr (listGet ws0 i) 0))) (sc/okShareOf health (optionOr (listGet leads i) "")))) 0)) (range 0 (listLength ws0)))
                    ws0))
              (total (fold (fn [(a Int64) (w Int64)] -> Int64 (+ a w)) 0 ws))
              (pick (if (and (> total 0) (= (listLength ps) (listLength ws))) (slotProfile ps ws (mod (idHash id) total)) ""))]
          (if (stringEmpty? pick) base pick)))))

fn writeProfile rc: RealCfg lane: String -> String
  (let [(rows (filter (fn [(l String)] -> Bool (and (stringContains? l "(:writeProfile ") (= (sp/tokAfter l ":tier") lane))) (stringLines (readOr rc.lanes))))
        (given (match (listHead rows) ((some l) (sp/tokAfter l ":profile")) ((none) "")))]
    (cond ((not (stringEmpty? given)) given) ((= lane "paid") "paidCheap") ((= lane "strong") "strong") (else rc.profile)))

fn ! writeProfileFor rc: RealCfg dir: String id: String lane: String -> String
  (pickWriteProfileH (readOr rc.lanes) id lane (writeProfile rc lane) (readOr (str dir "/providerHealth.asn")))

; (:m :ref ATTRACTOR-AB :do "--attractor-ab on splits the write stage into two arms by the parity of the unit id's char-code sum: even runs Leon with :attractor asn, odd without; the arm goes into the write stage's (:profile ...) journal row; off by default, and then no arm is named")
fn armOf id: String -> String
  (if (= (mod (fold (fn [(acc Int64) (ch String)] -> Int64 (+ acc (charCode ch))) 0 (stringChars id)) 2) 0) "asn" "off")

fn writeArm rc: RealCfg id: String -> String
  (if rc.attractorAb (armOf id) "")

fn armExtra arm: String -> String
  (if (= arm "asn") ":attractor asn" "")

; (:m :ref CONDUCTOR-VACUOUS-GATE :do "Leon runs the unit gate once before its first turn and lists the ones already green as :vacuousGates; on a branch with nothing past its base that means the gate passes on the base, so no write can prove it (CONDUCTOR-UNIT-FLAGS got a schema-only commit that way), unless the task calls the gate a regression guard")
fn regressionGuard? task: String -> Bool
  (stringContains? (stringLower task) "regression guard")

fn vacuousWrite? out: String gate: String task: String -> Bool
  (and (not (stringEmpty? gate))
       (and (not (regressionGuard? task))
            (match (stringIndexOf out ":vacuousGates (")
              ((none) false)
              ((some at)
                (let [(rest (optionOr (stringSlice out (+ at 15) (stringLength out)) ""))
                      (listed (str (optionOr (listHead (stringSplit rest "\")")) "") "\""))]
                  (stringContains? listed (st/q gate)))))))

fn vacuousSig gate: String -> String
  (str "vacuousGate: " gate)

fn vacuousSig? sig: String -> Bool
  (stringStartsWith? sig "vacuousGate: ")

; (:m :ref WRITEESC :do "a write whose branch has no commit past its base and no dirty file made no progress; an unreadable count is not a verdict")
fn ! noEdits? p: String base: String -> Bool
  (let [(r (gitOut p (list "rev-list" "--count" (str base "..HEAD"))))]
    (and (= r.exit 0) (and (= (stringTrim r.out) "0") (not (fp/gitDirty? p)))))

fn ! writeRes rc: RealCfg dir: String u: st/Task c: CUnit -> Res
  (let [(path (w/wtPath rc.wt u.id))
        (added (if (fileExists? path) (ok path) (attachOrAdd rc u path)))]
    (match added
      ((err e) (failRes e))
      ((ok p)
        (let [(fresh (noEdits? p u.base))
              (task (taskText dir u))
              (prof (writeProfileFor rc dir u.id c.lane))
              (arm (writeArm rc u.id))
              (_ (fileAppend (journalPath dir) (str "(:profile :unit " (st/q u.id) " :lane " (st/q c.lane) " :profile " (st/q prof) (if (stringEmpty? arm) "" (str " :arm " (st/q arm))) " :at " (n (/ (nowNs) 1000000)) ")\n")))
              (d (fp/runLeonProfileExtra! prof rc.repo p rc.home task u.owns (if (stringEmpty? u.gate) (list) (list u.gate)) rc.leaseSec rc.keys (armExtra arm)))
              (model (fp/modelOf d.out))
              (vacuous (and fresh (vacuousWrite? d.out u.gate task)))
              (_ (if (and (not vacuous) (fp/gitDirty? p)) (fp/driverCommitRow! p u.owns u.id model) false))
              (noEdit (and (= d.exit 0) (noEdits? p u.base)))]
          (Res :tiers "" :ok (if (and (= d.exit 0) (and (not noEdit) (not vacuous))) 1 0) :wt p :branch (str "sh/" u.id) :model model :tokens (leonTokens d.out) :costMicro (leonCost d.out (rs/costRows (readOr (str rc.home "/.asl/gateway.asn")) (readOr rc.lanes)) model) :claimedGreen 0
               :sig (cond (vacuous (vacuousSig u.gate)) ((!= d.exit 0) (gateSig d.out)) (noEdit "noEdit") (else "")) :ms d.ms :exit d.exit :asserts 0 :verdict "")))))

fn ! currentBranch dir: String -> String
  (let [(d (fr/runOne (fr/job (list "git" "-C" dir "rev-parse" "--abbrev-ref" "HEAD") dir (fr/childEnv (list)))))]
    (stringTrim d.out))

; (:m :ref CONDUCTOR :do "merge = asl train onto the dev branch checked out in devRepo, never main; the guard reads the branch in devRepo first; the worktree is collected afterwards")
; (:m :ref COND3 :do "the dev repo is the conductor's own clone and a train onto it runs the audit rules, whose workspaceIsolation rule is red when the repo lists a remote (a plain git clone has origin, so every VPS merge ran red on its base); its remotes are dropped before the train, the source repo is fetched by path")
fn ! dropRemotes! dir: String -> Int64
  (let [(names (filter (fn [(l String)] -> Bool (not (stringEmpty? l))) (map stringTrim (stringLines (gitOut dir (list "remote")).out))))
        (_ (map (fn [(r String)] -> fr/Done (gitOut dir (list "remote" "remove" r))) names))]
    (listLength names))

; (:m :ref COND3 :do "the train runs every suite its changed files reach, and a conductor test among them with ASL_E2E=1 inherited started a nested end-to-end run (a second Leon write and review inside the merge of the first, found on the VPS where the merge ran 780 s); the train's env pins ASL_E2E=0")
fn ! mergeEnv -> (List String)
  (fr/childEnv (list "ASL_E2E=0"))

fn ! mergeRes rc: RealCfg u: st/Task c: CUnit -> Res
  (let [(cur (currentBranch rc.devRepo))]
    (if (or (= rc.devBranch "main") (or (= rc.devBranch "master") (!= cur rc.devBranch)))
      (failRes (str "refused: devRepo is on " cur ", dev branch " rc.devBranch " must not be main"))
      (let [(_ (if (= rc.devRepo rc.repo) 0 (dropRemotes! rc.devRepo)))
            (fetched (if (= rc.devRepo rc.repo) (fr/Done :idx 0 :exit 0 :out "" :ms 0 :verdict "")
                       (gitOut rc.devRepo (list "fetch" "--quiet" rc.repo (str "+refs/heads/" c.branch ":refs/heads/" c.branch)))))
            (d (fr/runOneLimited (fr/job (list (str rc.devRepo "/bin/asl") "train" c.branch "--onto" "HEAD" "--repo" rc.devRepo "--commit") rc.devRepo (mergeEnv))
                                 (fr/limits 3600 200)))]
        (if (and (= fetched.exit 0) (and (= d.exit 0) (not (stringContains? d.out ":commitError"))))
          (let [(_ (w/removeWt! rc.wt u.id true))]
            (Res :tiers "" :ok 1 :wt "" :branch "" :model "" :tokens 0 :costMicro 0 :claimedGreen 0 :sig "" :ms d.ms :exit 0 :asserts 0 :verdict ""))
          (let [(f (failRes (gateSig d.out)))] (with f :ms d.ms))))))

; (:m :ref CONDUCTOR :do "thin adapter for the COND2 ladder: its Ruling action (merge|fix|await|blocked) maps to the review verdict pass|fail|defer|block; an unknown action blocks")
fn rulingVerdict action: String -> String
  (cond ((= action "merge") "pass") ((= action "fix") "fail") ((= action "await") "defer") (else "block"))

; (:m :ref CONDUCTOR :do "review is the COND2 ladder (asl/tools/coord/ladder.asl); until it is wired every review defers and parks the unit")
fn reviewUnwired -> Res
  (Res :tiers "" :ok 0 :wt "" :branch "" :model "" :tokens 0 :costMicro 0 :claimedGreen 0 :sig "review ladder not wired" :ms 0 :exit 0 :asserts 0 :verdict "defer")

fn ! readOr path: String -> String
  (resultOr (fileReadString path) "")

fn baseRef u: st/Task -> String
  (if (stringEmpty? u.base) "main" u.base)

fn ! gitOut dir: String argv: (List String) -> fr/Done
  (fr/runOne (fr/job (listAppend (list "git" "-C" dir) argv) dir (fr/childEnv (list))))

; (:m :ref COND3 :do "red-before: the declared gate is run once more in a detached checkout of the unit's merge-base; its exit and asserts go to the receipt the ladder reads (gatesProven needs a :redBefore row); a gate that is already green at the base leaves no redBefore row, so the ladder cannot merge it on R1")
fn ! redBefore! rc: RealCfg u: st/Task c: CUnit -> (Pair Int64 Int64)
  (let [(mb (gitOut c.wt (list "merge-base" "HEAD" (baseRef u))))
        (sha (stringTrim mb.out))
        (bpath (str c.wt ".base"))
        (_ (gitOut c.wt (list "worktree" "remove" "--force" bpath)))
        (added (gitOut c.wt (list "worktree" "add" "--detach" bpath sha)))]
    (if (or (!= mb.exit 0) (!= added.exit 0)) (pair -1 0)
      (let [(d (fr/runShell! u.gate bpath (fr/childEnv (list)) (fr/heavy (fr/limits rc.gateSec 200) "writer" "")))
            (_ (gitOut c.wt (list "worktree" "remove" "--force" bpath)))]
        (pair d.exit (optionOr (fr/executedOf d.out) 0)))))

fn receiptText u: st/Task g: Res before: (Pair Int64 Int64) -> String
  (str "(:receipt " (st/q u.id) " :gates ((:gate " (st/q u.gate) " :exit " (n g.exit) " :executed " (n g.asserts) "))"
       (if (> (pairFirst before) 0) (str " :redBefore ((:gate " (st/q u.gate) " :exit " (n (pairFirst before)) " :executed " (n (pairSecond before)) "))") "")
       ")")

; (:m :ref COND3 :do "the real gates stage: the conductor's own rerun of the gate in the unit's worktree plus the red-before run, and the receipt written to <store>/runs/UNIT-receipt.asn for the review stage")
fn ! gatesStage rc: RealCfg dir: String u: st/Task c: CUnit -> Res
  (let [(g (gatesRes rc.gateSec (taskText dir u) u c))]
    (if (and (= g.exit 0) (> g.asserts 0))
      (let [(before (redBefore! rc u c))
            (_ (dirCreate (runsDir dir)))
            (_ (fileWrite (runPath dir u.id "receipt" "asn") (str (receiptText u g before) "\n")))]
        g)
      g))

fn ! zoneNow -> lt/Zone
  (resultOr (lt/zoneLoad! (envGet "TZ")) (lt/utcZone))

fn ! pacesNow rc: RealCfg -> (List sp/SubPace)
  (sp/paceSubs (zoneNow) (readOr (str rc.home "/.asl/subscriptions.asn")) (readOr (ul/defaultSharedUsagePath rc.home)) (nowMs))

; (:m :ref COND3 :do "the real review stage: ladder review over the lane table with subPace allowances and the in-process gateway call; the ruling rows are appended to the journal, the ruling action maps to the review verdict, an await names the lane or tier whose refresh wakes the unit")
; (:m :ref COND4 :do "the tiers the ladder's escalate row still offers, as 'strong claude' or 'claude'; empty when the ruling wrote no escalate row")
fn tiersOfRows rows: (List String) -> String
  (match (listFind (fn [(r String)] -> Bool (and (stringStartsWith? r "(:escalate") (stringContains? r " :tiers ("))) rows)
    ((none) "")
    ((some r)
      (let [(rest (optionOr (listGet (stringSplit r " :tiers (") 1) ""))]
        (stringTrim (optionOr (listHead (stringSplit rest ")")) "")))))

fn offersDir dir: String -> String
  (str dir "/offers")

fn offerPath dir: String id: String -> String
  (str (offersDir dir) "/" id ".asn")

; (:m :ref COND4 :do "an offer to the strong lane is a file the next review of that unit consumes: it starts the ladder at R3 once, then is gone")
fn ! offeredRung! dir: String id: String -> String
  (if (fileExists? (offerPath dir id))
    (let [(_ (pathRemove (offerPath dir id)))] "R3")
    "")

fn ! realReview rc: RealCfg dir: String u: st/Task c: CUnit -> Res
  (let [(gatewayText (readOr (str rc.home "/.asl/gateway.asn")))
        (lanesText (readOr rc.lanes))
        (usage (runPath dir u.id "usage" "asn"))
        (_ (pathRemove usage))
        (diff (gitOut c.wt (list "diff" (str (baseRef u) "...HEAD"))))
        (riskRaw (stringTrim (readOr (str dir "/tasks/" u.id ".risk"))))
        (risk (if (stringEmpty? riskRaw) "low" riskRaw))
        (writer (if (or (stringEmpty? c.model) (= c.model "unknown")) rc.writerAlias c.model))
        (ru (l/ReviewUnit :id u.id :task (taskText dir u) :risk risk :closureChanged false :writerAlias writer :writerChannel u.channel
                          :startRung (offeredRung! dir u.id) :fixesUsed c.fails :prior (list)))
        (call (rs/callModelFor! rc.repo usage (rs/costRows gatewayText lanesText)))]
    (match (rs/reviewUnit! gatewayText lanesText (pacesNow rc) rc.repo usage ru diff.out (readOr (runPath dir u.id "receipt" "asn")) call)
      ((err e) (failRes (str "ladder: " e)))
      ((ok r)
        (let [(_ (fileAppend (journalPath dir) (str (stringJoin r.rows "\n") "\n")))]
          (Res :tiers (tiersOfRows r.rows) :ok 0 :wt "" :branch "" :model r.models :tokens r.tokens :costMicro r.costMicro :claimedGreen 0 :sig r.sig :ms 0 :exit 0 :asserts 0
               :verdict (rulingVerdict r.action))))))

; (:m :ref COND3 :do "alias and tier allowances now: every lane alias, and each tier as the largest allowance of its lanes, so a unit parked on a tier name wakes too")
fn ! laneSnapshot rc: RealCfg -> (List (Pair String Int64))
  (let [(gatewayText (readOr (str rc.home "/.asl/gateway.asn")))
        (lanesText (readOr rc.lanes))
        (am (rs/allowanceMap gatewayText lanesText (pacesNow rc)))
        (rows (rs/laneRowsOf lanesText))
        (tiers (map (fn [(t String)] -> (Pair String Int64)
                      (pair t (fold (fn [(a Int64) (r rs/LaneRow)] -> Int64
                                      (if (= r.tier t) (max a (pairSecond (optionOr (listFind (fn [(p (Pair String Int64))] -> Bool (= (pairFirst p) r.alias)) am) (pair "" 0)))) a))
                                    0 rows)))
                    (list "free" "paid" "strong")))]
    (listAppend am tiers))

; (:m :ref COND3 :do "after a subscription refresh, every lane or tier whose allowance rose (a window reset or a raised allowance) calls wake: units parked on it return to review; returns the units woken")
fn ! refreshWake! ctx: Ctx snapshot: (fn ! [] -> (List (Pair String Int64))) refresh: (fn ! [] -> Unit) -> Int64
  (let [(before (snapshot))
        (_ (refresh))
        (after (snapshot))
        (rising (rs/risingLanes before after))]
    (fold (fn [(a Int64) (lane String)] -> Int64 (+ a (wake! ctx lane))) 0 rising))

fn ! startupProblemsFor rc: RealCfg -> (List String)
  (rs/startupProblems (readOr (str rc.home "/.asl/gateway.asn")) (readOr rc.lanes))

fn stopPath dir: String -> String
  (str dir "/stop")

fn ! requestStop! dir: String -> Bool
  (ok? (fileWrite (stopPath dir) "stop\n"))

; (:m :ref COND4 :do "the queue consumer: a blocked unit whose newest escalate row offers the strong tier first gets a fresh lease and an offer file and goes back to awaitReview, where the review starts at R3 (the strong lane); only when the strong tier has allowance now (subPace), at most that many per call; a row whose tiers are only (claude) is left for Claude")
fn lastTiers rows: (List String) id: String -> String
  (fold (fn [(acc String) (r String)] -> String
          (if (and (stringContains? r (str ":unit " (st/q id) " ")) (stringContains? r " :tiers ("))
            (stringTrim (optionOr (listHead (stringSplit (optionOr (listGet (stringSplit r " :tiers (") 1) "") ")")) ""))
            acc))
        "" rows)

fn ! offerStrong! ctx: Ctx snapshot: (fn ! [] -> (List (Pair String Int64))) -> Int64
  (let [(allow (pairSecond (optionOr (listFind (fn [(p (Pair String Int64))] -> Bool (= (pairFirst p) "strong")) (snapshot)) (pair "strong" 0))))
        (rows (stringLines (readOr (escalationsPath ctx.dir))))
        (cands (filter (fn [(c CUnit)] -> Bool (and (= c.st "blocked") (and (= c.esc 1) (stringStartsWith? (lastTiers rows c.id) "strong")))) (readCUnits! ctx.dir)))]
    (if (<= allow 0) 0
      (fold (fn [(done Int64) (c CUnit)] -> Int64
              (if (>= done allow) done
                (match (st/claim! ctx.dir c.id ctx.holder ctx.ttlMs)
                  ((err _) done)
                  ((ok text)
                    (let [(epoch (match (st/parseLease text) ((ok l) l.epoch) ((err _) 0)))
                          (_ (dirCreate (offersDir ctx.dir)))
                          (_ (fileWrite (offerPath ctx.dir c.id) (str "(:offer :unit " (st/q c.id) " :to strong :at " (n (nowMs)) ")\n")))
                          (_ (move! ctx (with c :esc 0 :fails 0 :sig "" :parked 0 :epoch epoch :await "") "awaitReview" "queue" "" 0 0 "offerStrong" 0))]
                      (+ done 1))))))
            0 cands)))

; (:m :ref COND5 :do "intake each service cycle: <store>/ledger.path (written by run from --ledger, line 1 the ledger, line 2 the base ref) names the plan ledger, which planImport reads and never writes; every parked row it leaves is written once as a (:need :unit :needs :do) escalation row, deduped by unit id, and status lists them")
fn ledgerPath dir: String -> String
  (str dir "/ledger.path")

fn ! parkedRows! dir: String -> (List (Pair String String))
  (fold (fn [(acc (List (Pair String String))) (line String)] -> (List (Pair String String))
          (match (st/rowFields line "parked")
            ((err _) acc)
            ((ok fs) (listAppend acc (list (pair (st/textField fs "id") (str (st/textField fs "need") "\n" (st/textField fs "do"))))))))
        (list) (stringLines (readOr (str dir "/parked.asn"))))

fn ! needRows! dir: String -> Int64
  (let [(have (readOr (escalationsPath dir)))
        (todo (filter (fn [(p (Pair String String))] -> Bool (and (not (stringEmpty? (pairFirst p))) (not (stringContains? have (str "(:need :unit " (st/q (pairFirst p)) " "))))) (parkedRows! dir)))
        (_ (map (fn [(p (Pair String String))] -> (Result Unit String)
                  (let [(parts (stringSplit (pairSecond p) "\n"))]
                    (fileAppend (escalationsPath dir) (str "(:need :unit " (st/q (pairFirst p)) " :needs " (optionOr (listHead parts) "") " :do " (st/q (stringJoin (optionOr (listTail parts) (list)) " ")) ")\n"))))
                todo))]
    (listLength todo))

fn ! importCycle! ctx: Ctx -> Int64
  (let [(cfg (stringLines (readOr (ledgerPath ctx.dir))))
        (ledger (stringTrim (optionOr (listGet cfg 0) "")))
        (base (let [(b (stringTrim (optionOr (listGet cfg 1) "")))] (if (stringEmpty? b) "HEAD" b)))]
    (if (stringEmpty? ledger) 0
      (match (fileReadString ledger)
        ((err _) 0)
        ((ok text)
          (match (pi/plan! text ctx.dir base false)
            ((err _) 0)
            ((ok r) (let [(_ (needRows! ctx.dir))] (listLength r.put))))))))

; (:m :ref COND3 :do "no signal handler exists in ASL, so the loop's stop is cooperative: a stop file in the store (written by `conductor stop`, which the service runs as ExecStop) ends the loop after stopAll!; a raw SIGTERM or SIGKILL leaves stage children running and the next start resumes them from the rows")
fn ! loopOnce! ctx: Ctx snapshot: (fn ! [] -> (List (Pair String Int64))) refresh: (fn ! [] -> Unit) refreshDue: Bool -> Bool
  (if (fileExists? (stopPath ctx.dir))
    (let [(_ (stopAll! ctx)) (_ (pathRemove (stopPath ctx.dir)))] false)
    (let [(_ (importCycle! ctx))
          (_ (tick! ctx))
          (_ (offerStrong! ctx snapshot))
          (_ (if refreshDue (refreshWake! ctx snapshot refresh) 0))]
      true))

fn ! sleepSlices! dir: String slices: Int64 sliceMs: Int64 -> Unit
  (if (or (<= slices 0) (fileExists? (stopPath dir))) ()
    (let [(_ (sleepMs sliceMs))] (sleepSlices! dir (- slices 1) sliceMs)))

fn ! runLoop! ctx: Ctx snapshot: (fn ! [] -> (List (Pair String Int64))) refresh: (fn ! [] -> Unit) lastRefresh: Int64 everyMs: Int64 tickSlices: Int64 -> Int64
  (let [(due (>= (- (nowMs) lastRefresh) everyMs))]
    (if (loopOnce! ctx snapshot refresh due)
      (let [(_ (sleepSlices! ctx.dir tickSlices 5000))]
        (runLoop! ctx snapshot refresh (if due (nowMs) lastRefresh) everyMs tickSlices))
      0))

fn ! realRes rc: RealCfg dir: String stage: String u: st/Task c: CUnit -> Res
  (cond
    ((= stage "write") (writeRes rc dir u c))
    ((= stage "gates") (gatesStage rc dir u c))
    ((= stage "review") (realReview rc dir u c))
    ((= stage "merge") (mergeRes rc u c))
    (else (failRes (str "unknown stage " stage))))

fn ! loadUnit! dir: String id: String -> (Option (Pair st/Task CUnit))
  (match (st/readUnits! dir)
    ((err _) (none))
    ((ok units)
      (match (listFind (fn [(u st/Task)] -> Bool (= u.id id)) units)
        ((none) (none))
        ((some u) (match (listFind (fn [(c CUnit)] -> Bool (= c.id id)) (readCUnits! dir))
                    ((none) (none))
                    ((some c) (some (pair u c))))))))

fn ! realCfg args: (List String) dir: String -> RealCfg
  (let [(repo (st/opt args "repo" "."))]
    (RealCfg :repo repo :devRepo (st/opt args "dev-repo" repo) :devBranch (st/opt args "dev" "dev")
             :wt (w/Cfg :repo repo :base (st/opt args "worktrees" (str repo "/../worktrees")) :prefix "asex-" :archive (st/opt args "archive" (str dir "/archive")) :mainRef "main")
             :home (st/opt args "home" (resultOr (getHomeDir) ".")) :keys (st/opt args "keys" (str repo "/.env.free")) :leaseSec 3600 :gateSec 3600
             :lanes (st/opt args "lanes" (str repo "/.asl/mem/work/CAL/reviewLanes.asn")) :writerAlias (st/opt args "writer-alias" "") :profile (st/opt args "profile" "freeBulk")
             :attractorAb (= (st/opt args "attractor-ab" "off") "on")))

; (:m :ref CONDUCTOR :do "the stage child: conductor.asl stage STAGE UNIT --store DIR runs one stage for one unit and writes its Res row, printing nothing; a crash leaves no row and the poll reports the stage died")
fn ! stageMain! args: (List String) dir: String -> Int64
  (let [(stage (optionOr (listGet args 1) ""))
        (id (optionOr (listGet args 2) ""))]
    (match (loadUnit! dir id)
      ((none) 2)
      ((some pr)
        (let [(res (realRes (realCfg args dir) dir stage (pairFirst pr) (pairSecond pr)))]
          (match (writeRes! dir id stage res) ((ok _) 0) ((err _) 1))))))

; (:m :ref CONDUCTOR :do "the real launch: bin/asl run conductor.asl stage ... with the options the child needs to rebuild its RealCfg")
fn realLaunch args: (List String) dir: String -> (fn [String st/Task CUnit] -> (List String))
  (let [(repo (st/opt args "repo" "."))
        (pass (fold (fn [(acc (List String)) (k String)] -> (List String)
                      (if (stringEmpty? (st/opt args k "")) acc (listAppend acc (list (str "--" k) (st/opt args k "")))))
                    (list) (list "repo" "dev-repo" "dev" "worktrees" "archive" "home" "keys" "lanes" "writer-alias" "profile" "attractor-ab")))]
    (fn [(stage String) (u st/Task) (c CUnit)] -> (List String)
      (listAppend (list (str repo "/bin/asl") "run" (str repo "/asl/tools/coord/conductor.asl") "stage" stage u.id "--store" dir) pass)))

fn ! main args: (List String) -> (Result Int64 String)
  (let [(cmd (optionOr (listHead args) ""))
        (dir (st/opt args "store" (str (resultOr (getHomeDir) ".") "/.asl/run/conductor")))
        (rc (realCfg args dir))
        (ctx (Ctx :dir dir :holder (str "conductor" (n (procSelf))) :ttlMs 3600000 :maxWait (st/intOpt args "max-wait" 30) :maxSame 3
                  :stageSec (st/intOpt args "stage-sec" 4200) :maxDesc 200 :launch (realLaunch args dir) :pace (schedPace dir rc.home)))]
    (cond
      ((= cmd "stage") (ok (stageMain! args dir)))
      ((= cmd "tick") (match (tick! ctx) ((ok c) (do (println (str "(:tick :changed " (n c) ")")) (ok 0))) ((err e) (do (eprintln e) (ok 1)))))
      ((= cmd "status") (do (println (status! ctx)) (ok 0)))
      ((= cmd "wake") (let [(lane (optionOr (listGet args 1) ""))]
                        (do (println (str "(:wake :lane " (st/q lane) " :units " (n (wake! ctx lane)) ")")) (ok 0))))
      ((= cmd "check") (let [(ps (startupProblemsFor rc))]
                         (do (println (str "(:check :problems " (st/qList ps) ")")) (ok (if (listEmpty? ps) 0 1)))))
      ((= cmd "stop") (do (println (str "(:stop :requested " (if (requestStop! dir) "true" "false") ")")) (ok 0)))
      ((= cmd "run")
        (let [(ps (startupProblemsFor rc))]
          (if (not (listEmpty? ps))
            (do (eprintln (str "(:refuse :why coverage :problems " (st/qList ps) ")")) (ok 1))
            (let [(_ (pathRemove (stopPath dir)))
                  (_ (let [(l (st/opt args "ledger" ""))] (if (stringEmpty? l) (ok ()) (fileWrite (ledgerPath dir) (str l "\n" (st/opt args "ledger-base" "HEAD") "\n")))))
                  (_ (println (str "(:run :store " (st/q dir) " :refreshMin " (n (st/intOpt args "refresh-min" 15)) ")")))]
              (ok (runLoop! ctx (fn [] -> (List (Pair String Int64)) (laneSnapshot rc)) (fn [] -> Unit (let [(_ (sr/subsRefreshCli! (list)))] ()))
                            (nowMs) (* (st/intOpt args "refresh-min" 15) 60000) 12))))))
      (else (do (eprintln "usage: conductor tick|run|status|check|stop|wake LANE --store DIR") (ok 2)))))
