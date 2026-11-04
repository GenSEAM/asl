(module asl-tools/coord/conductor
  :x [hubGuard! leonGuard! staleSig? staleField staleWake! unitHead! cdErrors repoPath gradeCommitsPath gradeCommitRecorded? ledgerForged! settleWt! worktreeValid? ownedStates! briefTask! writeResWith repoBrokenPath repoErr! repoGate! ledgerState! ledgerSig! seedGradeCommits! ledgerGuard receiptRowOf fail! finish! step! providerRequeue! worktreesPath wtBase servedField servedAliasOf servedModel journalA! wipSave! gradeLand! staleOwnsFor! CUnit Res Pace Ctx RealCfg
      cuDir cuPath journalPath escalationsPath runsDir runPath runRow renderCUnit parseCUnit readCUnits! writeCUnit! costText renderRes parseRes
      allowanceUnlimited fixedPace jobserverPace gateSig trainSig mergeBusy? rulingVerdict
      depStalled? armOf writeArm armExtra vacuousWrite? vacuousSig vacuousSig? ownedChanges! commitWrite! noEdits? blankSlate? vacuousAround! aheadGreen! onBaseRun! checkOne! gateTimeoutSig gateRowOf gateErrors gateCheckS gateTimeoutSig? move! waitMore! parkedOf gateTimeoutRequeue! wakeRowsOf wakeErrors freeWake! blockSig reuseWt! baseNote! promoteDev! pickWriteProfile pickWriteProfileH pickWriteProfileX writeProfileFor stalledProfilesOf stalledProfilePath schedPace lightSlotsAt! rungCap hopsSince pfDefaultPatterns pfRowOf pfPatterns pfBackoffS pfMaxInRow pfErrors pfCfg providerFailSig? noCommits? providerHit? providerWaiting? pwLast offerBacklog! leadBacklogCap leadFresh? leadTtlMs nextRung! priorNote! tick! wake! status! drain! stopAll! gatesRes redBaseRow redBaseHit redCached! loadUnit! writeRes! realRes realLaunch attachOrAdd parkedRows! needRows! importCycle! ledgerPath offerStrong! lastTiers tiersOfRows offeredRung! offerPath freshBase! leonTokens leonCost dropRemotes! mergeEnv realPace      settled? realCfg sigKey laneSnapshot refreshWake! startupProblemsFor stopPath requestStop! restartPath draining? requestRestart! restartUntil! flyingIds! restart! loopOnce! runLoop! gatesStage
      stallProbes stallHooks stallRequeue! requeuePath requestRequeue! requeueDrain! depWake! wrRowOf wrCfg wrErrors wrMinFreeMb admitWriter? warmWait! writerHeld? firstCallSeen? warmPath
      main]
  :i [(asl-tools/coord/store :a st) (asl-gates/auditLanded :a al) (asl-tools/coord/grade :a gr) (asl-tools/coord/planImport :a pi) (asl-tools/coord/brief :a bf) (asl-tools/coord/worktree :a w) (asl-tools/coord/sched :a sc) (asl-tools/coord/stall :a stl) (asl-tools/fleet/run :a fr) (asl-tools/fleet/jobserver :a js) (tools/fleet/freePool :a fp) (tools/fleet/leonClient :a lc) (asl-tools/hub/preflight :a hp)
      (asl-parser/lexer :a lx) (asl-parser/ast :a ast) (asl-tools/coord/reviewStage :a rs) (asl-tools/coord/ladder :a l) (asl-tools/coord/gateGuard :a gg) (aslGateway/subPace :a sp) (aslGateway/localTime :a lt) (aslGateway/usageLedger :a ul) (aslGateway/subsRefresh :a sr)])

; (:m :ref CONDUCTOR :do "deterministic scheduler, no model in the loop: units are store rows (:after = deps, :owns, :gate, :channel = lane), the conductor keeps one state row per unit under <dir>/cond and appends one journal row per transition; the store lease is held from writing to merging so owns stay disjoint, and the store row turns done only when the unit is merged")

; (:m :do "states: queued ready writing gating awaitReview reviewing merging merged blocked failed")
(schema CUnit
  (:f id String) (:f st String) (:f lane String) (:f fails Int64) (:f sig String) (:f waited Int64) (:f parked Int64)
  (:f epoch Int64) (:f branch String) (:f wt String) (:f model String) (:f tokens Int64) (:f costMicro Int64) (:f esc Int64) (:f launched Int64) (:f await String))

; (:m :ref CONDUCTOR :do "a stage runs as a detached child process and leaves one Res row at <store>/runs/UNIT-STAGE.asn; fields are the union of the four stages: write sets ok wt branch model tokens costMicro claimedGreen sig, gates sets exit asserts sig, review sets verdict pass|fail|defer|block model tokens costMicro sig, merge sets ok sig; defer parks the unit until wake(lane), block escalates")
(schema Res
  (:f ok Int64) (:f wt String) (:f branch String) (:f model String) (:f tokens Int64) (:f costMicro Int64) (:f claimedGreen Int64)
  (:f sig String) (:f ms Int64) (:f exit Int64) (:f asserts Int64) (:f verdict String) (:f tiers String) (:f alias String :default ""))

; (:m :ref CONDUCTOR :do "the admission interface SUBPACE plugs into: tokens = how many units may be in flight at once on this machine (jobserver pool size), allowance lane = how many of them may belong to that lane; a tick admits min(ready, tokens - inFlight, allowance lane - inFlight lane)")
(schema Pace
  (:f tokens (fn [] -> Int64))
  (:f allowance (fn [String] -> Int64)))

; (:m :ref CONDUCTOR :do "launch stage unit state -> argv of the detached child that performs the stage and writes its Res row; stageSec is the child deadline recorded in the store run row, maxDesc its descendant limit")
(schema Ctx
  (:f dir String) (:f holder String) (:f ttlMs Int64) (:f maxWait Int64) (:f maxSame Int64) (:f stageSec Int64) (:f maxDesc Int64)
  (:f launch (fn [String st/Task CUnit] -> (List String))) (:f pace Pace))

(schema RealCfg
  (:f repo String) (:f devRepo String) (:f devBranch String) (:f wt w/Cfg) (:f home String) (:f keys String) (:f leaseSec Int64) (:f gateSec Int64) (:f lanes String) (:f writerAlias String) (:f profile String) (:f attractorAb Bool) (:f leonPool String :default ""))

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
  (journalA! ctx c to stage model "" tokens cost verdict ms)

; (:m :ref SERVED-ALIAS-JOURNAL :do "a transition row carries :alias A after :model when the writer's receipt named the served alias; an unknown alias adds nothing")
fn ! journalA! ctx: Ctx c: CUnit to: String stage: String model: String alias: String tokens: Int64 cost: Int64 verdict: String ms: Int64 -> (Result Unit String)
  (fileAppend (journalPath ctx.dir)
    (str "(:t :unit " (st/q c.id) " :from " c.st " :to " to " :stage " stage " :model " (st/q model) (if (stringEmpty? alias) "" (str " :alias " (st/q alias))) " :tokens " (n tokens)
         " :costUsd " (costText (max 0 cost)) (if (< cost 0) " :priced false" "") " :verdict " (st/q verdict) " :ms " (n ms) " :at " (n (/ (nowNs) 1000000)) ")\n"))

; (:m :ref INTAKE-PARKED-WAKE :do "every block carries a signature: a unit moved to blocked with none gets STAGE: REASON from the move itself, so no blocked row is blank and a blocked unit always says why")
fn blockSig stage: String verdict: String -> String
  (str (if (stringEmpty? stage) "blocked" stage) ": " (if (stringEmpty? verdict) "blocked" verdict))

; (:m :ref CONDUCTOR :do "every state change goes through move!: the journal row first, then the unit row with the spend added, so a crash between them replays as the same transition")
fn ! move! ctx: Ctx c: CUnit to: String stage: String model: String tokens: Int64 cost: Int64 verdict: String ms: Int64 -> CUnit
  (moveA! ctx c to stage model "" tokens cost verdict ms)

fn ! moveA! ctx: Ctx c: CUnit to: String stage: String model: String alias: String tokens: Int64 cost: Int64 verdict: String ms: Int64 -> CUnit
  (let [(next (with c :launched 0 :st to :tokens (+ c.tokens tokens) :costMicro (+ c.costMicro (max 0 cost)) :model (if (stringEmpty? model) c.model model)
                    :sig (if (and (= to "blocked") (stringEmpty? c.sig)) (blockSig stage verdict) c.sig)))
        (_ (journalA! ctx c to stage model alias tokens cost verdict ms))
        (_ (writeCUnit! ctx.dir next))]
    next)

; (:m :ref SERVED-ALIAS-JOURNAL :do "the model a write is journalled under comes from Leon's receipt: :servedAlias A, else :servedModel M, else the older literal :model tag (modelOf, unknown when absent); the alias alone is also journalled as :alias; review's writer exclusion (reviewWriter) reads the unit's model, so it sees the served alias and never an unknown family when the receipt named one")
; (:m :ref SERVED-ALIAS-JOURNAL :do "receiptRowOf is the last line of the output that starts with (: and carries :usage, Leon's final receipt row; servedField parses that one row as an ASN form and reads the key from it, so an echoed line earlier in the output never decides")
fn receiptRowOf out: String -> String
  (optionOr (listLast (filter (fn [(l String)] -> Bool (and (stringStartsWith? l "(:") (stringContains? l ":usage")))
                              (map stringTrim (stringLines out)))) "")

fn servedField out: String key: String -> String
  (al/rowText (receiptRowOf out) (if (stringStartsWith? key ":") (optionOr (stringSlice key 1 (stringLength key)) key) key))

fn servedAliasOf out: String -> String
  (servedField out ":servedAlias")

fn servedModel out: String -> String
  (let [(a (servedAliasOf out))
        (m (servedField out ":servedModel"))]
    (cond ((not (stringEmpty? a)) a) ((not (stringEmpty? m)) m) (else (fp/modelOf out))))

fn ! escalateTiered! ctx: Ctx c: CUnit seen: String tried: String tiers: String -> CUnit
  (let [(_ (if (= c.esc 0)
             (fileAppend (escalationsPath ctx.dir) (str "(:escalate :unit " (st/q c.id) " :seen " (st/q seen) " :tried " (st/q tried) (if (stringEmpty? tiers) "" (str " :tiers (" tiers ")")) ")\n"))
             (ok ())))]
    (with c :esc 1))

fn ! escalate! ctx: Ctx c: CUnit seen: String tried: String -> CUnit
  (escalateTiered! ctx c seen tried "")

fn ! dropLease! ctx: Ctx c: CUnit -> Unit
  (let [(_ (if (> c.epoch 0) (st/release! ctx.dir c.id c.epoch) (ok "")))] ())

; (:m :ref COORD-WIP-RESCUE :do "the worktree base of the conductor: <store>/worktrees.path, written by run from --worktrees, else repo/../worktrees; every path derived from a unit id (wip rescue, grade row, stall probe) follows it")
fn worktreesPath dir: String -> String
  (str dir "/worktrees.path")

fn wtBase dir: String repo: String -> String
  (let [(given (stringTrim (readOr (worktreesPath dir))))]
    (if (stringEmpty? given) (str repo "/../worktrees") given))

; (:m :ref COORD-WIP-RESCUE :do "a unit whose writer is killed, loses its lease or stops without landing never leaves a dirty worktree: its edits become one wip commit on the unit branch and one (:wip :unit :reason :branch :sha) journal row, then the unit is released; a clean or absent worktree writes nothing, a failed commit writes (:wipFailed ...) and keeps the edits in place")
fn wipRow id: String reason: String path: String r: (Result String String) left: Int64 outside: Int64 -> String
  (match r
    ((ok sha) (cond
                ((not (stringEmpty? sha)) (str "(:wip :unit " (st/q id) " :reason " (st/q reason) " :branch " (st/q (str "sh/" id)) " :sha " (st/q sha) (if (> left 0) (str " :left " (n left)) "") (if (> outside 0) (str " :leftOutside " (n outside)) "") ")"))
                ((or (> left 0) (> outside 0)) (str "(:wip :unit " (st/q id) " :reason " (st/q reason) " :committed 0 :left " (n left) (if (> outside 0) (str " :leftOutside " (n outside)) "") ")"))
                (else "")))
    ((err e) (if (= e "notAWorktree")
               (str "(:wip :unit " (st/q id) " :skipped " (st/q reason) " :why " (st/q (str "not a worktree of the repo: " path)) ")")
               (str "(:wipFailed :unit " (st/q id) " :reason " (st/q reason) " :err " (st/q e) ")"))))

fn ! wipSave! ctx: Ctx id: String reason: String -> Unit
  (let [(repo (stringTrim (readOr (repoPath ctx.dir))))]
    (if (stringEmpty? repo) ()
      (let [(cfg (w/Cfg :repo repo :base (wtBase ctx.dir repo) :prefix "asex-" :archive (str ctx.dir "/archive") :mainRef "main"))
            (recorded (match (cuOf (readCUnits! ctx.dir) id) ((some c) c.wt) ((none) "")))
            (path (if (stringEmpty? recorded) (w/wtPath cfg id) recorded))
            (live (w/isWorktreeOf! cfg path))
            (owns (match (st/readUnits! ctx.dir) ((ok us) (match (listFind (fn [(u st/Task)] -> Bool (= u.id id)) us) ((some u) u.owns) ((none) (list)))) ((err _) (list))))
            (res (if live (w/wipCommitOwned! cfg id path reason owns) (err "notAWorktree")))
            (left (if live (listLength (w/secretUntracked! path)) 0))
            (outside (if live (listLength (w/outsideUntracked! path owns)) 0))
            (row (wipRow id reason path res left outside))
            (_ (if (stringEmpty? row) (ok ()) (fileAppend (journalPath ctx.dir) (str row "\n"))))]
        ())))

; (:m :ref LANDED-AUDIT :do "a review pass lands with its verdict: one (:grade :ev UNIT :sha HEAD :verdict pass :by FAMILY :at ISO) row is appended to .asl/mem/grades.asn in the unit worktree and committed on the unit branch, so a merge or cherry-pick of the branch carries it; a worktree that is not one of the repo, or a failed append or commit, journals a gradeSkipped row and never blocks the merge; the ledger is rebuilt from the committed HEAD version plus the one conductor row, never from the worktree file, so a row a writer left in the working tree is overwritten and never committed")
fn ! gradeLand! ctx: Ctx c: CUnit unit: String model: String -> Unit
  (let [(repo (stringTrim (readOr (repoPath ctx.dir))))
        (cfg (w/Cfg :repo repo :base (wtBase ctx.dir repo) :prefix "asex-" :archive (str ctx.dir "/archive") :mainRef "main"))
        (path (if (stringEmpty? c.wt) (w/wtPath cfg unit) c.wt))
        (skip (fn [(why String)] -> Unit (let [(_ (fileAppend (journalPath ctx.dir) (str "(:gradeSkipped :unit " (st/q unit) " :why " (st/q why) ")\n")))] ())))]
    (if (or (stringEmpty? repo) (not (w/isWorktreeOf! cfg path))) (skip "not a worktree of the repo")
      (let [(head (stringTrim (gitOut path (list "rev-parse" "HEAD")).out))
            (mb (stringTrim (gitOut path (list "merge-base" "HEAD" "main")).out))
            (row (al/gradeRow unit head mb "pass" (gr/familyOf model) (al/isoOfMs (nowMs))))
            (file (str path "/" (al/ledgerPath)))
            (_ (dirCreate (str path "/.asl")))
            (_ (dirCreate (str path "/.asl/mem")))
            (shown (gitOut path (list "show" (str "HEAD:" (al/ledgerPath)))))
            (old (if (= shown.exit 0) shown.out (str "(:gradesHead :since " (st/q (if (stringEmpty? mb) head mb)) " :note \"branch without a ledger\")\n")))
            (wrote (fileWrite file (str old (if (or (stringEmpty? old) (stringEndsWith? old "\n")) "" "\n") row "\n")))
            (added (gitOut path (list "add" "--" (al/ledgerPath))))
            (done (gitOut path (list "-c" "user.name=conductor" "-c" "user.email=conductor@localhost" "-c" "commit.gpgsign=false" "commit" "-q" "--no-verify" "-m"
                                     (str "(:c :a grade :do " (st/q (str "unit " unit " review pass")) " :g review :ev (" unit "))") "--" (al/ledgerPath))))]
        (if (and (ok? wrote) (and (= added.exit 0) (= done.exit 0)))
          (let [(newSha (stringTrim (gitOut path (list "rev-parse" "HEAD")).out))
                (_ (fileAppend (gradeCommitsPath ctx.dir) (str "(:gradeCommit :unit " (st/q unit) " :sha " (st/q newSha) " :row " (st/q row) ")\n")))
                (_ (fileAppend (journalPath ctx.dir) (str "(:gradeLanded :unit " (st/q unit) " :sha " (st/q head) ")\n")))]
            ())
          (skip (str "grade commit failed: " (stringTrim (str added.out done.out))))))))

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
; (:m :ref ESC-LADDER :do "the ladder: free writers retry maxSame times per signature (L0), paid is the DeepSeek Flash fixer (L1), strong our strong paid models (L2), lead parks the unit blocked with :await lead (L3); a unit on paid or strong passes up after its second failure whatever the signature")
fn writeTiers -> (List String)
  (list "free" "paid" "strong" "lead")

fn rungLimit ctx: Ctx lane: String -> Int64
  (if (or (= lane "paid") (= lane "strong")) 2 ctx.maxSame)

fn ladderPath dir: String -> String
  (str dir "/ladder.asn")

; (:m :ref ESC-LADDER :do "a (:rung :tier T :perDay N) row of <store>/ladder.asn caps the units that enter rung T per UTC day; no row is no cap; lead is never capped")
fn rungCap text: String rung: String -> Int64
  (match (listFind (fn [(l String)] -> Bool (and (stringStartsWith? (stringTrim l) "(:rung ") (= (sp/tokAfter l ":tier") rung))) (stringLines text))
    ((some l) (optionOr (stringToInt64 (sp/tokAfter l ":perDay")) -1))
    ((none) -1))

fn hopsSince rows: (List String) rung: String since: Int64 -> Int64
  (listLength (filter (fn [(l String)] -> Bool
                        (and (stringContains? l (str "->" rung ": "))
                             (and (stringContains? l "tierHop ") (>= (optionOr (stringToInt64 (sp/tokAfter l ":at")) 0) since))))
                      rows))

; (:m :ref ESC-LEAD-HOOK :do "the lead rung is open only while <store>/leadOnline.asn (:leadOnline :at MS), written by a follower of vps events --class lead, is younger than leadTtlMs (adopted 120000: the follower polls every 2 s); no row, an unreadable row or a stale one means no lead is online and the ladder blocks the unit with the plain escalate row")
fn leadTtlMs -> Int64
  120000

fn leadFresh? text: String now: Int64 -> Bool
  (let [(at (optionOr (stringToInt64 (sp/tokAfter (stringTrim text) ":at")) -1))]
    (and (>= at 0) (<= (- now at) (leadTtlMs))))

; (:m :ref ESC-LEAD-HOOK :do "entering the lead rung appends one (:lead :unit :at :seen :tried) row to escalations.asn, the row a follower of class lead receives; the plain escalate row is kept for its other readers")
fn ! leadRow! dir: String c: CUnit seen: String tried: String -> Bool
  (ok? (fileAppend (escalationsPath dir) (str "(:lead :unit " (st/q c.id) " :at " (n (/ (nowNs) 1000000)) " :seen " (st/q seen) " :tried " (st/q (verdictSig tried)) ")\n")))

fn ! rungOpen? dir: String rung: String now: Int64 -> Bool
  (let [(cap (rungCap (readOr (ladderPath dir)) rung))]
    (if (= rung "lead") (leadFresh? (readOr (str dir "/leadOnline.asn")) now) (or (< cap 0) (< (hopsSince (stringLines (readOr (journalPath dir))) rung (- now (mod now 86400000))) cap))))

; (:m :ref ESC-LEAD-HOOK :do "the newest :at over the rows that name the unit and carry the marker, -1 when none")
fn rowsAt rows: (List String) id: String marker: String -> Int64
  (fold (fn [(a Int64) (l String)] -> Int64
          (if (and (stringContains? l (str ":unit " (st/q id) " ")) (stringContains? l marker))
            (max a (optionOr (stringToInt64 (sp/tokAfter l ":at")) -1))
            a))
        -1 rows)

; (:m :ref ESC-LEAD-HOOK :do "while the heartbeat is fresh, each unit blocked on a plain escalate (no :await lead) whose newest blocked move is newer than its newest (:lead row gets one (:lead row, oldest blocked first, at most leadBacklogCap per tick; the row's :at is newer than the blocked move, so the next tick offers nothing twice; returns the rows written")
fn leadBacklogCap -> Int64
  20

fn ! offerBacklog! dir: String now: Int64 -> Int64
  (if (not (leadFresh? (readOr (str dir "/leadOnline.asn")) now)) 0
    (let [(cands (filter (fn [(c CUnit)] -> Bool (and (= c.st "blocked") (and (stringEmpty? c.await) (= c.esc 1)))) (readCUnits! dir)))]
      (if (listEmpty? cands) 0
        (let [(jr (stringLines (readOr (journalPath dir))))
              (er (stringLines (readOr (escalationsPath dir))))
              (pend (filter (fn [(p (Pair CUnit Int64))] -> Bool (< (rowsAt er (pairFirst p).id "(:lead ") (pairSecond p)))
                            (map (fn [(c CUnit)] -> (Pair CUnit Int64) (pair c (rowsAt jr c.id " :to blocked "))) cands)))
              (take (listTake (listSortBy (fn [(p (Pair CUnit Int64))] -> Int64 (pairSecond p)) pend) (leadBacklogCap)))
              (wrote (map (fn [(p (Pair CUnit Int64))] -> Bool (leadRow! dir (pairFirst p) (str "backlog: blocked on " (pairFirst p).lane) (pairFirst p).sig)) take))]
          (listLength wrote)))))

; (:m :ref ESC-LADDER :do "the rung above lane whose daily cap has room; a capped rung is skipped")
fn ! nextRung! dir: String lane: String now: Int64 -> Option String
  (let [(tiers (writeTiers))
        (i (optionOr (listFind (fn [(k Int64)] -> Bool (= (optionOr (listGet tiers k) "") lane)) (range 0 (listLength tiers))) -1))]
    (if (< i 0) (none)
      (listFind (fn [(r String)] -> Bool (rungOpen? dir r now)) (optionOr (listSlice tiers (+ i 1) (listLength tiers)) (list)))))

; (:m :ref ESC-LADDER :do "every hop appends the failure that caused it as one line lane<TAB>signature, the lead hop too")
fn ! priorWrite! dir: String id: String lane: String sig: String -> Unit
  (let [(_ (dirCreate (runsDir dir)))
        (_ (fileAppend (runPath dir id "prior" "txt") (str lane "\t" (verdictSig sig) "\n")))]
    ())

fn priorEntry line: String -> String
  (let [(parts (stringSplit line "\t"))]
    (str (optionOr (listHead parts) "") ": " (stringJoin (optionOr (listTail parts) (list)) " ")))

; (:m :ref ESC-LADDER :do "the fixer on the next rung gets the newest failure as :last and the earlier rungs' failures as :history, oldest first; the earlier commits stay on the branch")
; (:m :ref CONDUCTOR-ASN-NOTES :do "a stall entry rides raw only when the reader finds exactly one form in it; a prefix and suffix test passes two forms or a torn one")
fn oneStallForm? entry: String -> Bool
  (and (stringStartsWith? entry "(:stall ")
       (match (ast/readForms (lx/tokenize entry))
         ((ok forms) (= (listLength forms) 1))
         ((err _) false)))

fn ! priorNote! dir: String id: String -> String
  (let [(rows (filter (fn [(l String)] -> Bool (not (stringEmpty? (stringTrim l)))) (stringLines (readOr (runPath dir id "prior" "txt")))))]
    (match (listLast rows)
      ((none) "")
      ((some last)
        (let [(entry (stringJoin (optionOr (listTail (stringSplit last "\t")) (list)) " "))]
          (str "(:prior :last " (if (oneStallForm? entry) entry (st/q entry))
               " :history (" (stringJoin (map (fn [(l String)] -> String (st/q (priorEntry l))) (listTake rows (- (listLength rows) 1))) " ") ") :branchHas commits)")))))

; (:m :ref CONDUCTOR :do "a stage failure releases the lease and retries from ready; the same failure signature maxSame times in a row writes one escalate row and parks the unit in blocked; WRITEESC: a write failure with a higher tier left hops the unit to that tier instead, resets the count and journals tierHop")
fn ! fail! ctx: Ctx c: CUnit stage: String model: String sig: String ms: Int64 -> CUnit
  (let [(climb (listContains? (list "write" "gates" "review") stage))
        (fails (if (or (= (sigKey sig) (sigKey c.sig)) (and climb (or (= c.lane "paid") (= c.lane "strong")))) (+ c.fails 1) 1))
        (_ (if (= stage "write") (wipSave! ctx c.id (str "writeFailed " (verdictSig sig))) ()))
        (_ (dropLease! ctx c))
        (c1 (with c :fails fails :sig sig :epoch 0))
        (limit (if climb (rungLimit ctx c.lane) ctx.maxSame))
        (hop (if (and climb (>= fails limit)) (nextRung! ctx.dir c.lane (/ (nowNs) 1000000)) (none)))]
    (if (>= fails limit)
      (match hop
        ((some next)
          (if (= next "lead")
            (let [(_ (priorWrite! ctx.dir c.id c.lane sig))
                  (_ (leadRow! ctx.dir c (str stage " failed " (n fails) "x on " c.lane) sig))
                  (c2 (escalateTiered! ctx c1 sig (str stage " failed " (n fails) "x on " c.lane) "lead"))]
              (move! ctx (with c2 :lane "lead" :await "lead") "blocked" stage model 0 0 (str "tierHop " c.lane "->lead: " (verdictSig sig)) ms))
            (let [(_ (priorWrite! ctx.dir c.id c.lane sig))]
              (move! ctx (with c1 :lane next :fails 0 :sig "" :waited 0) "ready" stage model 0 0 (str "tierHop " c.lane "->" next ": " (verdictSig sig)) ms))))
        ((none)
          (let [(c2 (escalate! ctx c1 sig (str stage " failed " (n fails) "x with the same signature")))]
            (move! ctx c2 "blocked" stage model 0 0 (str "escalated: " (verdictSig sig)) ms))))
      (move! ctx c1 "ready" stage model 0 0 (str "fail: " (verdictSig sig)) ms)))

; (:m :ref DEPWAIT :do "a dependency wait counts toward maxWait only when a dependency is missing, blocked or failed; one still queued, ready or in a stage is progress, not a stall; step! stores a waiting unit as queued so its own dependents never see it missing (DEPCHAIN)")
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
        (move! ctx (with c2 :sig (str "waitedOut: " why)) "blocked" "wait" "" 0 0 "escalated" 0))
      (let [(_ (writeCUnit! ctx.dir c1))] c1)))

fn ! beat? ctx: Ctx c: CUnit -> Bool
  (match (st/heartbeat! ctx.dir c.id c.epoch) ((ok _) true) ((err _) false))

fn runsDir dir: String -> String
  (str dir "/runs")

fn runPath dir: String id: String stage: String ext: String -> String
  (str (runsDir dir) "/" id "-" stage "." ext)

fn renderRes r: Res -> String
  (str "(:res :ok " (n r.ok) " :wt " (st/q r.wt) " :branch " (st/q r.branch) " :model " (st/q r.model) " :tokens " (n r.tokens) " :costMicro " (n r.costMicro)
       " :claimedGreen " (n r.claimedGreen) " :sig " (st/q r.sig) " :ms " (n r.ms) " :exit " (n r.exit) " :asserts " (n r.asserts) " :verdict " (st/q r.verdict) " :tiers " (st/q r.tiers) " :alias " (st/q r.alias) ")")

fn parseRes raw: String -> (Result Res String)
  (match (st/rowFields raw "res")
    ((err e) (err e))
    ((ok fs)
      (ok (Res :ok (st/intField fs "ok") :wt (st/textField fs "wt") :branch (st/textField fs "branch") :model (st/textField fs "model")
               :tokens (st/intField fs "tokens") :costMicro (st/intField fs "costMicro") :claimedGreen (st/intField fs "claimedGreen")
               :sig (st/textField fs "sig") :ms (st/intField fs "ms") :exit (st/intField fs "exit") :asserts (st/intField fs "asserts")
               :verdict (st/textField fs "verdict") :tiers (st/textField fs "tiers") :alias (st/textField fs "alias")))))

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
; (:m :ref COND-MERGE-STAGE-RED :do "merge stages run one at a time: every train shares the dev repo and its one scratch worktree, and on 2026-10-30 TIMEOUT-WRAPPER-ORPHAN's train reset the scratch under LL-SVD-PARSE's running train; a unit reaching merging while another unit's merge child is live stays merging with launched 0 and step! launches it on a later tick")
fn ! mergeBusy? dir: String id: String -> Bool
  (listAny? (fn [(x CUnit)] -> Bool (and (!= x.id id) (and (= x.st "merging") (!= x.launched 0)))) (readCUnits! dir))

fn ! launch! ctx: Ctx u: st/Task c: CUnit -> CUnit
  (if (or (draining? ctx.dir) (and (= c.st "merging") (mergeBusy? ctx.dir c.id))) (let [(c0 (with c :launched 0)) (_ (writeCUnit! ctx.dir c0))] c0)
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
          c1)))))

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

; (:m :ref LANDED-AUDIT :do "GRADE-COMMIT-AUTH: the conductor records every grade commit it makes as (:gradeCommit :unit :sha :row) in <store>/gradeCommits.asn, outside any worktree; a unit branch is forged when a commit past the base touching .asl/mem/grades.asn has a sha that is not in that store file (an author or subject a writer can write proves nothing), or the log is unreadable")
fn gradeCommitsPath dir: String -> String
  (str dir "/gradeCommits.asn")

fn ! gradeCommitRecorded? dir: String sha: String -> Bool
  (listAny? (fn [(l String)] -> Bool (and (stringStartsWith? l "(:gradeCommit ") (= (al/rowText l "sha") sha))) (stringLines (readOr (gradeCommitsPath dir))))

; (:m :ref GRADE-COMMIT-AUTH :do "one-time migration at conductor start: when <store>/gradeCommits.asn does not exist yet (grade commits of the W1b conductor were never recorded), it is created from the grade commits already on the unit branches sh/* of the repo: committer conductor@localhost, subject starting (:c :a grade :do, touching the ledger, at most 5000 commits; each becomes a (:gradeCommit :unit \"\" :sha S :row \"seed\") row and one (:gradeSeed :n N) row heads the file so it never runs twice; an unreadable log creates nothing and the next start retries. Never run lazily: only the operator's start trusts what is on the branches then; returns the commits seeded, -1 when the file exists or the repo is unknown")
fn ! seedGradeCommits! dir: String -> Int64
  (let [(repo (stringTrim (readOr (repoPath dir))))]
    (if (or (stringEmpty? repo) (fileExists? (gradeCommitsPath dir))) -1
      (let [(r (gitOut repo (list "log" "--branches=sh/*" "-n" "5000" "--committer=conductor@localhost" "--format=%H %s" "--" (al/ledgerPath))))
            (shas (map (fn [(l String)] -> String (optionOr (listHead (stringSplit l " ")) ""))
                       (filter (fn [(l String)] -> Bool (stringContains? l " (:c :a grade :do ")) (stringLines r.out))))
            (rows (map (fn [(sha String)] -> String (str "(:gradeCommit :unit \"\" :sha " (st/q sha) " :row \"seed\")")) (filter (fn [(x String)] -> Bool (not (stringEmpty? x))) shas)))]
        (if (!= r.exit 0) -1
          (match (fileWrite (gradeCommitsPath dir) (str "(:gradeSeed :n " (n (listLength rows)) ")\n" (stringJoin rows "\n") (if (listEmpty? rows) "" "\n")))
            ((ok _) (listLength rows))
            ((err _) -1))))))

; (:m :ref CONDUCTOR-REPO-HEALTH :do "the ledger verdict of a unit branch: empty when clean, forged when a commit touching the ledger is not in the store's record, ERR_REPO_GIT: TEXT when git could not read the log at all (the repo, not the writer, is broken: a vanished common dir made 45 units LEDGER_FORGED on node2)")
fn ! ledgerState! dir: String path: String base: String -> String
  (if (stringEmpty? path) ""
    (let [(r (gitOut path (list "log" "--format=%H" (str base "..HEAD") "--" (al/ledgerPath))))]
      (cond
        ((!= r.exit 0) (str "ERR_REPO_GIT: git log in " path " exit " (n r.exit) ": " (repoClip r.out)))
        ((listAny? (fn [(l String)] -> Bool (and (not (stringEmpty? (stringTrim l))) (not (gradeCommitRecorded? dir (stringTrim l))))) (stringLines r.out)) "forged")
        (else ""))))

fn repoClip text: String -> String
  (let [(t (stringTrim text))] (if (> (stringLength t) 160) (optionOr (stringSlice t 0 160) t) t))

fn ! ledgerForged! dir: String path: String base: String -> Bool
  (= (ledgerState! dir path base) "forged")

; (:m :ref CONDUCTOR-REPO-HEALTH :do "the signature a ledger state gives a result: LEDGER_FORGED for a forged branch, the ERR_REPO_GIT text for an unreadable repo, empty when clean")
fn ! ledgerSig! dir: String path: String base: String -> String
  (let [(st (ledgerState! dir path base))]
    (cond
      ((= st "forged") "LEDGER_FORGED: a writer commit touches .asl/mem/grades.asn")
      (else st)))

; (:m :ref LANDED-AUDIT :do "the ledger guard of finish!: a write result that landed commits touching the ledger, or a review pass over such a branch, becomes a failure (LEDGER_FORGED) so it is neither gated, reviewed nor merged")
fn ! ledgerGuard dir: String u: st/Task c: CUnit res0: Res -> Res
  (cond
    ((and (= c.st "writing") (= res0.ok 1))
      (let [(sig (ledgerSig! dir res0.wt (baseRef u)))] (if (stringEmpty? sig) res0 (with res0 :ok 0 :sig sig))))
    ((and (= c.st "reviewing") (= res0.verdict "pass"))
      (let [(sig (ledgerSig! dir c.wt (baseRef u)))] (if (stringEmpty? sig) res0 (with res0 :verdict "fail" :sig sig))))
    (else res0))

; (:m :do "applies one finished stage result to its unit; the writer's claimedGreen is only journalled")
fn ! finish! ctx: Ctx u: st/Task c: CUnit res0: Res -> Unit
  (let [(res (ledgerGuard ctx.dir u c res0))
        (stage (stageName c.st))
        (_ (dropRun! ctx.dir c.id stage))]
    (cond
      ((= c.st "writing")
        (if (providerHit? ctx u c res) (providerRequeue! ctx c res) (let [(_ (pwReset! ctx.dir c.id))] (if (= res.ok 1)
          (let [(c1 (moveA! ctx (written c res.wt res.branch) "gating" "write" res.model res.alias res.tokens res.costMicro (if (= res.claimedGreen 1) "claimedGreen" "written") res.ms))
                (_ (launch! ctx u c1))]
            ())
          (if (staleSig? res.sig)
            (let [(headBefore (unitHead! ctx.dir c.id))
                  (_ (wipSave! ctx c.id "staleNeedsRebase"))
                  (_ (dropLease! ctx c))
                  (leon (staleField res.sig "leon"))
                  (woken (stringStartsWith? c.sig "STALE_WOKEN"))
                  (main (if (and woken (not (stringEmpty? (staleField c.sig "main")))) (staleField c.sig "main") (staleField res.sig "main")))
                  (_ (fileAppend (journalPath ctx.dir) (str "(:stale :unit " (st/q c.id) " :leon " (st/q leon) " :main " (st/q main) " :result blocked :needs rebase)\n")))
                  ; (:m :ref STALE-WAKE :do "still stale after a wake: the lead class gets one (:lead ...) row per unit")
                  (leadRow (staleLeadRow c.id))
                  (wokenN (listLength (filter (fn [(l String)] -> Bool (stringStartsWith? l (str "(:stale :unit " (st/q c.id) " :result woken"))) (stringLines (readOr (journalPath ctx.dir))))))
                  (_ (if (and woken (and (>= wokenN (staleWakeMax ctx.dir)) (not (stringContains? (readOr (escalationsPath ctx.dir)) leadRow))))
                       (ok? (fileAppend (escalationsPath ctx.dir) (str leadRow " :leon " (st/q leon) " :main " (st/q main) ")\n")))
                       false))
                  (_ (move! ctx (with c :await "rebase" :sig (str "STALE_NEEDS_REBASE leon " leon " main " main " head " headBefore)) "blocked" "write" res.model 0 0 "needs rebase" res.ms))]
              ())
          (if (vacuousSig? res.sig)
            (let [(_ (wipSave! ctx c.id "vacuousGate"))
                  (_ (dropLease! ctx c))
                  (c1 (escalate! ctx (with c :sig res.sig :epoch 0) res.sig "write: the unit gate passes on the base before any edit, so no write can prove it; make the gate fail on the base or mark the task a regression guard"))
                  (_ (move! ctx c1 "blocked" "write" res.model 0 0 (str "escalated: " (verdictSig res.sig)) res.ms))]
              ())
            (let [(_ (fail! ctx c "write" res.model res.sig res.ms))] ())))))))
      ((= c.st "gating")
        (if (and (= res.exit 0) (> res.asserts 0))
          (let [(_ (move! ctx c "awaitReview" "gates" "" 0 0 (str "green " (n res.asserts)) res.ms))] ())
          (if (gateTimeoutSig? res.sig)
            (gateTimeoutRequeue! ctx u c res)
            (let [(_ (fail! ctx c "gates" "" (if (stringEmpty? res.sig) (str "exit " (n res.exit) " asserts " (n res.asserts)) res.sig) res.ms))] ()))))
      ((= c.st "reviewing")
        (cond
          ((= res.verdict "pass")
            (let [(_ (gradeLand! ctx c c.id res.model))
                  (c1 (move! ctx c "merging" "review" res.model res.tokens res.costMicro "pass" res.ms))
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
          (cond
            ((depStalled? u cus) (let [(_ (waitMore! ctx c "deps not merged"))] cap))
            ((none? (cuOf cus u.id)) (let [(_ (writeCUnit! ctx.dir c))] cap))
            (else cap))))
      ((= c.st "ready")
        (let [(pace ctx.pace)
              (allowOf pace.allowance)
              (allow (allowOf c.lane))]
          (if (or (or (or (or (<= cap 0) (>= (laneActive cus c.lane) allow)) (draining? ctx.dir)) (providerWaiting? ctx.dir c.id (/ (nowNs) 1000000))) (writerHeld? ctx cus c.id))
            cap
            (match (st/claim! ctx.dir c.id ctx.holder ctx.ttlMs)
              ((err e) (let [(_ (waitMore! ctx c e))] cap))
              ((ok text)
                (let [(epoch (match (st/parseLease text) ((ok l) l.epoch) ((err _) 0)))
                      (c1 (move! ctx (admitted c epoch) "writing" "claim" "" 0 0 "admitted" 0))
                      (_ (launch! ctx u c1))]
                  (- cap 1)))))))
      ((= c.st "awaitReview")
        (if (or (= c.parked 1) (draining? ctx.dir)) cap
          (let [(c1 (move! ctx c "reviewing" "review" "" 0 0 "start" 0))
                (_ (launch! ctx u c1))]
            cap)))
      ((and (= c.st "blocked") (= c.await "rebase")) (let [(_ (staleWake! ctx c))] cap))
      ((= (stageName c.st) "") cap)
      ((not (beat? ctx c))
        (let [(_ (killRun! ctx.dir c.id (stageName c.st)))
              (_ (dropRun! ctx.dir c.id (stageName c.st)))
              (_ (if (= c.st "writing") (wipSave! ctx c.id "leaseLost") ()))
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

; (:m :ref COND-STALL-AUTO :do "the stall sweep of stall.asl over the writing units: the probe carries the run record's pid liveness and start time, a unit whose Res row is already written is left to poll!, the hooks kill through the run record and requeue the unit to ready with the stall note as the newest prior failure, so the next write brief carries it; the strong lane only while its daily cap has room")
fn ! stallProbes ctx: Ctx -> (List stl/Probe)
  (let [(repo (stringTrim (readOr (repoPath ctx.dir))))]
    (map (fn [(c CUnit)] -> stl/Probe
           (stl/Probe :id c.id :lane c.lane :wt (str (wtBase ctx.dir repo) "/asex-" c.id)
                      :alive (match (runRow ctx.dir c.id "write") ((some r) (alive? (pairFirst r))) ((none) false))
                      :sinceMs (stl/statMs (runPath ctx.dir c.id "write" "run"))))
         (filter (fn [(c CUnit)] -> Bool (and (= c.st "writing") (and (!= c.launched 0) (not (fileExists? (runPath ctx.dir c.id "write" "asn")))))) (readCUnits! ctx.dir))))

fn ! stallRequeue! ctx: Ctx c: CUnit lane: String note: String -> Unit
  (let [(profile (quotedAfter (optionOr (listLast (filter (fn [(l String)] -> Bool (stringStartsWith? l (str "(:profile :unit " (st/q c.id) " "))) (journalLinesOf ctx.dir))) "") ":profile \""))
        (_ (if (stringEmpty? profile) (ok ()) (fileAppend (stalledProfilePath ctx.dir) (str "(:stalledProfile :unit " (st/q c.id) " :profile " (st/q profile) " :alias " (st/q c.model) " :at " (n (/ (nowNs) 1000000)) ")\n"))))
        (to (if (and (= lane "strong") (not (rungOpen? ctx.dir "strong" (nowMs)))) c.lane lane))
        (_ (priorWrite! ctx.dir c.id c.lane note))
        (_ (dropLease! ctx c))
        (_ (move! ctx (with c :lane to :fails 0 :sig "" :epoch 0 :esc 0 :await "") "ready" "write" "" 0 0 "stalled" 0))]
    ())

fn ! stallHooks ctx: Ctx -> stl/Hooks
  (stl/Hooks
    :kill (fn [(id String)] -> Unit (let [(_ (killRun! ctx.dir id "write")) (_ (dropRun! ctx.dir id "write")) (_ (wipSave! ctx id "stalled"))] ()))
    :requeue (fn [(id String) (lane String) (note String)] -> Unit
               (match (cuOf (readCUnits! ctx.dir) id)
                 ((none) ())
                 ((some c) (stallRequeue! ctx c lane note)))))

; (:m :ref CONDUCTOR :do "one tick starts, polls and transitions only, never waits for a stage: every unit moves at most one transition in id order; capacity = pace tokens minus the units already in flight; the result is 1 when any unit row changed, 0 when the tick was idle")
; (:m :ref CONDUCTOR-REPO-HEALTH :do "<store>/repoBroken.asn marks a repo whose common dir git cannot read (git rev-parse --git-common-dir in --repo fails): on the transition one (:repoBroken :repo :err :at) row goes to the escalations and the journal, no tick admits or steps a unit while it stands, and the first healthy probe journals (:repoHealthy) and removes the mark; a repo path the store does not know is not probed")
fn repoBrokenPath dir: String -> String
  (str dir "/repoBroken.asn")

fn ! repoErr! repo: String -> String
  (let [(r (gitOut repo (list "rev-parse" "--git-common-dir")))]
    (cond
      ((!= r.exit 0) (str "git exit " (n r.exit) (if (stringEmpty? (stringTrim r.out)) "" (str ": " (repoClip r.out)))))
      ((not (worktreeValid? repo)) "the directory is not its own git top level (its .git is gone, an enclosing repo answers)")
      (else "")))

fn ! repoGate! ctx: Ctx -> Bool
  (let [(repo (stringTrim (readOr (repoPath ctx.dir))))]
    (if (stringEmpty? repo) true
      (let [(err (repoErr! repo))
            (marked (fileExists? (repoBrokenPath ctx.dir)))
            (now (/ (nowNs) 1000000))]
        (cond
          ((and (not (stringEmpty? err)) (not marked))
            (let [(row (str "(:repoBroken :repo " (st/q repo) " :err " (st/q err) " :at " (n now) ")"))
                  (_ (fileWrite (repoBrokenPath ctx.dir) (str row "\n")))
                  (_ (fileAppend (escalationsPath ctx.dir) (str row "\n")))
                  (_ (fileAppend (journalPath ctx.dir) (str row "\n")))]
              false))
          ((not (stringEmpty? err)) false)
          (marked
            (let [(_ (fileAppend (journalPath ctx.dir) (str "(:repoHealthy :repo " (st/q repo) " :at " (n now) ")\n")))
                  (_ (pathRemove (repoBrokenPath ctx.dir)))]
              true))
          (else true)))))

fn ! tick! ctx: Ctx -> (Result Int64 String)
  (if (repoGate! ctx) (tickRepo! ctx) (ok 0))

fn ! tickRepo! ctx: Ctx -> (Result Int64 String)
  (match (st/readUnits! ctx.dir)
    ((err e) (err e))
    ((ok units)
      (let [(_ (requeueDrain! ctx units))
            (_ (depWake! ctx units))
            (_ (freeWake! ctx))
            (_ (stl/sweep! ctx.dir (nowMs) (stallProbes ctx) (stallHooks ctx)))
            (before (snapshot ctx.dir))
            (pace ctx.pace)
            (tokensOf pace.tokens)
            (flying (listLength (filter inFlight? (readCUnits! ctx.dir))))
            (_ (offerBacklog! ctx.dir (/ (nowNs) 1000000)))
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

; (:m :ref ORG-GAP-20261102 :do "check prints one (:staleOwns :id :paths) warning line per queue row whose :owns names a path absent from the repo tree (ledger from --ledger, else the store's ledger.path); it never changes the exit code")
fn ! staleOwnsFor! dir: String args: (List String) rc: RealCfg -> (List String)
  (let [(given (st/opt args "ledger" ""))
        (ledger (if (stringEmpty? given) (stringTrim (optionOr (listHead (stringLines (readOr (ledgerPath dir)))) "")) given))]
    (if (stringEmpty? ledger) (list) (pi/staleOwns (readOr ledger) rc.repo)))

; (:m :ref CONDUCTOR :do "stopAll! kills the process tree of every in-flight stage and drops its run row; the unit goes back to ready through the lease on the next start")
fn ! stopAll! ctx: Ctx -> Int64
  (let [(flying (filter inFlight? (readCUnits! ctx.dir)))
        (_ (map (fn [(c CUnit)] -> Unit (let [(_ (killRun! ctx.dir c.id (stageName c.st))) (_ (dropRun! ctx.dir c.id (stageName c.st)))] (if (= c.st "writing") (wipSave! ctx c.id "stopped") ()))) flying))]
    (listLength flying))

; (:m :ref CONDUCTOR :do "wake LANE: units parked in awaitReview for that lane (quota window reset or refreshed allowance) become ready for review; one journal row per unit")
fn ! wake! ctx: Ctx lane: String -> Int64
  (let [(cus (filter (fn [(c CUnit)] -> Bool (and (= c.st "awaitReview") (and (= c.parked 1) (or (= c.lane lane) (= c.await lane))))) (readCUnits! ctx.dir)))
        (_ (map (fn [(c CUnit)] -> CUnit (move! ctx (parkedOf c 0) "awaitReview" "wake" "" 0 0 lane 0)) cus))]
    (listLength cus))

; (:m :ref INTAKE-PARKED-WAKE :do "(:wake :await NAME :readyBelow N) rows in the store's ladder.asn: units parked in awaitReview on NAME (a lane or intake class no allowance refresh ever names) wake while a writer slot is free and fewer than N units are ready; one per free slot, oldest first by file order; no row means nothing wakes this way")
fn wakeRowsOf dir: String -> (List String)
  (filter (fn [(l String)] -> Bool (stringStartsWith? l "(:wake ")) (map stringTrim (stringLines (readOr (ladderPath dir)))))

fn wakeErrors row: String -> (List String)
  (let [(keys (filter (fn [(t String)] -> Bool (stringStartsWith? t ":")) (stringSplit row " ")))
        (bad (filter (fn [(k String)] -> Bool (not (listContains? (list ":await" ":readyBelow") k))) keys))
        (below (optionOr (stringToInt64 (sp/tokAfter row ":readyBelow")) 0))
        (name (stringTrim (stringReplace (stringReplace (sp/tokAfter row ":await") "\"" "") ")" "")))]
    (listAppend (listAppend (map (fn [(k String)] -> String (str "unknown key " k)) bad)
                            (if (stringEmpty? name) (list ":await missing") (list)))
                (if (or (< below 1) (> below 1000)) (list (str ":readyBelow " (n below) " outside 1..1000")) (list))))

fn ! freeWake! ctx: Ctx -> Int64
  (let [(cus (readCUnits! ctx.dir))
        (pace ctx.pace)
        (tokensOf pace.tokens)
        (slots (- (tokensOf) (listLength (filter inFlight? cus))))
        (ready (listLength (filter (fn [(c CUnit)] -> Bool (= c.st "ready")) cus)))
        (rows (filter (fn [(r String)] -> Bool (listEmpty? (wakeErrors r))) (wakeRowsOf ctx.dir)))]
    (fold (fn [(done Int64) (r String)] -> Int64
            (let [(name (stringTrim (stringReplace (stringReplace (sp/tokAfter r ":await") "\"" "") ")" "")))
                  (below (optionOr (stringToInt64 (sp/tokAfter r ":readyBelow")) 0))
                  (room (- slots done))
                  (parked (filter (fn [(c CUnit)] -> Bool (and (= c.st "awaitReview") (and (= c.parked 1) (= c.await name)))) (readCUnits! ctx.dir)))
                  (take (if (or (<= room 0) (>= (+ ready done) below)) (list) (listTake parked (min room (- below (+ ready done))))))
                  (_ (map (fn [(c CUnit)] -> CUnit (move! ctx (parkedOf c 0) "awaitReview" "wake" "" 0 0 (str "free:" name) 0)) take))]
              (+ done (listLength take))))
          0 rows))

; (:m :ref COND-REQUEUE :do "requeue: `conductor requeue --ids A,B | --all-blocked --store DIR` appends (:requeue :unit ID) rows to <store>/requeue.asn; the running tick claims the file by rename, and each named unit that is blocked or failed goes back to queued with a clean count, lane, wait and escalation flag (one journal row, stage requeue); other states and unknown ids are ignored, so the verb never races a stage")
fn requeuePath dir: String -> String
  (str dir "/requeue.asn")

fn ! requestRequeue! dir: String ids: (List String) -> Bool
  (if (listEmpty? ids) true
    (ok? (fileAppend (requeuePath dir) (str (stringJoin (map (fn [(id String)] -> String (str "(:requeue :unit " (st/q id) ")")) ids) "\n") "\n"))))

fn cleaned c: CUnit lane: String -> CUnit
  (with c :lane lane :fails 0 :sig "" :waited 0 :parked 0 :epoch 0 :esc 0 :await "")

fn ! requeueOne! ctx: Ctx units: (List st/Task) id: String -> Bool
  (match (cuOf (readCUnits! ctx.dir) id)
    ((none) false)
    ((some c)
      (if (not (listContains? (list "blocked" "failed") c.st)) false
        (let [(lane (match (listFind (fn [(u st/Task)] -> Bool (= u.id id)) units) ((some u) u.channel) ((none) c.lane)))
              (_ (dropLease! ctx c))
              (_ (pwReset! ctx.dir c.id))
              (_ (move! ctx (cleaned c lane) "queued" "requeue" "" 0 0 "requeued" 0))]
          true))))

fn ! requeueDrain! ctx: Ctx units: (List st/Task) -> Int64
  (let [(p (requeuePath ctx.dir))
        (taken (str p ".taken"))
        (_ (if (and (fileExists? p) (not (fileExists? taken))) (pathRename p taken) (ok ())))]
    (if (not (fileExists? taken)) 0
      (let [(ids (filter (fn [(s String)] -> Bool (not (stringEmpty? s))) (map (fn [(l String)] -> String (quotedAfter l ":unit \"")) (stringLines (readOr taken)))))
            (done (filter (fn [(id String)] -> Bool (requeueOne! ctx units id)) ids))
            (_ (pathRemove taken))]
        (listLength done))))

; (:m :ref COND-DEP-WAKE :do "a unit blocked only by 'deps not merged' (no failure signature, wait past maxWait) goes back to queued on the tick after none of its :after units is blocked, failed or missing, so a requeued or merged root releases its dependents")
fn ! depWake! ctx: Ctx units: (List st/Task) -> Int64
  (let [(cus (readCUnits! ctx.dir))
        (wake (filter (fn [(u st/Task)] -> Bool
                        (and (not (listEmpty? u.after))
                             (and (not (depStalled? u cus))
                                  (match (cuOf cus u.id)
                                    ((none) false)
                                    ((some c) (and (= c.st "blocked") (and (or (stringEmpty? c.sig) (stringStartsWith? c.sig "waitedOut: ")) (and (stringEmpty? c.await) (> c.waited ctx.maxWait)))))))))
                      units))
        (done (filter (fn [(u st/Task)] -> Bool (requeueOne! ctx units u.id)) wake))]
    (listLength done))

; (:m :ref COND-ADMIT-TOKENS :do "writer admission: with a (:writers :minFreeMb N :warmFirst true|false :jobserver DIR :meminfo PATH) row in the store's ladder.asn, a ready unit starts its writer only while the node has a free jobserver token (tokenCount - heldCount > 0) and MemAvailable >= :minFreeMb (default 2000, adopted), and, after each conductor start, one writer starts alone: the rest wait until that writer's session journal shows its first served model turn, its unit left writing, or warmMaxMs passed. No row, or a row wrOpts rejects: no gate. :jobserver and :meminfo default to the node's own and exist so tests can fake them")
fn wrRowOf dir: String -> String
  (optionOr (listFind (fn [(l String)] -> Bool (stringStartsWith? (stringTrim l) "(:writers ")) (stringLines (readOr (ladderPath dir)))) "")

fn wrInt row: String key: String dflt: Int64 -> Int64
  (optionOr (stringToInt64 (sp/tokAfter row key)) dflt)

fn wrMinFreeMb row: String -> Int64
  (wrInt row ":minFreeMb" 2000)

fn wrWarmFirst? row: String -> Bool
  (not (stringContains? row ":warmFirst false"))

fn wrErrors row: String -> (List String)
  (let [(keys (filter (fn [(t String)] -> Bool (stringStartsWith? t ":")) (stringSplit row " ")))
        (bad (filter (fn [(k String)] -> Bool (not (listContains? (list ":minFreeMb" ":warmFirst" ":jobserver" ":meminfo") k))) keys))
        (m (wrMinFreeMb row))]
    (listAppend (map (fn [(k String)] -> String (str "unknown key " k)) bad)
                (if (or (< m 0) (> m 1000000)) (list (str ":minFreeMb " (n m) " outside 0..1000000")) (list))))

fn wrCfg dir: String -> String
  (let [(row (wrRowOf dir))]
    (if (listEmpty? (wrErrors row)) row ""))

; (:m :ref COND-ADMIT-TOKENS :do "the pure decision: a free token and enough memory; an unreadable meminfo (-1) does not block")
fn admitWriter? free: Int64 freeMb: Int64 minMb: Int64 -> Bool
  (and (> free 0) (or (< freeMb 0) (>= freeMb minMb)))

fn warmPath dir: String -> String
  (str dir "/warm.asn")

fn warmMaxMs -> Int64
  900000

fn ! firstCallSeen? dir: String id: String -> Bool
  (let [(jd (str (wtBase dir (stringTrim (readOr (repoPath dir)))) "/asex-" id "/.asl/run/agentLoop"))
        (names (filter (fn [(f String)] -> Bool (stringEndsWith? f ".journal")) (resultOr (dirList jd) (list))))]
    (listAny? (fn [(f String)] -> Bool (stringContains? (readOr (str jd "/" f)) "(:served :turn ")) names))

; (:m :ref COND-ADMIT-TOKENS :do "warm gate: true while this conductor's warm writer is still before its first model turn; the first unit asked after a start becomes the warm writer (row (:warm :holder :unit :at) in <store>/warm.asn, rewritten with :done when it is over)")
fn ! warmWait! ctx: Ctx cus: (List CUnit) id: String -> Bool
  (let [(row (readOr (warmPath ctx.dir)))
        (now (/ (nowNs) 1000000))
        (mine (stringContains? row (str ":holder " (st/q ctx.holder) " ")))]
    (cond
      ((not mine)
        (let [(_ (fileWrite (warmPath ctx.dir) (str "(:warm :holder " (st/q ctx.holder) " :unit " (st/q id) " :at " (n now) ")\n")))] false))
      ((stringContains? row " :done") false)
      (else
        (let [(w (quotedAfter row ":unit \""))
              (at (wrInt row ":at" now))
              (stillWarming (and (< (- now at) (warmMaxMs))
                                 (match (cuOf cus w) ((some wc) (and (= wc.st "writing") (not (firstCallSeen? ctx.dir w)))) ((none) false))))
              (_ (if stillWarming true (ok? (fileWrite (warmPath ctx.dir) (str "(:warm :holder " (st/q ctx.holder) " :unit " (st/q w) " :at " (n at) " :done " (n now) ")\n")))))]
          stillWarming))))

fn ! writerHeld? ctx: Ctx cus: (List CUnit) id: String -> Bool
  (let [(row (wrCfg ctx.dir))]
    (if (stringEmpty? row) false
      (let [(jdir (quotedAfter row ":jobserver \""))
            (minfo (let [(m (quotedAfter row ":meminfo \""))] (if (stringEmpty? m) "/proc/meminfo" m)))
            (free (- (js/tokenCount jdir) (js/heldCount jdir)))]
        (if (not (admitWriter? free (sc/memFreeMB (readOr minfo)) (wrMinFreeMb row))) true
          (if (wrWarmFirst? row) (warmWait! ctx cus id) false)))))

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
; (:m :ref CONDTEST-SCHED-RED :do "the sample with the machine readings passed in: conductorTest read node2's real load (37 on 8 cores), which stepped a fresh :start 7 down to 6; tests pass fixed readings, lightSlots! the real ones")
fn ! lightSlotsAt! dir: String home: String freeMB: Int64 load: Float64 cores: Int64 -> Int64
  (let [(txt (readOr (str home "/.asl/conductor/sched.asn")))]
    (if (stringEmpty? txt)
      (poolSize "")
      (let [(cfg (sc/parseCfg txt))
            (now (/ (nowNs) 1000000))]
        (if (sc/slotsDue? dir now 60000)
          (sc/schedTick! dir cfg now (stringLines (readOr (str home "/.asl/run/usage/gatewayCalls.asn"))) freeMB load cores)
          (pairFirst (sc/slotsRead! dir))))))

fn ! lightSlots! dir: String home: String -> Int64
  (lightSlotsAt! dir home (sc/memFreeMB (readOr "/proc/meminfo")) (sc/loadOne (readOr "/proc/loadavg")) (resultOr (cpuCount) 1))

fn schedPace dir: String home: String -> Pace
  (Pace :tokens (fn [] -> Int64 (lightSlots! dir home)) :allowance allowanceUnlimited)

fn realPace -> Pace
  (jobserverPace "" allowanceUnlimited)

fn quotedAfter line: String marker: String -> String
  (match (listGet (stringSplit line marker) 1)
    ((some rest) (optionOr (listHead (stringSplit rest "\"")) ""))
    ((none) ""))

fn segment text: String from: String to: String -> String
  (match (listGet (stringSplit text from) 1)
    ((some rest) (optionOr (listHead (stringSplit rest to)) ""))
    ((none) ""))

; (:m :ref COND-MERGE-STAGE-RED :do "the cause a killed or red train names itself, before any ERR line: a run.asl kill row, a train failure row, the receipt's commit error, else the streamed red suites the receipt still counts as fresh (preexisting ones dropped), by path only; the ERR lines inside those rows are suite output quoted once per nesting level, and LL-SVD-PARSE's merge took one such fragment (HOSTFAIL followed by 15 backslashes) as its signature; empty when the output has none of these rows")
fn wordAfter line: String marker: String -> String
  (optionOr (listHead (stringSplit (stringReplace (segment line marker "\n") ")" " ") " ")) "")

fn killSig line: String -> String
  (str "killed: " (wordAfter line "(:fleetRun :verdict :") " after " (n (/ (optionOr (stringToInt64 (wordAfter line " :timeoutMs ")) 0) 1000)) " s")

fn trainSig lines: (List String) -> String
  (let [(kill (listFind (fn [(l String)] -> Bool (stringStartsWith? l "(:fleetRun :verdict :")) lines))
        (failed (listFind (fn [(l String)] -> Bool (stringStartsWith? l "(:train :status :failed")) lines))
        (receipt (optionOr (listLast (filter (fn [(l String)] -> Bool (stringStartsWith? l "(:train :head ")) lines)) ""))
        (fresh (segment receipt " :red (" " :preexisting ("))
        (lost (segment receipt " :assertLoss (" ")"))
        (reds (filter (fn [(p String)] -> Bool (and (not (stringEmpty? p)) (or (stringEmpty? receipt) (stringContains? fresh (str "(\"" p "\" ")))))
                      (map (fn [(l String)] -> String (quotedAfter l "(:redLive \"")) (filter (fn [(l String)] -> Bool (stringStartsWith? l "(:redLive ")) lines))))]
    (cond
      ((some? kill) (killSig (optionOr kill "")))
      ((some? failed) (optionOr failed ""))
      ((stringContains? receipt " :commitError ") (str "commitError " (quotedAfter receipt " :commitError \"")))
      ((not (listEmpty? reds)) (str "train red: " (stringJoin (listTake reds 3) " ")))
      ((not (stringEmpty? lost)) (str "train assertLoss: " (stringReplace lost "\"" "")))
      (else "")))

; (:m :do "a train's own cause first (trainSig), else the first ERR line, else the last non-empty line, cut to 160 chars: the same failure gives the same signature")
fn gateSig out: String -> String
  (let [(own (trainSig (map stringTrim (stringLines out))))
        (errs (if (stringEmpty? own) (fr/errorLinesOf out) (list own)))
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

; (:m :ref GATE-CHECK-TIMEOUT :do "the asl check run before a gate is bounded by (:gate :checkTimeoutS N) in the store's ladder.asn, default 900 s (adopted; the old hard limit of 300 s killed leonServe.asl checks 7 times on a loaded node); a check that hits the limit is the signature gateTimeout, its own failure kind")
fn gateRowOf dir: String -> String
  (optionOr (listFind (fn [(l String)] -> Bool (stringStartsWith? (stringTrim l) "(:gate ")) (stringLines (readOr (ladderPath dir)))) "")

fn gateErrors row: String -> (List String)
  (let [(keys (filter (fn [(t String)] -> Bool (stringStartsWith? t ":")) (stringSplit row " ")))
        (bad (filter (fn [(k String)] -> Bool (not (= k ":checkTimeoutS"))) keys))
        (m (optionOr (stringToInt64 (sp/tokAfter row ":checkTimeoutS")) 900))]
    (listAppend
      (map (fn [(k String)] -> String (str "unknown key " k)) bad)
      (if (or (< m 30) (> m 7200)) (list (str ":checkTimeoutS " (n m) " outside 30..7200")) (list))))

fn ! gateCheckS dir: String -> Int64
  (let [(row (gateRowOf dir))]
    (if (or (stringEmpty? row) (not (listEmpty? (gateErrors row)))) 900 (optionOr (stringToInt64 (sp/tokAfter row ":checkTimeoutS")) 900)))

fn gateTimeoutSig p: String sec: Int64 -> String
  (str "gateTimeout: asl check on " p " passed " (n sec) " s")

fn gateTimeoutSig? sig: String -> Bool
  (stringStartsWith? sig "gateTimeout: ")

; (:m :ref GATE-CHECK-TIMEOUT :do "a gate that timed out is the node's load, not the writer's work: the unit stays in gating and its gate stage runs again, journaled as (:stop :unit :kind gateTimeout :n N), without a fail count; the :maxInRow+1th consecutive timeout (3, adopted) is an ordinary gate failure")
fn ! gateTimeoutRequeue! ctx: Ctx u: st/Task c: CUnit res: Res -> Unit
  (let [(prior (listLength (filter (fn [(l String)] -> Bool (stringStartsWith? l (str "(:stop :unit " (st/q c.id) " :kind gateTimeout"))) (stringLines (readOr (journalPath ctx.dir))))))]
    (if (>= prior 3)
      (let [(_ (fail! ctx c "gates" "" res.sig res.ms))] ())
      (let [(_ (fileAppend (journalPath ctx.dir) (str "(:stop :unit " (st/q c.id) " :kind gateTimeout :n " (n (+ prior 1)) " :why " (st/q res.sig) ")\n")))
            (c1 (move! ctx c "gating" "gates" "" 0 0 "gateTimeout" res.ms))
            (_ (launch! ctx u c1))]
        ())))

; (:m :ref CONDHARDEN :do "asl check on every owned .asl file and on every importer of an owned module; the first failure is the signature, empty when all check")
fn ! checkOne! wt: String p: String sec: Int64 -> String
  (let [(d (fr/runOneLimited (fr/job (list (str wt "/bin/asl") "check" p) wt (fr/childEnv (list (str "ASL_ROOT=" wt)))) (fr/limits sec 200)))]
    (cond
      ((= d.exit 0) "")
      ((= d.verdict "timeout") (gateTimeoutSig p sec))
      (else (str "asl check failed on " p ": " (gateSig d.out)))))

fn ! firstCheckSig! wt: String targets: (List String) sec: Int64 -> String
  (match (listHead targets)
    ((none) "")
    ((some p) (let [(sig (checkOne! wt p sec))] (if (stringEmpty? sig) (firstCheckSig! wt (optionOr (listTail targets) (list)) sec) sig))))

fn ! checkSig! wt: String owned: (List String) sec: Int64 -> String
  (firstCheckSig! wt (filter (fn [(p String)] -> Bool (and (stringEndsWith? p ".asl") (fileExists? (str wt "/" p)))) (listAppend owned (importerFiles! wt owned))) sec)

; (:m :ref CONDUCTOR :do "the conductor's own gate stage reruns the declared gate in the unit's worktree and never reads the writer's report")
; (:m :ref CONDHARDEN :do "before the declared gate: owned files may not lose more than half their base lines without the word rewrite in the task text, and every owned .asl file and each importer of an owned module must pass asl check; either failure is exit 3 with a :sig naming the file")
fn ! gatesRes gateSec: Int64 checkSec: Int64 task: String u: st/Task c: CUnit -> Res
  (let [(refused (if (stringEmpty? u.gate) "" (shrinkRefusal! c.wt u task)))
        (broken (if (or (stringEmpty? u.gate) (not (stringEmpty? refused))) "" (checkSig! c.wt u.owns checkSec)))]
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
  (pickWriteProfileX lanes id lane base health (list))

; (:m :ref STALL-MODEL-DEDUPE :do "profiles a unit stalled on are left out of its pick while another one is configured: the weights and profiles of the :writeProfiles row are filtered by the excluded list before the stable hash picks, so the retry after a stall runs another profile; an exclusion that would empty the row is ignored")
fn pickWriteProfileX lanes: String id: String lane: String base: String health: String excluded: (List String) -> String
  (let [(rows (filter (fn [(l String)] -> Bool (and (stringContains? l "(:writeProfiles ") (= (sp/tokAfter l ":tier") lane))) (stringLines lanes)))]
    (match (listHead rows)
      ((none) base)
      ((some l)
        (let [(ps0 (listAfter l ":profiles"))
              (ws00 (map (fn [(x String)] -> Int64 (max 0 (optionOr (stringToInt64 x) 0))) (listAfter l ":weights")))
              (leads (listAfter l ":leads"))
              (ws0 (if (and (not (stringEmpty? health)) (= (listLength leads) (listLength ws00)))
                     (map (fn [(i Int64)] -> Int64 (optionOr (float64ToInt64 (* (int64ToFloat64 (* 100 (optionOr (listGet ws00 i) 0))) (sc/okShareOf health (optionOr (listGet leads i) "")))) 0)) (range 0 (listLength ws00)))
                     ws00))
              (keep (filter (fn [(i Int64)] -> Bool (not (listContains? excluded (optionOr (listGet ps0 i) "")))) (range 0 (min (listLength ps0) (listLength ws0)))))
              (useKeep (and (not (listEmpty? excluded)) (and (not (listEmpty? keep)) (= (listLength ps0) (listLength ws0)))))
              (ps (if useKeep (map (fn [(i Int64)] -> String (optionOr (listGet ps0 i) "")) keep) ps0))
              (ws (if useKeep (map (fn [(i Int64)] -> Int64 (optionOr (listGet ws0 i) 0)) keep) ws0))
              (total (fold (fn [(a Int64) (w Int64)] -> Int64 (+ a w)) 0 ws))
              (pick (if (and (> total 0) (= (listLength ps) (listLength ws))) (slotProfile ps ws (mod (idHash id) total)) ""))]
          (if (stringEmpty? pick) base pick)))))

; (:m :ref STALL-MODEL-DEDUPE :do "<store>/stalledProfiles.asn holds (:stalledProfile :unit ID :profile P :alias A :at MS) rows, one per stall kill, written by stallRequeue! from the profile of the unit's newest (:profile ...) journal row and the alias of its newest write move")
fn stalledProfilePath dir: String -> String
  (str dir "/stalledProfiles.asn")

fn ! journalLinesOf dir: String -> (List String)
  (stringLines (readOr (journalPath dir)))

fn ! stalledProfilesOf dir: String id: String -> (List String)
  (filter (fn [(p String)] -> Bool (not (stringEmpty? p)))
          (map (fn [(l String)] -> String (quotedAfter l ":profile \""))
               (filter (fn [(l String)] -> Bool (stringStartsWith? l (str "(:stalledProfile :unit " (st/q id) " "))) (stringLines (readOr (stalledProfilePath dir))))))

fn writeProfile rc: RealCfg lane: String -> String
  (let [(rows (filter (fn [(l String)] -> Bool (and (stringContains? l "(:writeProfile ") (= (sp/tokAfter l ":tier") lane))) (stringLines (readOr rc.lanes))))
        (given (match (listHead rows) ((some l) (sp/tokAfter l ":profile")) ((none) "")))]
    (cond ((not (stringEmpty? given)) given) ((= lane "paid") "paidCheap") ((= lane "strong") "strong") (else rc.profile)))

fn ! writeProfileFor rc: RealCfg dir: String id: String lane: String -> String
  (pickWriteProfileX (readOr rc.lanes) id lane (writeProfile rc lane) (readOr (str dir "/providerHealth.asn")) (stalledProfilesOf dir id))

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

; (:m :ref CONDUCTOR-ZERO-MERGE :do "the changed paths inside the unit's :owns, untracked ones included; driver debris outside :owns (.asl/gatewayProfilePin.asn) is no edit, and an owned path the writer never created is simply absent, where git add -- owns failed on it and committed nothing")
fn ! ownedChanges! p: String owns: (List String) -> (List String)
  (if (listEmpty? owns)
    (if (fp/gitDirty? p) (list ".") (list))
    (let [(r (gitOut p (listAppend (list "status" "--porcelain" "--untracked-files=all" "--") owns)))]
      (if (!= r.exit 0) (list)
        (map (fn [(l String)] -> String
               (let [(path (optionOr (stringSlice l 3 (stringLength l)) ""))]
                 (match (stringIndexOf path " -> ") ((some at) (optionOr (stringSlice path (+ at 4) (stringLength path)) path)) ((none) path))))
             (filter (fn [(l String)] -> Bool (> (stringLength l) 3)) (stringLines r.out))))))

; (:m :ref CONDUCTOR-ZERO-MERGE :do "the driver commit stages only the owned paths that changed; true when a commit landed")
fn ! commitWrite! p: String owns: (List String) id: String model: String -> Bool
  (let [(changed (ownedChanges! p owns))]
    (if (listEmpty? changed) false
      (fp/driverCommitRow! p (if (listEmpty? owns) (list) changed) id model)))

; (:m :ref COORD-WIP-RESCUE :do "progress counts commits past the base except wip rescue commits, found by their ASN message head (:c :a wip :do; a rescued tree is kept work, not a finished write")
fn pastArgs base: String -> (List String)
  (list "rev-list" "--count" "--invert-grep" "--grep=^(:c :a wip :do" (str base "..HEAD"))

fn ! commitsPast? p: String base: String -> Bool
  (let [(r (gitOut p (pastArgs base)))]
    (or (!= r.exit 0) (!= (stringTrim r.out) "0")))

; (:m :ref WRITEESC :do "a write whose branch has no commit past its base and no changed owned file made no progress; an unreadable count is not a verdict")
fn ! noEdits? p: String base: String owns: (List String) -> Bool
  (and (not (commitsPast? p base)) (listEmpty? (ownedChanges! p owns)))

; (:m :ref VACUOUS-ON-FINISHED :do "a retained branch whose only work is a wip rescue commit is not a blank slate: noEdits? skips wip commits (a wip commit is no landed progress) but the vacuous-gate verdict compares with the base, and a gate green on a branch that already holds commits past the base is that work, not a gate green on main; blank means no commit at all past the base and no owned change")
fn ! blankSlate? p: String base: String owns: (List String) -> Bool
  (let [(r (gitOut p (list "rev-list" "--count" (str base "..HEAD"))))]
    (and (and (= r.exit 0) (= (stringTrim r.out) "0")) (listEmpty? (ownedChanges! p owns))))

; (:m :ref VACUOUS-ON-FINISHED :do "the write stage's vacuous verdict in one place: the tree is read for a blank slate (no commit past base, wip rescue included, no owned change) just before the writer runs, and the gate listed in :vacuousGates counts only then, so a retained wip-only branch with a green gate reaches gating; returns the writer's result and the verdict")
fn ! vacuousAround! p: String base: String owns: (List String) gate: String task: String run: (fn ! [] -> fr/Done) -> (Pair fr/Done Bool)
  (let [(blank (blankSlate? p base owns))
        (d (run))]
    (pair d (and blank (vacuousWrite? d.out gate task))))

; (:m :ref UNIT-AHEAD-GATING :do "a write whose gate failed still had its owned edits driver-committed, so a later claim found the work on sh/UNIT and ran another writer on it, whose doc-only change Leon judged vacuous against HEAD, forever (node2 2026-11-04: 27 of 41 branches ahead, never merged); a branch with commits past its base, no uncommitted owned change and a green unit gate is finished work: the write stage returns it as written without a writer run, unless the gate is also green on the merge-base, which is the vacuous verdict")
fn ! aheadGreen! rc: RealCfg dir: String u: st/Task c: CUnit p: String -> (Option Res)
  (let [(past (gitOut p (list "rev-list" "--count" (str (baseRef u) "..HEAD"))))]
    (if (or (stringEmpty? u.gate) (or (!= past.exit 0) (or (= (stringTrim past.out) "0") (not (listEmpty? (ownedChanges! p u.owns)))))) none
      (let [(cw (written c p (str "sh/" u.id)))
            (g (gatesRes rc.gateSec (gateCheckS dir) (taskText dir u) u cw))]
        (if (or (!= g.exit 0) (<= g.asserts 0)) none
          (let [(before (redBefore! rc dir u cw))
                (_ (fileAppend (journalPath dir) (str "(:ahead :unit " (st/q u.id) " :commits " (stringTrim past.out) " :gate (:exit 0 :executed " (n g.asserts) ") :base (:exit " (n (pairFirst before)) "))\n")))]
            (some (Res :tiers "" :ok (if (= (pairFirst before) 0) 0 1) :wt p :branch (str "sh/" u.id) :model "" :tokens 0 :costMicro 0 :claimedGreen 0
                       :sig (if (= (pairFirst before) 0) (vacuousSig u.gate) "") :ms g.ms :exit 0 :asserts g.asserts :verdict "")))))))

; (:m :ref UNIT-AHEAD-GATING :do "Leon's gate integrity reverts the changed files to HEAD, so on a branch already holding the unit's earlier commits it saw only the new edit; the writer runs with HEAD soft-reset to the merge-base, the earlier work staged, so the revert is measured against the unit base; when the writer made no commit HEAD goes back to the branch tip with the new edit left on top, and a Leon commit holds the whole unit")
fn ! onBaseRun! p: String base: String run: (fn ! [] -> fr/Done) -> fr/Done
  (let [(head (stringTrim (gitOut p (list "rev-parse" "HEAD")).out))
        (mb (stringTrim (gitOut p (list "merge-base" "HEAD" base)).out))]
    (if (or (stringEmpty? mb) (or (stringEmpty? head) (= mb head))) (run)
      (if (!= (gitOut p (list "reset" "-q" "--soft" mb)).exit 0) (run)
        (let [(d (run))
              (now (stringTrim (gitOut p (list "rev-parse" "HEAD")).out))
              (_ (if (= now mb) (= (gitOut p (list "reset" "-q" "--soft" head)).exit 0) false))]
          d))))

; (:m :ref CONDUCTOR-ZERO-MERGE :do "a unit worktree kept across retries was reused as it stood, so a unit created in the morning ran Leon and its gates on the morning's tree all day (NODE2-ASEX-DETACHED at ace2ae8ec while main moved on); a reused worktree with no tracked change is brought onto its base like a re-attached one")
fn ! reuseWt! rc: RealCfg u: st/Task path: String -> (Result String String)
  (if (stringEmpty? (stringTrim (gitOut path (list "status" "--porcelain" "--untracked-files=no")).out))
    (freshBase! rc u path)
    (ok path))

; (:m :ref CONDUCTOR-ZERO-MERGE :do "how far the unit's tree is behind its base, for the receipt: (:base :sha S :behind N)")
fn ! baseNote! p: String base: String -> String
  (let [(sha (stringTrim (gitOut p (list "rev-parse" "--short" base)).out))
        (behind (stringTrim (gitOut p (list "rev-list" "--count" (str "HEAD.." base))).out))]
    (str "(:base :sha " (st/q sha) " :behind " (if (stringEmpty? behind) "-1" behind) ")"))

; (:m :ref ORCH-NODE2-CUTOVER-BUG :do "a node whose ~/.asl/hub.asn names a hub socket must not start a Leon from a worktree whose providers.asl predates the hub client: that Leon talks to no hub and its calls are served in-process, outside the shared buckets; the write stage refuses with ERR_HUB_CLIENT_MISSING instead")
fn ! hubGuard! home: String wt: String -> (Option Res)
  (match (hp/hubPreflight home wt)
    ((err e) (some (failRes e)))
    ((ok _) none))

; (:m :ref DEV-PROMOTE-ON-DEPLOY :do "a unit worktree must hold the deployed Leon: the last commit touching asl/packages/asl-agent on the deployed main (the conductor's --repo) is an ancestor of the unit's HEAD; a stale clean worktree is rebased onto the deployed main and the write goes on, a dirty one or a rebase conflict (aborted) returns a STALE_NEEDS_REBASE result, which finish! parks as blocked :await rebase with no failure count and no ladder hop; an unreadable deployed head is not a verdict")
fn staleSig? sig: String -> Bool
  (stringStartsWith? sig "STALE_NEEDS_REBASE ")

fn staleRes sha: String main: String -> Res
  (Res :tiers "" :ok 0 :wt "" :branch "" :model "" :tokens 0 :costMicro 0 :claimedGreen 0 :sig (str "STALE_NEEDS_REBASE leon " sha " main " main) :ms 0 :exit 1 :asserts 0 :verdict "")

; (:m :ref STALE-WAKE :do "a word after its key in a stale signature (leon SHA, main SHA); empty when absent")
fn staleField sig: String key: String -> String
  (match (listGet (stringSplit sig (str " " key " ")) 1)
    ((some r) (optionOr (listHead (stringSplit r " ")) ""))
    ((none) ""))

; (:m :ref COND-PROVIDER-FAIL-NO-HOP :do "the store's ladder.asn may hold one (:providerFail :backoffS S :maxInRow N :patterns (\"p\" ...)) row, patterns last and without parentheses, matched case-insensitively against the failed write's signature; schema in asl/grammar/conductorConfig.asn; no row or a row pfErrors rejects means the documented defaults (adopted: 60 s, 6 in a row, the provider-class words below)")
fn pfDefaultPatterns -> (List String)
  (list "err_vendor" "err_no_upstream" "bad gateway" "service unavailable" "overloaded" " 502" " 503" " 504" " 429" "breaker")

fn pfRowOf dir: String -> String
  (optionOr (listFind (fn [(l String)] -> Bool (stringStartsWith? (stringTrim l) "(:providerFail ")) (stringLines (readOr (ladderPath dir)))) "")

fn pfHead row: String -> String
  (optionOr (listHead (stringSplit row " :patterns ")) row)

fn pfPatterns row: String -> (List String)
  (match (listGet (stringSplit row " :patterns (") 1)
    ((none) (pfDefaultPatterns))
    ((some r)
      (let [(parts (stringSplit (optionOr (listHead (stringSplit r ")")) "") "\""))]
        (filter (fn [(p String)] -> Bool (not (stringEmpty? p)))
                (map (fn [(i Int64)] -> String (stringLower (optionOr (listGet parts i) "")))
                     (filter (fn [(i Int64)] -> Bool (= (mod i 2) 1)) (range 0 (listLength parts))))))))

fn pfInt row: String key: String dflt: Int64 -> Int64
  (optionOr (stringToInt64 (sp/tokAfter (pfHead row) key)) dflt)

fn pfBackoffS row: String -> Int64
  (pfInt row ":backoffS" 60)

fn pfMaxInRow row: String -> Int64
  (pfInt row ":maxInRow" 6)

; (:m :ref COND-PROVIDER-FAIL-NO-HOP :do "config check of a (:providerFail ...) row: unknown keys, :backoffS outside 1..3600, :maxInRow outside 1..100 and an empty :patterns list are errors; no error means the row is used")
fn pfErrors row: String -> (List String)
  (let [(keys (filter (fn [(t String)] -> Bool (stringStartsWith? t ":")) (stringSplit (pfHead row) " ")))
        (bad (filter (fn [(k String)] -> Bool (not (listContains? (list ":backoffS" ":maxInRow") k))) keys))
        (b (pfBackoffS row))
        (m (pfMaxInRow row))]
    (listAppend
      (map (fn [(k String)] -> String (str "unknown key " k)) bad)
      (listAppend
        (if (or (< b 1) (> b 3600)) (list (str ":backoffS " (n b) " outside 1..3600")) (list))
        (listAppend
          (if (or (< m 1) (> m 100)) (list (str ":maxInRow " (n m) " outside 1..100")) (list))
          (if (and (stringContains? row " :patterns ") (listEmpty? (pfPatterns row))) (list ":patterns is empty") (list))))))

fn ! pfCfg dir: String -> String
  (let [(row (pfRowOf dir))]
    (if (listEmpty? (pfErrors row)) row ""))

fn providerFailSig? sig: String pats: (List String) -> Bool
  (let [(low (stringLower sig))]
    (listAny? (fn [(p String)] -> Bool (stringContains? low p)) pats))

; (:m :ref COND-PROVIDER-FAIL-NO-HOP :do "a write that left no commit past its base made no progress; an unreadable count or no worktree counts as none, so the provider class decides")
fn ! noCommits? p: String base: String -> Bool
  (if (stringEmpty? p) true
    (let [(r (gitOut p (pastArgs base)))]
      (or (!= r.exit 0) (= (stringTrim r.out) "0"))))

; (:m :ref COND-PROVIDER-FAIL-NO-HOP :do "<store>/providerWait.asn keeps (:pw :unit ID :n N :until MS) rows, the newest per unit wins: N is the provider fails in a row (0 after any other outcome), MS when the unit may be admitted again; the unit row itself (fails, sig, lane) is untouched")
fn providerWaitPath dir: String -> String
  (str dir "/providerWait.asn")

fn ! pwLast dir: String id: String -> (Pair Int64 Int64)
  (match (listLast (filter (fn [(l String)] -> Bool (stringContains? l (str ":unit " (st/q id) " "))) (stringLines (readOr (providerWaitPath dir)))))
    ((none) (pair 0 0))
    ((some l) (pair (optionOr (stringToInt64 (sp/tokAfter l ":n")) 0) (optionOr (stringToInt64 (sp/tokAfter l ":until")) 0))))

fn ! pwNote! dir: String id: String run: Int64 until: Int64 -> Bool
  (ok? (fileAppend (providerWaitPath dir) (str "(:pw :unit " (st/q id) " :n " (n run) " :until " (n until) ")\n")))

fn ! providerWaiting? dir: String id: String now: Int64 -> Bool
  (> (pairSecond (pwLast dir id)) now)

fn ! pwReset! dir: String id: String -> Bool
  (if (> (pairFirst (pwLast dir id)) 0) (pwNote! dir id 0 0) false)

; (:m :ref COND-PROVIDER-FAIL-NO-HOP :do "a provider-class write failure (sig matches a pattern, no commit past base, not stale or vacuous, at most :maxInRow in a row) requeues the unit after :backoffS with its fail count, signature and lane untouched and journals (:providerFail :unit :route :backoffS :n :at); the next one past :maxInRow is an ordinary failure, so a dead route cannot hold a unit forever")
fn ! providerHit? ctx: Ctx u: st/Task c: CUnit res: Res -> Bool
  (let [(row (pfCfg ctx.dir))]
    (and (= res.ok 0)
         (and (not (staleSig? res.sig))
              (and (not (vacuousSig? res.sig))
                   (and (providerFailSig? res.sig (pfPatterns row))
                        (and (noCommits? res.wt u.base)
                             (<= (+ (pairFirst (pwLast ctx.dir c.id)) 1) (pfMaxInRow row))))))))

fn ! providerRequeue! ctx: Ctx c: CUnit res: Res -> Unit
  (let [(row (pfCfg ctx.dir))
        (back (pfBackoffS row))
        (now (/ (nowNs) 1000000))
        (run (+ (pairFirst (pwLast ctx.dir c.id)) 1))
        (_ (wipSave! ctx c.id "providerFail"))
        (_ (dropLease! ctx c))
        (_ (pwNote! ctx.dir c.id run (+ now (* back 1000))))
        (_ (fileAppend (journalPath ctx.dir) (str "(:providerFail :unit " (st/q c.id) " :route " (st/q res.model) " :backoffS " (n back) " :n " (n run) " :at " (n now) ")\n")))
        (_ (move! ctx (with c :epoch 0) "ready" "write" res.model 0 0 (str "providerFail: " (verdictSig res.sig)) res.ms))]
    ())

; (:m :ref STALE-WAKE :do "<store>/repo.path names the conductor's --repo (the deployed main); written by run")
fn repoPath dir: String -> String
  (str dir "/repo.path")

; (:m :ref COND-REBASE-WAKE-LOOP :do "the lead row a stale unit parks behind; while it stands, a moved main alone never wakes the unit again")
fn staleLeadRow id: String -> String
  (str "(:lead :unit " (st/q id) " :needs rebase")

; (:m :ref COND-REBASE-WAKE-LOOP :do "short head of the unit branch sh/ID in the deployed repo, empty when the repo or the branch is absent; a changed head means someone rebased the unit")
fn ! unitHead! dir: String id: String -> String
  (let [(repo (stringTrim (readOr (repoPath dir))))]
    (if (stringEmpty? repo) ""
      (let [(g (gitOut repo (list "rev-parse" "--short=9" "--verify" "-q" (str "refs/heads/sh/" id))))]
        (if (= g.exit 0) (stringTrim g.out) ""))))

; (:m :ref COND-REBASE-WAKE-LOOP :do "the (:conductor ...) line of the store's ladder.asn, empty when absent; its only key is :staleWakeMax")
fn cdRowOf dir: String -> String
  (optionOr (listFind (fn [(l String)] -> Bool (stringStartsWith? (stringTrim l) "(:conductor ")) (stringLines (readOr (ladderPath dir)))) "")

; (:m :ref COND-REBASE-WAKE-LOOP :do "config check of a (:conductor ...) row: an unknown key or :staleWakeMax outside 1..100 is an error; no error means the row is used")
fn cdErrors row: String -> (List String)
  (let [(keys (filter (fn [(t String)] -> Bool (stringStartsWith? t ":")) (stringSplit row " ")))
        (bad (filter (fn [(k String)] -> Bool (not (= k ":staleWakeMax"))) keys))
        (m (optionOr (stringToInt64 (sp/tokAfter row ":staleWakeMax")) 1))]
    (listAppend
      (map (fn [(k String)] -> String (str "unknown key " k)) bad)
      (if (or (< m 1) (> m 100)) (list (str ":staleWakeMax " (n m) " outside 1..100")) (list))))

; (:m :ref COND-REBASE-WAKE-LOOP :do "how many failed wakes a stale unit gets before it parks behind its lead row: (:conductor :staleWakeMax N) in the store's ladder.asn, default 1 (adopted), a row cdErrors rejects means the default")
fn ! staleWakeMax dir: String -> Int64
  (let [(row (cdRowOf dir))]
    (if (listEmpty? (cdErrors row)) (optionOr (stringToInt64 (sp/tokAfter row ":staleWakeMax")) 1) 1))

; (:m :ref STALE-WAKE :do "a unit blocked :await rebase wakes once the deployed main moved past the head recorded in its stale signature: it goes back to ready for one write retry, lane, fails and esc unchanged, with sig STALE_WOKEN main HEAD; an unchanged or unreadable head leaves it blocked")
fn ! staleWake! ctx: Ctx c: CUnit -> Unit
  (let [(was (staleField c.sig "main"))
        (repo (stringTrim (readOr (repoPath ctx.dir))))
        (head (if (stringEmpty? repo) "" (stringTrim (gitOut repo (list "rev-parse" "--short=9" "HEAD")).out)))
        (cur (unitHead! ctx.dir c.id))
        (moved (and (not (stringEmpty? cur)) (!= cur (staleField c.sig "head"))))
        (parked (stringContains? (readOr (escalationsPath ctx.dir)) (staleLeadRow c.id)))
        (mainMoved (and (not (stringEmpty? head)) (and (!= head was) (not parked))))]
    (if (not (or moved mainMoved)) ()
      (let [(_ (fileAppend (journalPath ctx.dir) (str "(:stale :unit " (st/q c.id) " :result woken :from " (st/q was) " :to " (st/q head) " :why " (st/q (if moved "branch" "main")) ")\n")))
            (_ (move! ctx (with c :await "" :sig (str "STALE_WOKEN main " head)) "ready" "wake" "" 0 0 "staleWake" 0))]
        ())))

fn ! leonGuard! repo: String wt: String -> (Option Res)
  (let [(d (gitOut repo (list "log" "-1" "--format=%H" "HEAD" "--" "asl/packages/asl-agent")))
        (sha (stringTrim d.out))
        (short (optionOr (stringSlice sha 0 9) sha))
        (main (stringTrim (gitOut repo (list "rev-parse" "--short=9" "HEAD")).out))]
    (cond
      ((or (!= d.exit 0) (stringEmpty? sha)) none)
      ((= (gitOut wt (list "merge-base" "--is-ancestor" sha "HEAD")).exit 0) none)
      ((not (stringEmpty? (stringTrim (gitOut wt (list "status" "--porcelain" "--untracked-files=no")).out))) (some (staleRes short main)))
      ((and (= (gitOut wt (list "fetch" "-q" repo "HEAD")).exit 0) (= (gitOut wt (list "rebase" "-q" "FETCH_HEAD")).exit 0)) none)
      (else (let [(_ (gitOut wt (list "rebase" "--abort")))] (some (staleRes short main))))))

fn ! writeGuard! home: String repo: String wt: String dir: String id: String -> (Option Res)
  (match (hubGuard! home wt)
    ((some r) (some r))
    ((none)
      (let [(before (stringTrim (gitOut wt (list "rev-parse" "HEAD")).out))
            (g (leonGuard! repo wt))
            (after (stringTrim (gitOut wt (list "rev-parse" "HEAD")).out))
            (_ (if (and (not (some? g)) (!= before after)) (ok? (fileAppend (journalPath dir) (str "(:stale :unit " (st/q id) " :result rebased :from " (st/q before) " :to " (st/q after) ")\n"))) false))]
        g)))

; (:m :ref SE5C-CONDUCTOR-POOL :do "a free-lane write goes to the Leon pool process named by --leon-pool when it answers (:status), as one session of that process; a refused or unreachable submit (exit 125) and every other lane or an unset pool spawn Leon as before, so the flag only ever moves where Leon runs")
fn ! runWrite! rc: RealCfg lane: String id: String prof: String p: String task: String owns: (List String) gates: (List String) extra: String -> fr/Done
  (if (lc/pooledWrite? lane rc.leonPool)
    (let [(d (fp/runLeonPooledExtra! rc.leonPool (str id "-" (stringFromInt64 (nowMs))) prof p rc.home task owns gates rc.leaseSec extra))]
      (if (= d.exit 125) (fp/runLeonProfileExtra! prof rc.repo p rc.home task owns gates rc.leaseSec rc.keys extra) d))
    (fp/runLeonProfileExtra! prof rc.repo p rc.home task owns gates rc.leaseSec rc.keys extra))

; (:m :ref CONDUCTOR-REPO-HEALTH :do "a unit worktree directory is valid when git sees it as its own top level; one that exists without a valid .git (a vanished common dir leaves such shells, orphan writes recreate them) is moved aside to BASE/orphan-ID-MS, journaled as (:orphan :unit :moved), and the unit worktree is added again, instead of the writer failing on it as ERR_HUB_CLIENT_MISSING")
fn ! worktreeValid? path: String -> Bool
  (let [(r (gitOut path (list "rev-parse" "--show-toplevel")))]
    (and (= r.exit 0) (= (resultOr (realPath (stringTrim r.out)) (stringTrim r.out)) (resultOr (realPath path) path))))

fn ! settleWt! rc: RealCfg dir: String u: st/Task path: String -> (Result String String)
  (cond
    ((not (fileExists? path)) (attachOrAdd rc u path))
    ((worktreeValid? path) (reuseWt! rc u path))
    (else
      (let [(aside (str rc.wt.base "/orphan-" u.id "-" (n (/ (nowNs) 1000000))))
            (mv (pathRename path aside))]
        (match mv
          ((err e) (err (str "orphan worktree dir not movable: " e)))
          ((ok _)
            (let [(_ (fileAppend (journalPath dir) (str "(:orphan :unit " (st/q u.id) " :moved " (st/q aside) ")\n")))
                  (_ (gitOut rc.repo (list "worktree" "prune")))]
              (attachOrAdd rc u path)))))))

; (:m :ref COND-TASK-SPEC :do "each owned file's state in the unit worktree at claim: its line count, -1 when it does not exist yet; directory entries (a trailing slash) are left out")
fn ! ownedStates! wt: String owns: (List String) -> (List (Pair String Int64))
  (map (fn [(p String)] -> (Pair String Int64)
         (pair p (match (fileReadString (str wt "/" p)) ((ok t) (listLength (stringLines t))) ((err _) -1))))
       (filter (fn [(p String)] -> Bool (not (stringEndsWith? p "/"))) owns))

; (:m :ref COND-TASK-SPEC :do "the brief the writer gets: the stored task text (never rewritten in the store) with the owned paths' states at claim added, then the prior note when there is one")
fn ! briefTask! wt: String dir: String u: st/Task prior: String -> String
  (let [(text (bf/briefFor (taskText dir u) (ownedStates! wt u.owns)))]
    (if (stringEmpty? prior) text (str text "\n\n" prior)))

fn ! writeRes rc: RealCfg dir: String u: st/Task c: CUnit -> Res
  (writeResWith runWrite! rc dir u c)

; (:m :ref COND-TASK-SPEC :do "the write stage with its Leon run injected, so a gate can record the task text the writer would receive; writeRes passes runWrite!")
fn ! writeResWith run: (fn ! [(rc RealCfg) (lane String) (id String) (prof String) (p String) (task String) (owns (List String)) (gates (List String)) (extra String)] -> fr/Done) rc: RealCfg dir: String u: st/Task c: CUnit -> Res
  (let [(path (w/wtPath rc.wt u.id))
        (added (settleWt! rc dir u path))]
    (match added
      ((err e) (failRes e))
      ((ok p)
       (match (writeGuard! rc.home rc.repo p dir u.id)
        ((some refused) refused)
        ((none)
        (match (aheadGreen! rc dir u c p)
        ((some done) done)
        ((none)
        (let [(prior (priorNote! dir u.id))
              (task (briefTask! p dir u prior))
              (prof (writeProfileFor rc dir u.id c.lane))
              (arm (writeArm rc u.id))
              (_ (fileAppend (journalPath dir) (str "(:profile :unit " (st/q u.id) " :lane " (st/q c.lane) " :profile " (st/q prof) (if (stringEmpty? arm) "" (str " :arm " (st/q arm))) " :at " (n (/ (nowNs) 1000000)) ")\n")))
              (pv (vacuousAround! p u.base u.owns u.gate task (fn [] -> fr/Done (onBaseRun! p (baseRef u) (fn [] -> fr/Done (run rc c.lane u.id prof p task u.owns (if (stringEmpty? u.gate) (list) (list u.gate)) (armExtra arm)))))))
              (d (pairFirst pv))
              (model (servedModel d.out))
              (vacuous (pairSecond pv))
              (_ (if vacuous false (commitWrite! p u.owns u.id model)))
              ; (:m :ref CONDUCTOR-ZERO-MERGE :do "review diffs base...HEAD and merge trains the branch, so a write is progress only when a commit landed: an owned edit the driver could not commit was reviewed as an empty diff 6 times (NODE2-ASEX-DETACHED)")
              (noEdit (and (= d.exit 0) (not (commitsPast? p u.base))))]
          (Res :tiers "" :ok (if (and (= d.exit 0) (and (not noEdit) (not vacuous))) 1 0) :wt p :branch (str "sh/" u.id) :model model :alias (servedAliasOf d.out) :tokens (leonTokens d.out) :costMicro (leonCost d.out (rs/costRows (readOr (str rc.home "/.asl/gateway.asn")) (readOr rc.lanes)) model) :claimedGreen 0
               :sig (cond (vacuous (vacuousSig u.gate)) ((!= d.exit 0) (gateSig d.out)) (noEdit "noEdit") (else "")) :ms d.ms :exit d.exit :asserts 0 :verdict "")))))))))

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

; (:m :ref CONDUCTOR-ZERO-MERGE :do "dev sat at ace2ae8ec all day while main moved, until the lead fast-forwarded it by hand; before each train main is brought into dev: fast-forward when dev has nothing of its own, else a merge commit, and a conflict refuses the train rather than merging onto a stale dev")
fn ! promoteDev! rc: RealCfg -> String
  (if (= rc.devRepo rc.repo) "same"
    (let [(f (gitOut rc.devRepo (list "fetch" "--quiet" rc.repo "+refs/heads/main:refs/heads/srcMain")))]
      (cond
        ((!= f.exit 0) "fetchFailed")
        ((= (gitOut rc.devRepo (list "merge-base" "--is-ancestor" "srcMain" "HEAD")).exit 0) "current")
        ((= (gitOut rc.devRepo (list "merge" "--ff-only" "--quiet" "srcMain")).exit 0) "fastForward")
        (else
          (let [(m (gitOut rc.devRepo (list "merge" "--no-ff" "--quiet" "-m" "(:c :a coord :do \"bring main into dev before a train\" :ev (CONDUCTOR-ZERO-MERGE))" "srcMain")))]
            (if (= m.exit 0) "merged"
              (let [(_ (gitOut rc.devRepo (list "merge" "--abort")))] "conflict")))))))

fn ! mergeRes rc: RealCfg u: st/Task c: CUnit -> Res
  (let [(cur (currentBranch rc.devRepo))
        (promoted (if (or (= rc.devBranch "main") (or (= rc.devBranch "master") (!= cur rc.devBranch))) "" (promoteDev! rc)))]
    (cond
      ((or (= rc.devBranch "main") (or (= rc.devBranch "master") (!= cur rc.devBranch)))
        (failRes (str "refused: devRepo is on " cur ", dev branch " rc.devBranch " must not be main")))
      ((or (= promoted "conflict") (= promoted "fetchFailed"))
        (failRes (str "refused: main does not come into dev (" promoted ")")))
      (else
      (let [(_ (if (= rc.devRepo rc.repo) 0 (dropRemotes! rc.devRepo)))
            (fetched (if (= rc.devRepo rc.repo) (fr/Done :idx 0 :exit 0 :out "" :ms 0 :verdict "")
                       (gitOut rc.devRepo (list "fetch" "--quiet" rc.repo (str "+refs/heads/" c.branch ":refs/heads/" c.branch)))))
            (d (fr/runOneLimited (fr/job (list (str rc.devRepo "/bin/asl") "train" c.branch "--onto" "HEAD" "--repo" rc.devRepo "--commit") rc.devRepo (mergeEnv))
                                 (fr/limits 3600 200)))]
        (if (and (= fetched.exit 0) (and (= d.exit 0) (not (stringContains? d.out ":commitError"))))
          (let [(_ (w/removeWt! rc.wt u.id true))]
            (Res :tiers "" :ok 1 :wt "" :branch "" :model "" :tokens 0 :costMicro 0 :claimedGreen 0 :sig "" :ms d.ms :exit 0 :asserts 0 :verdict ""))
          (let [(f (failRes (gateSig d.out)))] (with f :ms d.ms)))))))

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

; (:m :ref REDBEFORE-SHARE :do "the red-before result depends only on the merge-base commit and the gate text, so a genuine red (exit 1..123) is remembered in <store>/runs/UNIT-redbase.asn under that sha and gate and a later gate stage of the same unit (a fix round) reuses it instead of checking the base out and running the gate again; a timeout, a kill, a green base or a different sha or gate runs it afresh")
fn redBaseRow sha: String gate: String r: (Pair Int64 Int64) -> String
  (str "(:redBase :sha " (st/q sha) " :exit " (n (pairFirst r)) " :executed " (n (pairSecond r)) " :gate " (st/q gate) ")")

fn redBaseHit text: String sha: String gate: String -> (Option (Pair Int64 Int64))
  (if (and (stringContains? text (str "(:redBase :sha " (st/q sha) " ")) (stringContains? text (str " :gate " (st/q gate) ")")))
    (let [(e (optionOr (stringToInt64 (sp/tokAfter text ":exit")) 0))
          (x (optionOr (stringToInt64 (sp/tokAfter text ":executed")) 0))]
      (if (and (> e 0) (< e 124)) (some (pair e x)) (none)))
    (none))

fn ! redCached! path: String sha: String gate: String run: (fn [] -> (Pair Int64 Int64)) -> (Pair Int64 Int64)
  (match (redBaseHit (readOr path) sha gate)
    ((some r) r)
    ((none)
      (let [(r (run))
            (_ (if (and (> (pairFirst r) 0) (< (pairFirst r) 124)) (ok? (fileWrite path (str (redBaseRow sha gate r) "\n"))) false))]
        r)))

; (:m :ref COND3 :do "red-before: the declared gate is run once more in a detached checkout of the unit's merge-base; its exit and asserts go to the receipt the ladder reads (gatesProven needs a :redBefore row); a gate that is already green at the base leaves no redBefore row, so the ladder cannot merge it on R1")
fn ! redBefore! rc: RealCfg dir: String u: st/Task c: CUnit -> (Pair Int64 Int64)
  (let [(mb (gitOut c.wt (list "merge-base" "HEAD" (baseRef u))))
        (sha (stringTrim mb.out))]
    (if (!= mb.exit 0) (pair -1 0)
      (redCached! (runPath dir u.id "redbase" "asn") sha u.gate
        (fn [] -> (Pair Int64 Int64)
          (let [(bpath (str c.wt ".base"))
                (_ (gitOut c.wt (list "worktree" "remove" "--force" bpath)))
                (added (gitOut c.wt (list "worktree" "add" "--detach" bpath sha)))]
            (if (!= added.exit 0) (pair -1 0)
              (let [(d (fr/runShell! u.gate bpath (fr/childEnv (list)) (fr/heavy (fr/limits rc.gateSec 200) "writer" "")))
                    (_ (gitOut c.wt (list "worktree" "remove" "--force" bpath)))]
                (pair d.exit (optionOr (fr/executedOf d.out) 0)))))))))

fn receiptText u: st/Task g: Res before: (Pair Int64 Int64) base: String -> String
  (str "(:receipt " (st/q u.id) " :gates ((:gate " (st/q u.gate) " :exit " (n g.exit) " :executed " (n g.asserts) "))"
       (if (> (pairFirst before) 0) (str " :redBefore ((:gate " (st/q u.gate) " :exit " (n (pairFirst before)) " :executed " (n (pairSecond before)) "))") "")
       " " base ")")

; (:m :ref COND3 :do "the real gates stage: the conductor's own rerun of the gate in the unit's worktree plus the red-before run, and the receipt written to <store>/runs/UNIT-receipt.asn for the review stage")
fn ! gatesStage rc: RealCfg dir: String u: st/Task c: CUnit -> Res
  (let [(g (gatesRes rc.gateSec (gateCheckS dir) (taskText dir u) u c))]
    (if (and (= g.exit 0) (> g.asserts 0))
      (let [(before (redBefore! rc dir u c))
            (_ (dirCreate (runsDir dir)))
            (_ (fileWrite (runPath dir u.id "receipt" "asn") (str (receiptText u g before (baseNote! c.wt (baseRef u))) "\n")))]
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
        (writer (l/reviewWriter c.model rc.writerAlias))
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

; (:m :ref COND-GRACEFUL-RESTART :do "a restart file in the store (written by `conductor restart`, which vps sync --deploy runs when the deployed range touches asl/tools/coord) drains the loop: nothing new is launched, neither an admission nor a unit's next stage, in-flight stages are polled until they finish or :untilMs passes, one (:restart :finished :left) journal row records them, and the loop ends with exit 0 so systemd (Restart=always) starts the new code; a stage still running at the deadline is left to the next start, which resumes it from its rows")
fn restartPath dir: String -> String
  (str dir "/restart")

fn ! draining? dir: String -> Bool
  (fileExists? (restartPath dir))

fn ! requestRestart! dir: String graceSec: Int64 -> Bool
  (let [(at (/ (nowNs) 1000000))]
    (ok? (fileWrite (restartPath dir) (str "(:restart :at " (n at) " :untilMs " (n (+ at (* graceSec 1000))) ")\n"))))

fn ! restartUntil! dir: String -> Int64
  (let [(until (match (st/rowFields (readOr (restartPath dir)) "restart") ((ok fs) (st/intField fs "untilMs")) ((err _) 0)))]
    (if (> until 0) until (+ (/ (nowNs) 1000000) 1200000)))

fn ! flyingIds! dir: String -> (List String)
  (map (fn [(c CUnit)] -> String c.id) (filter inFlight? (readCUnits! dir)))

fn ! restartDrain! ctx: Ctx until: Int64 sliceMs: Int64 -> (List String)
  (let [(_ (tick! ctx))
        (left (flyingIds! ctx.dir))]
    (if (or (listEmpty? left) (> (/ (nowNs) 1000000) until)) left
      (let [(_ (sleepMs sliceMs))] (restartDrain! ctx until sliceMs))))

fn ! restart! ctx: Ctx -> (List String)
  (let [(was (flyingIds! ctx.dir))
        (left (restartDrain! ctx (restartUntil! ctx.dir) 500))
        (done (filter (fn [(id String)] -> Bool (not (listContains? left id))) was))
        (_ (fileAppend (journalPath ctx.dir) (str "(:restart :finished " (st/qList done) " :left " (st/qList left) " :at " (n (/ (nowNs) 1000000)) ")\n")))
        (_ (pathRemove (restartPath ctx.dir)))]
    left)

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
  (cond
    ((fileExists? (stopPath ctx.dir)) (let [(_ (stopAll! ctx)) (_ (pathRemove (stopPath ctx.dir)))] false))
    ((draining? ctx.dir) (let [(_ (restart! ctx))] false))
    (else
    (let [(_ (importCycle! ctx))
          (_ (tick! ctx))
          (_ (offerStrong! ctx snapshot))
          (_ (if refreshDue (refreshWake! ctx snapshot refresh) 0))]
      true)))

fn ! sleepSlices! dir: String slices: Int64 sliceMs: Int64 -> Unit
  (if (or (or (<= slices 0) (fileExists? (stopPath dir))) (draining? dir)) ()
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
             :attractorAb (= (st/opt args "attractor-ab" "off") "on") :leonPool (st/opt args "leon-pool" "")))

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
                    (list) (list "repo" "dev-repo" "dev" "worktrees" "archive" "home" "keys" "lanes" "writer-alias" "profile" "attractor-ab" "leon-pool")))]
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
      ((= cmd "requeue") (let [(ids (if (listContains? args "--all-blocked")
                                      (map (fn [(c CUnit)] -> String c.id) (filter (fn [(c CUnit)] -> Bool (= c.st "blocked")) (readCUnits! dir)))
                                      (filter (fn [(s String)] -> Bool (not (stringEmpty? s))) (map stringTrim (stringSplit (st/opt args "ids" "") ",")))))]
                           (do (println (str "(:requeue :requested " (if (requestRequeue! dir ids) "true" "false") " :units " (st/qList ids) ")")) (ok 0))))
      ((= cmd "check") (let [(ps (startupProblemsFor rc))
                             (_ (map (fn [(l String)] -> Unit (println l)) (staleOwnsFor! dir args rc)))]
                         (do (println (str "(:check :problems " (st/qList ps) ")")) (ok (if (listEmpty? ps) 0 1)))))
      ((= cmd "restart") (do (println (str "(:restart :requested " (if (requestRestart! dir (st/intOpt args "grace-sec" 1200)) "true" "false") ")")) (ok 0)))
      ((= cmd "stop") (do (println (str "(:stop :requested " (if (requestStop! dir) "true" "false") ")")) (ok 0)))
      ((= cmd "run")
        (let [(ps (startupProblemsFor rc))]
          (if (not (listEmpty? ps))
            (do (eprintln (str "(:refuse :why coverage :problems " (st/qList ps) ")")) (ok 1))
            (let [(_ (pathRemove (stopPath dir)))
                  (_ (pathRemove (restartPath dir)))
                  (_ (let [(l (st/opt args "ledger" ""))] (if (stringEmpty? l) (ok ()) (fileWrite (ledgerPath dir) (str l "\n" (st/opt args "ledger-base" "HEAD") "\n")))))
                  (_ (fileWrite (repoPath dir) (str rc.repo "\n")))
                  (_ (fileWrite (worktreesPath dir) (str rc.wt.base "\n")))
                  (seeded (seedGradeCommits! dir))
                  (_ (if (< seeded 0) (ok ()) (fileAppend (journalPath dir) (str "(:gradeSeed :n " (n seeded) ")\n"))))
                  (_ (println (str "(:run :store " (st/q dir) " :refreshMin " (n (st/intOpt args "refresh-min" 15)) ")")))]
              (ok (runLoop! ctx (fn [] -> (List (Pair String Int64)) (laneSnapshot rc)) (fn [] -> Unit (let [(_ (sr/subsRefreshCli! (list)))] ()))
                            (nowMs) (* (st/intOpt args "refresh-min" 15) 60000) 12))))))
      (else (do (eprintln "usage: conductor tick|run|status|check|stop|requeue (--ids A,B|--all-blocked)|restart [--grace-sec S]|wake LANE --store DIR") (ok 2)))))
