(module asl-tools/coord/conductor
  :x [utf8Clip verdictSig spawnFailedSig repoClip mergeHoldWhy porcelainPaths unquoteGit hubGuard! leonGuard! staleSig? staleField staleWake! unitHead! cdErrors repoPath gradeCommitsPath gradeCommitRecorded? ledgerForged! settleWt! worktreeValid? ownedStates! briefTask! writeResWith pinExtra leonReceiptSave! repoBrokenPath repoErr! repoGate! ledgerState! ledgerSig! seedGradeCommits! ledgerGuard receiptRowOf fail! finish! launch! step! stepAll! priorNote! providerRequeue! worktreesPath wtBase servedField servedAliasOf servedModel journalA! wipSave! gradeLand! staleOwnsFor! CUnit Res Pace Ctx RealCfg
      cuDir cuPath journalPath escalationsPath runsDir runPath runRow renderCUnit parseCUnit readCUnits! writeCUnit! costText renderRes parseRes
      allowanceUnlimited fixedPace jobserverPace gateSig trainSig mergeBusy? surfaceReads! storeReadError! quarantinedIds quarantineRow! realCtx trainLimitSec stageSecDefault clampMergeCheckSec renamePairs ownsRemap! releaseQuarantined! unparseableIds! quarantineDir mergeRes mergeResWith mergeVerdictRes! mergeCheckWhy realMergeCheck! rulingVerdict
      depStalled? armOf writeArm armExtra withToolRoot! vacuousWrite? vacuousSig vacuousSig? ownedChanges! commitWrite! noEdits? blankSlate? vacuousAround! aheadGreen! reviewFailedSinceWriter? onBaseRun! onBaseEnter! onBaseHeal! attachOrAddIn! outsideOwned! writerOf! baseRef moveA! resolved! repoBase! aheadMarked? commitsPast? checkOne! gateTimeoutSig gateRowOf gateErrors gateCheckS gateTimeoutSig? move! waitMore! parkedOf gateTimeoutRequeue! wakeRowsOf wakeErrors freeWake! blockSig reuseWt! baseNote! promoteDev! pickWriteProfile pickWriteProfileH pickWriteProfileX writeProfileFor stalledProfilesOf stalledProfilePath schedPace lightSlotsAt! rungCap hopsSince pfDefaultPatterns pfRowOf pfPatterns pfBackoffS pfMaxInRow pfErrors pfCfg providerFailSig? noCommits? providerHit? providerWaiting? pwLast offerBacklog! leadBacklogCap leadFresh? leadTtlMs nextRung! priorNote! tick! wake! status! drain! stopAll! gatesRes redBaseRow redBaseHit redCached! loadUnit! writeRes! realRes realLaunch attachOrAdd parkedRows! needRows! importCycle! ledgerPath offerStrong! lastTiers tiersOfRows offeredRung! offerPath freshBase! leonTokens leonCost dropRemotes! mergeEnv realPace      settled? realCfg sigKey laneSnapshot refreshWake! availWake! availNames starvedAwait? AwaitScan AvailPlan awaitScan availPlan allowanceOf staggered wakeUpTo! availWakeSpent! deadAwait? startupProblemsFor stopPath requestStop! restartPath draining? requestRestart! restartUntil! flyingIds! restart! loopOnce! runLoop! gatesStage
      stallProbes stallHooks reapLeases! leaseDead? holderPid laneDeadRows skipDead rememberDeadLanes! laneDeadPath laneDeadLive laneCause tickBeat! tickBeatPath stopOf modelEscalatedSig modelEscalatedSig? writeFailSig parkModelEscalated! starvedOut? starvedRows starvedCap trimSlashes conductorLeaseSig? conductorStallSig? ladderHopSig? ladderHop! blockedStageIn impossibleWhy! impossibleRecheck! baseHead! impossibleSig? handoffBranches gateFiles retryBlocked! ladderHop! transientWhy! blockedRetryMax retryBackoffS claimFreed? retryLast! retriesPath stallRequeue! requeuePath requestRequeue! requeueDrain! depWake! wrRowOf wrCfg wrErrors wrMinFreeMb admitWriter? warmWait! writerHeld? firstCallSeen? warmPath
      main]
  :i [(asl-tools/coord/leadStream :a ls) (asl-tools/coord/store :a st) (asl-gates/auditLanded :a al) (asl-tools/coord/grade :a gr) (asl-tools/coord/planImport :a pi) (asl-tools/coord/brief :a bf) (asl-tools/coord/worktree :a w) (asl-tools/coord/sched :a sc) (asl-tools/coord/stall :a stl) (asl-tools/fleet/run :a fr) (asl-tools/fleet/jobserver :a js) (tools/fleet/freePool :a fp) (tools/fleet/leonClient :a lc) (asl-tools/hub/preflight :a hp)
      (asl-parser/lexer :a lx) (asl-parser/ast :a ast) (asl-tools/coord/reviewStage :a rs) (asl-tools/coord/ladder :a l) (asl-tools/coord/gateGuard :a gg) (asl-syntax/asl/asn :a asn) (asl-tools/coord/mergeCheck :a mc) (aslGateway/subPace :a sp) (aslGateway/localTime :a lt) (aslGateway/usageLedger :a ul) (aslGateway/subsRefresh :a sr)])

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
  (:f launch (fn [String st/Task CUnit] -> (List String))) (:f pace Pace) (:f hold Bool :default false))

(schema RealCfg
  (:f repo String) (:f devRepo String) (:f devBranch String) (:f wt w/Cfg) (:f home String) (:f keys String) (:f leaseSec Int64) (:f gateSec Int64) (:f lanes String) (:f writerAlias String) (:f profile String) (:f attractorAb Bool) (:f leonPool String :default "") (:f writerModel String :default "") (:f laneTtlSec Int64 :default 3600) (:f mergeCheckSec Int64 :default 1200))

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

; (:m :ref REVIEW-DEFER :do "the unit row's :model is the writer's: only the write stage sets it; a review stored its reviewer list there and the next review excluded those families as the writer's, parking AGY-MODEL-IDS-55 on a paid lane out of allowance")
fn ! moveA! ctx: Ctx c: CUnit to: String stage: String model: String alias: String tokens: Int64 cost: Int64 verdict: String ms: Int64 -> CUnit
  (let [(next (with c :launched 0 :st to :tokens (+ c.tokens tokens) :costMicro (+ c.costMicro (max 0 cost)) :model (if (or (stringEmpty? model) (!= stage "write")) c.model model)
                    :sig (if (and (= to "blocked") (stringEmpty? c.sig)) (blockSig stage verdict) c.sig)))
        (_ (journalA! ctx c to stage model alias tokens cost verdict ms))
        (_ (writeCUnit! ctx.dir next))]
    next)

; (:m :ref SERVED-ALIAS-JOURNAL :do "the model a write is journalled under comes from Leon's receipt: :servedAlias A, else :servedModel M, else the older literal :model tag (modelOf, unknown when absent); the alias alone is also journalled as :alias; review's writer exclusion (reviewWriter) reads the unit's model, so it sees the served alias and never an unknown family when the receipt named one")
; (:m :ref SERVED-ALIAS-JOURNAL :do "receiptRowOf is the last line of the output that starts with (: and carries :usage, Leon's final receipt row; servedField parses that one row as an ASN form and reads the key from it, so an echoed line earlier in the output never decides")
fn receiptRowOf out: String -> String
  (optionOr (listLast (filter (fn [(l String)] -> Bool (and (stringStartsWith? l "(:") (stringContains? l ":usage")))
                              (map stringTrim (stringLines out)))) "")

; (:m :ref REVIEW-DEFER :do "Leon's output wraps the receipt as (:agent :receipt (:agentReceipt ... :servedAlias A ...)), so the served keys sit one form down; nestedReceipt is the balanced (:agentReceipt ...) text of a row, empty when none, string literals skipped")
fn formEnd s: String i: Int64 depth: Int64 inStr: Bool esc: Bool -> Int64
  (if (>= i (stringLength s))
    (stringLength s)
    (let [(c (optionOr (stringSlice s i (+ i 1)) ""))]
      (cond
        (esc (formEnd s (+ i 1) depth inStr false))
        ((and inStr (= c "\\")) (formEnd s (+ i 1) depth inStr true))
        ((= c "\"") (formEnd s (+ i 1) depth (not inStr) false))
        (inStr (formEnd s (+ i 1) depth inStr false))
        ((= c "(") (formEnd s (+ i 1) (+ depth 1) inStr false))
        ((= c ")") (if (<= depth 1) (+ i 1) (formEnd s (+ i 1) (- depth 1) inStr false)))
        (else (formEnd s (+ i 1) depth inStr false)))))

fn nestedReceipt row: String -> String
  (match (stringIndexOf row "(:agentReceipt ")
    ((none) "")
    ((some at) (optionOr (stringSlice row at (formEnd row at 0 false false)) "")))

fn servedField out: String key: String -> String
  (let [(k (if (stringStartsWith? key ":") (optionOr (stringSlice key 1 (stringLength key)) key) key))
        (row (receiptRowOf out))
        (top (al/rowText row k))]
    (if (stringEmpty? top) (al/rowText (nestedReceipt row) k) top))

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
            (_ (if live (onBaseHeal! ctx.dir path (match (st/readUnits! ctx.dir) ((ok us) (match (listFind (fn [(u st/Task)] -> Bool (= u.id id)) us) ((some u) (baseRef (resolved! repo u))) ((none) "main"))) ((err _) "main")) id) false))
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

; (:m :ref JOURNAL-UTF8-CUT :do "stringSlice and stringLength count bytes, so a cut at a fixed byte offset can split a multibyte character and leave invalid UTF-8 in a journal row (grep then calls journal.asn binary); utf8Clip backs the cut off to the start of the character it would split")
fn utf8Back bs: Bytes j: Int64 -> Int64
  (if (and (> j 0) (let [(b (bytesGet bs j))] (and (>= b 128) (< b 192)))) (utf8Back bs (- j 1)) j)

fn utf8Clip t: String limit: Int64 -> String
  (let [(bs (stringToBytes t))]
    (if (<= (bytesLength bs) limit) t (optionOr (stringSlice t 0 (utf8Back bs (max 0 limit))) "")))

fn spawnFailedSig stderr: String -> String
  (str "spawnFailed " (utf8Clip stderr 120))

fn verdictSig sig: String -> String
  (utf8Clip (stringTrim (stringJoin (stringSplit sig "\n") " ")) 400)

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
        (_ (if (and (= stage "review") (< fails limit)) (priorWrite! ctx.dir c.id c.lane sig) ()))
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

; (:m :ref RES-GUARD-M1 :do "while the disk level in slots.asn is stop (ctx.hold, set by step! from sc/levelRead!) no gate and no review starts; plain slot saturation does not hold, because ready claims earlier in store order would take every freed slot and starve gates and reviews: the unit stays gating or reviewing with launched 0 and a later tick starts it; a running stage is untouched")
fn ! launch! ctx: Ctx u: st/Task c: CUnit -> CUnit
  (if (or (draining? ctx.dir) (or (and ctx.hold (listContains? (list "gating" "reviewing") c.st)) (and (= c.st "merging") (mergeBusy? ctx.dir c.id)))) (let [(c0 (with c :launched 0)) (_ (writeCUnit! ctx.dir c0))] c0)
  (let [(stage (stageName c.st))
        (mk ctx.launch)
        (argv (mk stage u c))
        (_ (dirCreate (runsDir ctx.dir)))
        (_ (dropRun! ctx.dir c.id stage))]
    (match (fr/spawnSep argv "." (fr/childEnv (list)))
      ((err po) (fail! ctx c stage "" (spawnFailedSig po.stderr) 0))
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
; (:m :ref COND-RECOVER-C1 :do "a grade commit the store recorded under another sha is still the conductors own: a rebase rewrites every sha and sets the committer to the rebasing identity (t@example.invalid on node2), so neither sha nor committer identifies it; the guard is the content: the commit adds only ledger rows the store recorded and drops none, so a writer cannot add a row the conductor never wrote")
fn ! rebasedGradeCommit? dir: String path: String sha: String -> Bool
  (let [(diff (gitOut path (list "show" "--format=" "-U0" sha "--" (al/ledgerPath))))
        (recorded (readOr (gradeCommitsPath dir)))
        (lines (stringLines diff.out))
        (added (filter (fn [(l String)] -> Bool (and (stringStartsWith? l "+") (not (stringStartsWith? l "+++")))) lines))
        (dropped (filter (fn [(l String)] -> Bool (and (stringStartsWith? l "-") (not (stringStartsWith? l "---")))) lines))]
    (and (= diff.exit 0)
      (and (and (not (listEmpty? added)) (listEmpty? dropped))
        (listAll? (fn [(l String)] -> Bool (stringContains? recorded (str ":row " (st/q (optionOr (stringSlice l 1 (stringLength l)) "")) ")"))) added))))

fn ! ledgerState! dir: String path: String base: String -> String
  (if (stringEmpty? path) ""
    (let [(r (gitOut path (list "log" "--format=%H" (str base "..HEAD") "--" (al/ledgerPath))))]
      (cond
        ((!= r.exit 0) (str "ERR_REPO_GIT: git log in " path " exit " (n r.exit) ": " (repoClip r.out)))
        ((listAny? (fn [(l String)] -> Bool (and (not (stringEmpty? (stringTrim l))) (and (not (gradeCommitRecorded? dir (stringTrim l))) (not (rebasedGradeCommit? dir path (stringTrim l)))))) (stringLines r.out)) "forged")
        (else ""))))

fn repoClip text: String -> String
  (let [(t (stringTrim text))] (utf8Clip t 160))

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

; (:m :ref COND-RECOVER-C3 :do "a review that could not be shown the change (gone worktree, failed git diff) is a transient, not a review failure: the unit goes to ready with stage requeue and verdict reviewDiffUnreadable, its fail count and ladder lane untouched, so no rung is spent and reviewFailedSinceWriter? stays false; settleWt! then re-attaches sh/UNIT and the ahead check sends it to gating; each requeue is one retries.asn row and past :blockedRetryMax the unit blocks with the unreadable signature")
fn ! requeueUnreadable! ctx: Ctx c: CUnit res: Res -> Unit
  (let [(r (retryLastBy! ctx.dir c.id true))
        (_ (dropLease! ctx c))]
    (if (>= (pairFirst r) (blockedRetryMax ctx.dir))
      (let [(c1 (escalate! ctx (with c :sig res.sig :epoch 0) res.sig (str "review diff unreadable " (n (+ (pairFirst r) 1)) "x")))
            (_ (move! ctx c1 "blocked" "review" "" 0 0 (str "escalated: " (verdictSig res.sig)) res.ms))]
        ())
      (let [(_ (retryNote! ctx.dir c.id "reviewDiff" (+ (pairFirst r) 1)))
            (_ (move! ctx (noEpoch c) "ready" "requeue" "" 0 0 "reviewDiffUnreadable" res.ms))]
        ())))

; (:m :ref COND-MODEL-ESCALATE :do "a model escalation parks the unit at once, no ladder hop and no retry: its tree is rescued as a wip commit, the lease dropped, one (:escalate :unit :seen :tried) row carries the model's reason in escalations.asn, the unit blocks with the signature modelEscalated: REASON, and one act-severity event of kind modelEscalated goes to the lead stream (the stream never blocks a writer: a failed emit changes nothing)")
fn ! parkModelEscalated! ctx: Ctx c: CUnit res: Res -> Unit
  (let [(_ (wipSave! ctx c.id "modelEscalated"))
        (_ (dropLease! ctx c))
        (c1 (escalate! ctx (with c :sig res.sig :epoch 0) res.sig "the model asked for help: no ladder rung answers a model escalation"))
        (_ (ls/emitAt! (dirOf ctx.dir) (nowMs) "conductor" "act" "modelEscalated" c.id c.id res.sig))
        (_ (move! ctx c1 "blocked" "write" res.model 0 0 (str "escalated: " (verdictSig res.sig)) res.ms))]
    ())

; (:m :ref CONDWIRE-A :do "the last-rung defer for absent reviewers is bounded: the ladder journals one await row marked quorumStarved per defer; when the newest await row of the unit is such a row and the unit has had more than starvedCap of them, the next one parks the unit blocked instead, with the tiebreak reason and reviewQuorumStarved in the sig, and one warn event on the lead stream; the count is per unit lifetime and adopted at 3")
fn starvedCap -> Int64
  3

fn starvedRows dir: String id: String -> (List String)
  (filter (fn [(l String)] -> Bool (and (stringContains? l ":why \"quorumStarved:") (or (stringStartsWith? l (str "(:await :unit " id " ")) (stringStartsWith? l (str "(:await :unit " (st/q id) " ")))))
          (journalLinesOf dir))

fn starvedOut? dir: String id: String -> Bool
  (let [(rows (starvedRows dir id))
        (newest (optionOr (listLast (filter (fn [(l String)] -> Bool (or (stringStartsWith? l (str "(:await :unit " id " ")) (stringStartsWith? l (str "(:await :unit " (st/q id) " ")))) (journalLinesOf dir))) ""))]
    (and (stringContains? newest ":why \"quorumStarved:") (> (listLength rows) (starvedCap))))

fn ! starvedPark! ctx: Ctx c: CUnit res: Res -> Unit
  (let [(row (optionOr (listLast (starvedRows ctx.dir c.id)) ""))
        (sig (str "tiebreak: reviewers split at the last rung (pass " (sp/tokAfter row "(pass") " fail 0); reviewQuorumStarved"))
        (c2 (escalateTiered! ctx c sig "review blocked" res.tiers))
        (_ (dropLease! ctx c2))
        (_ (ls/emitAt! (dirOf ctx.dir) (nowMs) "conductor" "warn" "reviewQuorumStarved" c.id c.id sig))
        (_ (move! ctx (noEpoch c2) "blocked" "review" res.model res.tokens res.costMicro sig res.ms))]
    ())

; (:m :do "applies one finished stage result to its unit; the writer's claimedGreen is only journalled")
fn ! finish! ctx: Ctx u0: st/Task c: CUnit res0: Res -> Unit
  (let [(u (resolved! (stringTrim (readOr (repoPath ctx.dir))) u0))
        (res (ledgerGuard ctx.dir u c res0))
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
          (if (modelEscalatedSig? res.sig)
            (let [(_ (parkModelEscalated! ctx c res))] ())
          (if (vacuousSig? res.sig)
            (let [(_ (wipSave! ctx c.id "vacuousGate"))
                  (_ (dropLease! ctx c))
                  (c1 (escalate! ctx (with c :sig res.sig :epoch 0) res.sig "write: the unit gate passes on the base before any edit, so no write can prove it; make the gate fail on the base or mark the task a regression guard"))
                  (_ (move! ctx c1 "blocked" "write" res.model 0 0 (str "escalated: " (verdictSig res.sig)) res.ms))]
              ())
            (let [(_ (fail! ctx c "write" res.model res.sig res.ms))] ()))))))))
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
          ((= res.verdict "defer")
            (if (starvedOut? ctx.dir c.id)
              (starvedPark! ctx c res)
              (let [(_ (move! ctx (awaiting c res.sig) "awaitReview" "review" res.model res.tokens res.costMicro "defer" res.ms))] ())))
          ((= res.verdict "block")
            (let [(c2 (escalateTiered! ctx c res.sig "review blocked" res.tiers))
                  (_ (dropLease! ctx c2))
                  (_ (move! ctx (noEpoch c2) "blocked" "review" res.model res.tokens res.costMicro "block" res.ms))]
              ()))
          ((= res.verdict "requeue") (let [(_ (requeueUnreadable! ctx c res))] ()))
          (else (let [(_ (fail! ctx c "review" res.model res.sig res.ms))] ()))))
      ((= c.st "merging")
        (cond
          ; (:m :ref CONDUCTOR-MERGE-CHECK :do "mergeCheck verdicts park the unit without a failure count or a retry: block is blocked with the check rows, hold is blocked await mergeHold for the lead")
          ((or (= res.verdict "block") (= res.verdict "hold"))
            (let [(_ (dropLease! ctx c))
                  (_ (move! ctx (with (noEpoch c) :sig res.sig :await (if (= res.verdict "hold") "mergeHold" "")) "blocked" "merge" "" 0 0 (str "mergeCheck " res.verdict) res.ms))]
              ()))
          (else
        (if (= res.ok 1)
          (match (st/commit! ctx.dir c.id c.epoch c.branch)
            ((ok _) (let [(_ (move! ctx (noEpoch c) "merged" "merge" "" 0 0 "merged" res.ms))] ()))
            ((err e) (let [(_ (mergeFail! ctx u c e res.ms))] ())))
          (let [(_ (mergeFail! ctx u c res.sig res.ms))] ())))))
      (else ())))

; (:m :do "returns the in-flight capacity left for the rest of this tick")
fn ! step! ctx0: Ctx u: st/Task cap: Int64 -> Int64
  (let [(ctx (with ctx0 :hold (or ctx0.hold (= (sc/levelRead! ctx0.dir) "stop"))))
        (cus (readCUnits! ctx.dir))
        (c (optionOr (cuOf cus u.id) (newCUnit u)))
        (held (and (none? (cuOf cus u.id)) (or (fileExists? (cuPath ctx.dir u.id)) (listContains? (quarantinedIds ctx.dir) u.id))))]
    (cond
      (held cap)
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
            (let [(why (impossibleWhy! ctx u))]
              (if (not (stringEmpty? why))
                (let [(_ (refuseImpossible! ctx u c why))] cap)
                (match (st/claim! ctx.dir c.id ctx.holder ctx.ttlMs)
                  ((err e) (let [(_ (waitMore! ctx c e))] cap))
                  ((ok text)
                    (let [(epoch (match (st/parseLease text) ((ok l) l.epoch) ((err _) 0)))
                          (c1 (move! ctx (admitted c epoch) "writing" "claim" "" 0 0 "admitted" 0))
                          (_ (launch! ctx u c1))]
                      (- cap 1)))))))))
      ((= c.st "awaitReview")
        (if (or (= c.parked 1) (or ctx.hold (draining? ctx.dir))) cap
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
; (:m :ref REVIEW-DEFER :do "a write stage still in the ahead check runs the unit gate and asl check, often longer than stalledMin with no writer journal and no file write, and was killed as stalled before it could write its (:ahead) row (node2 CHILDENV-STRIP-MORE, CMDTEST-STALE-CLEAN, twice each); while runs/UNIT-ahead.run exists the unit is not probed, the stage deadline still bounds it")
; (:m :ref REVIEW-DEFER :do "a unit counts as in its ahead check while runs/UNIT-ahead.run says so and its :untilMs (start plus twice the gate bound) is still ahead; a marker a killed stage left behind is ignored after that")
fn ! aheadMarked? dir: String id: String now: Int64 -> Bool
  (> (optionOr (stringToInt64 (stringTrim (sp/tokAfter (readOr (runPath dir id "ahead" "run")) ":untilMs"))) 0) now)

fn ! stallProbes ctx: Ctx -> (List stl/Probe)
  (let [(repo (stringTrim (readOr (repoPath ctx.dir))))]
    (map (fn [(c CUnit)] -> stl/Probe
           (stl/Probe :id c.id :lane c.lane :wt (str (wtBase ctx.dir repo) "/asex-" c.id)
                      :alive (match (runRow ctx.dir c.id "write") ((some r) (alive? (pairFirst r))) ((none) false))
                      :sinceMs (stl/statMs (runPath ctx.dir c.id "write" "run"))))
         (filter (fn [(c CUnit)] -> Bool (and (= c.st "writing") (and (!= c.launched 0) (and (not (fileExists? (runPath ctx.dir c.id "write" "asn"))) (not (aheadMarked? ctx.dir c.id (nowMs))))))) (readCUnits! ctx.dir))))

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

; (:m :ref NODEWATCH-IDLE-RESTART :do "every tick, idle or not, rewrites <store>/tick.asn atomically (temp file, then rename) with the time and pid; nodeWatch judges the conductor stale only by this file's age, since an idle conductor writes no journal row")
fn tickBeatPath dir: String -> String
  (str dir "/tick.asn")

fn ! tickBeat! dir: String -> Bool
  (let [(tmp (str (tickBeatPath dir) "." (n (procSelf)) ".tmp"))]
    (match (fileWrite tmp (str "(:tick :at " (n (nowMs)) " :pid " (n (procSelf)) ")\n"))
      ((err _) false)
      ((ok _) (match (pathRename tmp (tickBeatPath dir)) ((ok _) true) ((err _) false)))))

; (:m :ref COND-TICK-READS :do "a store that cannot be read is an error, not an empty store: the unit rows count as unreadable when their directory exists and listing or parsing it fails (a directory that does not exist yet is an empty store)")
fn ! storeReadError! dir: String -> (Option String)
  (if (not (fileExists? (st/unitsDir dir))) (none)
    (match (st/readUnits! dir) ((err e) (some e)) ((ok _) (none))))

; (:m :ref COND-TICK-READS :do "a conductor state row that exists but does not parse is moved with its bytes to <store>/cond/quarantine/ID.TS and its unit stays out of scheduling while any such file is there: step! no longer recreates it as a fresh queued row, which lost the unit's state silently; an operator restores the row (or removes the quarantine file) to release it")
fn quarantineDir dir: String -> String
  (str (cuDir dir) "/quarantine")

fn quarantineIdOf name: String -> String
  (let [(parts (stringSplit name "."))]
    (stringJoin (listTake parts (max 1 (- (listLength parts) 1))) "."))

fn ! quarantinedIds dir: String -> (List String)
  (match (dirList (quarantineDir dir))
    ((err _) (list))
    ((ok names)
      (fold (fn [(acc (List String)) (name String)] -> (List String)
              (if (= name "released") acc
                (let [(id (quarantineIdOf name))]
                  (if (listContains? acc id) acc (listAppend acc (list id))))))
            (list) (listSort names))))

; (:m :ref COND-TICK-READS :do "only a row read successfully as bytes that fails to parse is quarantined; a list or read error is surfaced and retried, never a move; the name is ID.nowMs-pid so two quarantines of one id never collide")
fn ! quarantineRow! dir: String id: String -> Bool
  (let [(_ (dirCreate (quarantineDir dir)))]
    (ok? (pathRename (cuPath dir id) (str (quarantineDir dir) "/" id "." (n (nowMs)) "-" (n (procSelf))))))

; (:m :ref COND-TICK-READS :do "a quarantined unit is released once a parsing row is back at cond/ID.asn: its quarantine files move to quarantine/released/ and the unit schedules again")
fn ! releaseQuarantined! dir: String -> Int64
  (match (dirList (quarantineDir dir))
    ((err _) 0)
    ((ok names)
      (let [(good (filter (fn [(id String)] -> Bool (match (fileReadString (cuPath dir id)) ((err _) false) ((ok raw) (match (parseCUnit raw) ((ok _) true) ((err _) false))))) (quarantinedIds dir)))
            (mine (filter (fn [(name String)] -> Bool (and (!= name "released") (listContains? good (quarantineIdOf name)))) names))
            (_ (if (listEmpty? mine) false (ok? (dirCreate (str (quarantineDir dir) "/released")))))
            (_ (map (fn [(name String)] -> Bool (ok? (pathRename (str (quarantineDir dir) "/" name) (str (quarantineDir dir) "/released/" name)))) mine))]
        (listLength mine))))

; (:m :ref COND-TICK-READS :do "every tick raises one lead-stream warn per unreadable conductor state row (kind cuUnreadable, key the unit) and one for an unreadable store (kind storeUnreadable); the stream dedupes repeats, so a corrupt row is one row with a count, not a silent drop")
fn ! surfaceReads! ctx: Ctx -> Int64
  (let [(now (nowMs))
        (_ (map (fn [(id String)] -> Bool (quarantineRow! ctx.dir id)) (unparseableIds! ctx.dir)))
        (_ (releaseQuarantined! ctx.dir))
        (ids (quarantinedIds ctx.dir))
        (_ (map (fn [(id String)] -> Bool (ls/emitAt! (dirOf ctx.dir) now "conductor" "warn" "cuUnreadable" id id (str "conductor state row unparseable: bytes kept in " (quarantineDir ctx.dir) "/" id ".*, the unit is out of scheduling; release: cp or mv a good row back to " (cuPath ctx.dir id) ", the next tick moves the quarantine file to " (quarantineDir ctx.dir) "/released"))) ids))
        (bad (storeReadError! ctx.dir))
        (_ (match bad ((some e) (ls/emitAt! (dirOf ctx.dir) now "conductor" "warn" "storeUnreadable" "store" "" (str "store rows unreadable: " e))) ((none) true)))]
    (+ (listLength ids) (match bad ((some _) 1) ((none) 0))))

fn ! tick! ctx: Ctx -> (Result Int64 String)
  (let [(_ (tickBeat! ctx.dir))
        (_ (surfaceReads! ctx))]
    (if (repoGate! ctx) (tickRepo! ctx) (ok 0)))

fn ! tickRepo! ctx: Ctx -> (Result Int64 String)
  (match (st/readUnits! ctx.dir)
    ((err e) (err e))
    ((ok units)
      (let [(_ (requeueDrain! ctx units))
            (_ (reapLeases! ctx))
            (_ (retryBlocked! ctx units))
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
    (and (none? (storeReadError! ctx.dir))
         (and (= (listLength cus) (listLength stored))
         (listAll? (fn [(c CUnit)] -> Bool (or (listContains? (list "merged" "blocked" "failed") c.st) (and (= c.st "awaitReview") (= c.parked 1)))) cus))))

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
  (wakeUpTo! ctx lane (- 0 1))

; (:m :ref WAKE-LOWS :do "wake LANE for at most cap units in id order, a negative cap meaning all: refreshWake! passes the lane's allowance so a reset does not send the whole herd to one lane in one tick")
fn ! wakeUpTo! ctx: Ctx lane: String cap: Int64 -> Int64
  (let [(all (filter (fn [(c CUnit)] -> Bool (and (= c.st "awaitReview") (and (= c.parked 1) (or (= c.lane lane) (listContains? (stringSplit c.await " ") lane))))) (readCUnits! ctx.dir)))
        (cus (if (< cap 0) all (listTake all cap)))
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
                  (parked (filter (fn [(c CUnit)] -> Bool (and (= c.st "awaitReview") (and (= c.parked 1) (listContains? (stringSplit c.await " ") name)))) (readCUnits! ctx.dir)))
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

; (:m :ref COND-RECOVER-C2 :do "the pid in a holder name conductorPID, 0 for any other holder (a test, a hand claim), which then lives or dies by its beat alone")
fn holderPid holder: String -> Int64
  (if (stringStartsWith? holder "conductor") (optionOr (stringToInt64 (optionOr (stringSlice holder 9 (stringLength holder)) "")) 0) 0)

; (:m :ref COND-RECOVER-C2 :do "a lease is dead when another holder owns it and either its beat is older than its ttl or its holder process is gone, and no in-flight stage of this store still runs on it: a restarted conductor adopts the stage rows of the old one through heartbeat, which this must not undo (node2 2026-11-04: conductor1177356 died holding 38 leases, 32 units refused behind them, nothing freed them for the ttl hour)")
fn ! leaseDead? ctx: Ctx cus: (List CUnit) l: st/Lease now: Int64 -> Bool
  (and (!= l.holder ctx.holder)
       (and (not (listAny? (fn [(c CUnit)] -> Bool (and (= c.id l.id) (and (active? c) (= c.epoch l.epoch)))) cus))
            (or (not (st/live? l now))
                (let [(pid (holderPid l.holder))] (and (> pid 0) (not (alive? pid)))))))

; (:m :ref COND-RECOVER-C2 :do "the lease reaper: every dead lease is released through the stores fenced release (unit back to queued, lease file removed, one log row) and journalled as a leaseReaped row naming unit, holder, epoch and cause; returns the units freed")
fn ! reapLeases! ctx: Ctx -> (List String)
  (match (st/readLeases! ctx.dir)
    ((err _) (list))
    ((ok leases)
      (let [(now (nowNs))
            (cus (readCUnits! ctx.dir))
            (dead (filter (fn [(l st/Lease)] -> Bool (leaseDead? ctx cus l now)) leases))
            (freed (filter (fn [(l st/Lease)] -> Bool
                             (match (st/release! ctx.dir l.id l.epoch)
                               ((ok _) (let [(_ (fileAppend (journalPath ctx.dir) (str "(:leaseReaped :unit " (st/q l.id) " :holder " (st/q l.holder) " :epoch " (n l.epoch) " :why " (st/q (if (st/live? l now) "holderGone" "expired")) " :at " (n (nowMs)) ")\n")))] true))
                               ((err _) false)))
                           dead))]
        (map (fn [(l st/Lease)] -> String l.id) freed))))

; (:m :ref COND-RECOVER-C2 :do "<store>/retries.asn keeps (:retry :unit ID :n N :at MS) rows, the newest per unit wins: N automatic retries a blocked unit has had, MS the last one")
fn retriesPath dir: String -> String
  (str dir "/retries.asn")

; (:m :ref UNREADABLE-RETRY-SHARED-CAP :do "retries.asn rows count per cause: a reviewDiff row (unreadable review requeue) and a blocked-retry row of the same unit never share a count, each cause has its own cap per unit lifetime")
fn ! retryLastBy! dir: String id: String review: Bool -> (Pair Int64 Int64)
  (let [(hits (fold (fn [(acc (List (Pair Int64 Int64))) (l String)] -> (List (Pair Int64 Int64))
                      (match (st/rowFields l "retry")
                        ((err _) acc)
                        ((ok fs) (if (and (= (st/textField fs "unit") id) (= review (= (st/textField fs "why") "reviewDiff")))
                                   (listAppend acc (list (pair (st/intField fs "n") (st/intField fs "at"))))
                                   acc))))
                    (list) (stringLines (readOr (retriesPath dir)))))]
    (match (listLast hits) ((none) (pair 0 0)) ((some p) p)))

fn ! retryLast! dir: String id: String -> (Pair Int64 Int64)
  (retryLastBy! dir id false)

fn ! retryNote! dir: String id: String why: String count: Int64 -> Bool
  (ok? (fileAppend (retriesPath dir) (str "(:retry :unit " (st/q id) " :why " (st/q why) " :n " (n count) " :at " (n (nowMs)) ")\n")))

; (:m :ref COND-RECOVER-C2 :do "a unit blocked waitedOut on a claim refusal (held by a lease, or its :owns clashing with another unit's lease) whose blocker no longer holds a live lease goes back to ready once: the blocker was a dead holder's lease the reaper freed, and nothing else ever woke it (32 units on node2 behind conductor1177356)")
fn claimFreed? c: CUnit leases: (List st/Lease) now: Int64 -> Bool
  (and (stringStartsWith? c.sig "waitedOut: (:refused ")
       (let [(live (filter (fn [(l st/Lease)] -> Bool (st/live? l now)) leases))
             (liveHas (fn [(id String)] -> Bool (listAny? (fn [(l st/Lease)] -> Bool (= l.id id)) live)))]
         (cond
           ((stringContains? c.sig " :why held ") (not (liveHas c.id)))
           ((stringContains? c.sig " :why owns ") (let [(by (quotedAfter c.sig ":by \""))] (and (not (stringEmpty? by)) (not (liveHas by)))))
           (else false))))

; (:m :ref COND-RECOVER-C3 :do "config of the blocked-unit retry policy, in the (:conductor ...) row of the stores ladder.asn: :blockedRetryMax N automatic retries a blocked unit gets per transient cause (default 2 adopted, 0 turns the policy off), :retryBackoffS S the wait before the first retry, doubled for each later one (default 300 adopted)")
fn ! blockedRetryMax dir: String -> Int64
  (let [(row (cdRowOf dir))]
    (if (listEmpty? (cdErrors row)) (optionOr (stringToInt64 (sp/tokAfter row ":blockedRetryMax")) 2) 2))

fn ! retryBackoffS dir: String -> Int64
  (let [(row (cdRowOf dir))]
    (if (listEmpty? (cdErrors row)) (optionOr (stringToInt64 (sp/tokAfter row ":retryBackoffS")) 300) 300))

; (:m :ref COND-RECOVER-C3 :do "the conductors own signatures of a lost lease (leaseLost, stage run row lost, lease ended before) and of a stalled writer (stalled), matched as sig prefixes, never as substrings: a gate failure naming leaseTest or a stalled word is a writer failure")
fn conductorLeaseSig? sig: String -> Bool
  (listAny? (fn [(p String)] -> Bool (stringStartsWith? sig p)) (list "leaseLost" "stage run row lost" "lease ended before"))

fn conductorStallSig? sig: String -> Bool
  (or (= sig "stalled") (stringStartsWith? sig "stalled: "))

; (:m :ref COND-RECOVER-C3 :do "why a blocked unit may be retried by itself, empty when it may not, a cap per unit lifetime (retries.asn is never reset): claim (the lease or owns clash that refused it is gone), provider (the failure signature matches the providerFail patterns), lease and stall (the conductors own signatures), vacuous (the vacuous verdict with commits on the unit branch past its base, which gating can now test); every other block, a review block, a stale rebase, deps, a repeated writer failure, waits for a person or the ladder")
fn ! transientWhy! ctx: Ctx u: st/Task c: CUnit leases: (List st/Lease) now: Int64 -> String
  (let [(low (stringLower c.sig))]
    (cond
      ((impossibleSig? c.sig) "")
      ((claimFreed? c leases now) "claim")
      ((stringEmpty? c.sig) "")
      ((providerFailSig? c.sig (pfPatterns (pfRowOf ctx.dir))) "provider")
      ((conductorLeaseSig? c.sig) "lease")
      ((conductorStallSig? c.sig) "stall")
      ((vacuousSig? c.sig)
        (let [(repo (stringTrim (readOr (repoPath ctx.dir))))
              (p (str (wtBase ctx.dir repo) "/asex-" c.id))]
          (if (and (not (stringEmpty? repo)) (and (worktreeValid? p) (commitsPast? p (baseRef (resolved! repo u))))) "vacuous" "")))
      (else "")))

; (:m :ref COND-RECOVER-C3 :do "an escalated writer failure whose next ladder rung has room again (the per-day cap of a rung rolled over, a rung row was raised) hops there as the failed write would have, one tierHop move to ready with a clean count; the lead rung is left to offerBacklog!; the review block that offerStrong! serves, a stale rebase, deps and the vacuous verdict are not writer failures")
; (:m :ref COND-RECOVER-C3 :do "only a writer failure hops a rung (the journal is read once per tick by retryBlocked! and passed in): the unit blocked at stage write through fail! and its signature is not one of the conductors own non-writer failures (LEDGER_FORGED, ERR_REPO_GIT, worktree attach, stage run row lost, stale branch, merge or train failures, impossible, vacuous, waitedOut, review, STALE)")
fn blockedStageIn lines: (List String) id: String -> String
  (sp/tokAfter (optionOr (listLast (filter (fn [(x String)] -> Bool (and (stringStartsWith? x (str "(:t :unit " (st/q id) " ")) (stringContains? x " :to blocked "))) lines)) "") ":stage")

fn ladderHopSig? sig: String -> Bool
  (not (or (stringEmpty? sig)
        (listAny? (fn [(p String)] -> Bool (stringStartsWith? sig p))
                  (list "waitedOut: " "review" "impossible: " "vacuousGate" "STALE" "LEDGER_FORGED" "ERR_REPO_GIT" "worktree attach" "stage run row lost" "leaseLost" "merge" "train"))))

fn ! ladderHop! ctx: Ctx c: CUnit now: Int64 jr: (List String) -> Bool
  (if (and (and (= c.st "blocked") (stringEmpty? c.await)) (and (= c.esc 1) (and (listContains? (list "free" "paid" "strong") c.lane) (and (ladderHopSig? c.sig) (= (blockedStageIn jr c.id) "write")))))
    (match (nextRung! ctx.dir c.lane now)
      ((none) false)
      ((some next)
        (if (= next "lead") false
          (let [(_ (priorWrite! ctx.dir c.id c.lane c.sig))
                (_ (move! ctx (with c :lane next :fails 0 :waited 0 :esc 0 :epoch 0 :sig "") "ready" "retry" "" 0 0 (str "tierHop " c.lane "->" next ": " (verdictSig c.sig)) 0))]
            true))))
    false)

; (:m :ref COND-RECOVER-C3 :do "the blocked-unit policy, once per tick: a blocked unit with a transient cause (transientWhy!) goes back to ready with a clean count while it has had fewer than :blockedRetryMax retries and the backoff since its last one (:retryBackoffS doubled per retry) has passed, each retry one row in retries.asn; a unit with no transient cause gets ladderHop!; on node2 2026-11-04 129 of 172 units sat blocked with only dep, lead-backlog, strong-offer and stale wakes to leave by")
fn ! retryOne! ctx: Ctx u: st/Task c: CUnit leases: (List st/Lease) now: Int64 max: Int64 backoffMs: Int64 jr: (List String) -> Bool
  (if (not (and (= c.st "blocked") (stringEmpty? c.await))) false
    (let [(why (transientWhy! ctx u c leases now))]
      (if (impossibleSig? c.sig) (impossibleRecheck! ctx u c)
      (if (stringEmpty? why) (ladderHop! ctx c (/ now 1000000) jr)
        (let [(r (retryLast! ctx.dir c.id))
              (wait (* backoffMs (fold (fn [(a Int64) (_ Int64)] -> Int64 (* a 2)) 1 (range 0 (pairFirst r)))))]
          (if (or (>= (pairFirst r) max) (< (- (nowMs) (pairSecond r)) wait)) false
            (let [(_ (retryNote! ctx.dir c.id why (+ (pairFirst r) 1)))
                  (_ (pwReset! ctx.dir c.id))
                  (_ (move! ctx (with c :waited 0 :sig "" :esc 0 :epoch 0 :fails 0) "ready" "retry" "" 0 0 (str "retry " why) 0))]
              true)))))))

fn ! retryBlocked! ctx: Ctx units: (List st/Task) -> Int64
  (match (st/readLeases! ctx.dir)
    ((err _) 0)
    ((ok leases)
      (let [(now (nowNs))
            (jr (journalLinesOf ctx.dir))
            (max (blockedRetryMax ctx.dir))
            (backoffMs (* 1000 (retryBackoffS ctx.dir)))
            (woken (filter (fn [(u st/Task)] -> Bool
                             (match (cuOf (readCUnits! ctx.dir) u.id)
                               ((none) false)
                               ((some c) (retryOne! ctx u c leases now max backoffMs jr))))
                           units))]
        (listLength woken))))

; (:m :ref COND-RECOVER-C4 :do "the branch names a task cites as its handoff, the text after main..sh/ up to the first character a branch name cannot hold")
fn branchChars? ch: String -> Bool
  (let [(k (charCode ch))] (or (and (>= k 48) (<= k 57)) (or (and (>= k 65) (<= k 90)) (or (and (>= k 97) (<= k 122)) (listContains? (list "-" "_" "." "/") ch)))))

fn handoffBranches text: String -> (List String)
  (map (fn [(seg String)] -> String
         (let [(r (fold (fn [(acc (Pair String Bool)) (ch String)] -> (Pair String Bool)
                          (if (pairSecond acc) acc (if (branchChars? ch) (pair (str (pairFirst acc) ch) false) (pair (pairFirst acc) true))))
                        (pair "" false) (stringChars seg)))]
           (let [(name (pairFirst r))] (if (stringEndsWith? name ".") (optionOr (stringSlice name 0 (- (stringLength name) 1)) name) name))))
       (optionOr (listTail (stringSplit text "main..sh/")) (list)))

; (:m :ref COND-RECOVER-C4 :do "the .asl paths a gate command runs")
fn gateFiles gate: String -> (List String)
  (filter (fn [(t String)] -> Bool (and (stringEndsWith? t ".asl") (stringContains? t "/"))) (stringSplit gate " "))

fn trimSlashes p: String -> String
  (if (and (> (stringLength p) 1) (stringEndsWith? p "/")) (trimSlashes (optionOr (stringSlice p 0 (- (stringLength p) 1)) p)) p)

fn dirOf p0: String -> String
  (let [(p (trimSlashes p0))
        (parts (stringSplit p "/"))]
    (stringJoin (listTake parts (max 0 (- (listLength parts) 1))) "/"))

; (:m :ref COND-RECOVER-C4 :do "why a unit can never be written, empty when it can; a refusal needs positive evidence, an unreadable or ambiguous case is admitted: an owned path whose directory is absent on the base but was on its history (removed, as asl/agentLoop was for asl/packages/asl-agent, 17 node2 units) while the task text does not name it, a gate file absent on the base that was on its history and that the unit neither owns, nor sits under an owned directory of, nor names in its task, a handoff branch the task cites (main..sh/NAME) that is merged into the base when the task is only the handoff (GRADE-AND-LAND), or is missing while no commit on the base carries NAME in its message (a cited tip sha that still exists does not admit it); a directory that never existed (a new tests/ under a live package) is the unit's to create")
fn ! impossibleWhy! ctx: Ctx u0: st/Task -> String
  (let [(repo (stringTrim (readOr (repoPath ctx.dir))))]
    (if (stringEmpty? repo) ""
      (let [(u (resolved! repo u0))
            (base (baseRef u))
            (task (taskText ctx.dir u))
            (onBase (fn [(path String)] -> Bool (= (gitOut repo (list "cat-file" "-e" (str base ":" path))).exit 0)))
            (hadOnBase (fn [(path String)] -> Bool (let [(r (gitOut repo (list "log" "-1" "--format=%H" "--diff-filter=D" base "--" path)))] (and (= r.exit 0) (not (stringEmpty? (stringTrim r.out)))))))
            (plain (filter (fn [(p String)] -> Bool (and (not (stringContains? p "*")) (not (stringEndsWith? p "/")))) u.owns))
            (declared (fn [(d String)] -> Bool (or (stringContains? task d) (listAny? (fn [(o String)] -> Bool (and (stringEndsWith? o "/") (stringStartsWith? (str d "/") o))) u.owns))))
            (ownedDirs (listAppend (map dirOf plain) (map (fn [(o String)] -> String (optionOr (stringSlice o 0 (- (stringLength o) 1)) o)) (filter (fn [(o String)] -> Bool (stringEndsWith? o "/")) u.owns))))
            (createsGate (fn [(f String)] -> Bool (or (listContains? u.owns f) (or (stringContains? task f) (listAny? (fn [(d String)] -> Bool (and (not (stringEmpty? d)) (stringStartsWith? f (str d "/")))) ownedDirs)))))
            (badDir (listFind (fn [(p String)] -> Bool (let [(d (dirOf p))] (and (not (stringEmpty? d)) (and (not (onBase d)) (and (not (declared d)) (hadOnBase d)))))) plain))
            (badGate (listFind (fn [(f String)] -> Bool (and (not (onBase f)) (and (not (createsGate f)) (hadOnBase f)))) (gateFiles u.gate)))
            (branches (filter (fn [(b String)] -> Bool (not (stringEmpty? b))) (handoffBranches task)))
            (onMain (fn [(b String)] -> Bool (let [(r (gitOut repo (list "log" "-1" "--format=%H" "--fixed-strings" (str "--grep=" b) base)))] (and (= r.exit 0) (not (stringEmpty? (stringTrim r.out)))))))
            (missing (listFind (fn [(b String)] -> Bool (and (!= (gitOut repo (list "rev-parse" "--verify" "--quiet" (str "refs/heads/sh/" b))).exit 0) (not (onMain b)))) branches))
            (merged (listFind (fn [(b String)] -> Bool (and (stringContains? task "GRADE-AND-LAND") (= (gitOut repo (list "merge-base" "--is-ancestor" (str "refs/heads/sh/" b) base)).exit 0))) branches))]
        (cond
          ((some? badDir) (str "ownsDirMissing " (dirOf (optionOr badDir "")) " on " base))
          ((some? badGate) (str "gateFileMissing " (optionOr badGate "")))
          ((some? missing) (str "handoffBranchMissing sh/" (optionOr missing "")))
          ((some? merged) (str "handoffBranchMerged sh/" (optionOr merged "")))
          (else "")))))

; (:m :ref COND-RECOVER-C4 :do "an impossible block carries the base head it was judged on (impossible: WHY @SHA); impossibleRecheck! re-judges when the base moved, so a restored directory, a fixed gate path or a landed branch releases the unit and a still impossible unit only has its head refreshed")
fn ! baseHead! ctx: Ctx u0: st/Task -> String
  (let [(repo (stringTrim (readOr (repoPath ctx.dir))))]
    (if (stringEmpty? repo) "" (stringTrim (gitOut repo (list "rev-parse" "--short=9" (baseRef (resolved! repo u0)))).out)))

fn ! impossibleSigOf! ctx: Ctx u: st/Task why: String -> String
  (str "impossible: " why " @" (baseHead! ctx u))

; (:m :ref IMPOSSIBLE-REMAP-MOVED :do "git name-status lines of a commit as (old new) pairs of its renames, rename lines being R<score> TAB old TAB new")
fn renamePairs text: String -> (List (Pair String String))
  (map (fn [(parts (List String))] -> (Pair String String) (pair (optionOr (listGet parts 1) "") (optionOr (listGet parts 2) "")))
       (filter (fn [(parts (List String))] -> Bool (and (= (listLength parts) 3) (stringStartsWith? (optionOr (listHead parts) "") "R")))
               (map (fn [(l String)] -> (List String) (stringSplit l "\t")) (stringLines text))))

; (:m :ref IMPOSSIBLE-REMAP-MOVED :do "when an owned directory is gone because a commit renamed its files, the proposal lists each owned path with the path it was renamed to (old=>new), read from the commit that removed the directory; empty when no owned path was renamed")
fn ! ownsRemap! ctx: Ctx u: st/Task why: String -> String
  (let [(repo (stringTrim (readOr (repoPath ctx.dir))))
        (words (stringSplit why " "))]
    (if (or (stringEmpty? repo) (!= (optionOr (listHead words) "") "ownsDirMissing")) ""
      (let [(dir (optionOr (listGet words 1) ""))
            (base (baseRef (resolved! repo u)))
            (gone (stringTrim (gitOut repo (list "log" "-1" "--format=%H" "--diff-filter=D" base "--" dir)).out))]
        (if (stringEmpty? gone) ""
          (let [(pairs (renamePairs (gitOut repo (list "show" "-M" "--name-status" "--format=" gone)).out))
                (hits (filter (fn [(p String)] -> Bool (listAny? (fn [(r (Pair String String))] -> Bool (= (pairFirst r) p)) pairs)) u.owns))]
            (stringJoin (map (fn [(p String)] -> String (str p "=>" (pairSecond (optionOr (listFind (fn [(r (Pair String String))] -> Bool (= (pairFirst r) p)) pairs) (pair p p))))) hits) " "))))))

fn ! refuseImpossible! ctx: Ctx u: st/Task c: CUnit why: String -> Unit
  (let [(sig (impossibleSigOf! ctx u why))
        (c1 (escalate! ctx (with c :sig sig) sig "admission refused the unit before any claim or writer run"))
        (_ (move! ctx c1 "blocked" "admit" "" 0 0 sig 0))
        (remap (ownsRemap! ctx u why))
        (_ (if (stringEmpty? remap) true (ls/emitAt! (dirOf ctx.dir) (nowMs) "conductor" "act" "ownsRemap" u.id u.id (str "owned paths were renamed, not deleted; proposed :owns " remap))))]
    ())

fn ! impossibleRecheck! ctx: Ctx u: st/Task c: CUnit -> Bool
  (let [(head (baseHead! ctx u))]
    (if (or (stringEmpty? head) (stringEndsWith? c.sig (str " @" head))) false
      (let [(why (impossibleWhy! ctx u))]
        (if (stringEmpty? why)
          (let [(_ (move! ctx (with c :waited 0 :sig "" :esc 0 :epoch 0 :fails 0) "ready" "recheck" "" 0 0 "impossibleCleared" 0))] true)
          (let [(_ (writeCUnit! ctx.dir (with c :sig (impossibleSigOf! ctx u why))))] false)))))

fn impossibleSig? sig: String -> Bool
  (stringStartsWith? sig "impossible: ")

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

; (:m :ref COND-TICK-READS :do "the ids whose row was read as bytes and does not parse: the only rows quarantine may move")
fn ! unparseableIds! dir: String -> (List String)
  (match (dirList (cuDir dir))
    ((err _) (list))
    ((ok names)
      (map (fn [(name String)] -> String (optionOr (stringSlice name 0 (- (stringLength name) 4)) name))
           (filter (fn [(name String)] -> Bool
                     (and (stringEndsWith? name ".asn")
                          (match (fileReadString (str (cuDir dir) "/" name))
                            ((err _) false)
                            ((ok raw) (match (parseCUnit raw) ((ok _) false) ((err _) true))))))
                   (listSort names)))))

; (:m :ref STATUS-UNREADABLE :do "the unit ids whose conductor row file does not parse; readCUnits! skips them, so status! lists each as st unreadable instead of dropping the unit")
fn ! unreadableIds! dir: String -> (List String)
  (match (dirList (cuDir dir))
    ((err _) (list))
    ((ok names)
      (map (fn [(name String)] -> String (optionOr (stringSlice name 0 (- (stringLength name) 4)) name))
           (filter (fn [(name String)] -> Bool
                     (and (stringEndsWith? name ".asn")
                          (match (fileReadString (str (cuDir dir) "/" name))
                            ((err _) true)
                            ((ok raw) (match (parseCUnit raw) ((ok _) false) ((err _) true))))))
                   (listSort names)))))

fn ! status! ctx: Ctx -> String
  (let [(cus (readCUnits! ctx.dir))
        (lanes (fold (fn [(acc (List String)) (c CUnit)] -> (List String) (if (listContains? acc c.lane) acc (listAppend acc (list c.lane)))) (list) cus))
        (rows (listAppend (map (fn [(c CUnit)] -> String (str "(:unit :id " (st/q c.id) " :st " c.st " :lane " (st/q c.lane) " :fails " (n c.fails) " :parked " (n c.parked) " :waited " (n c.waited) ")")) cus)
                          (map (fn [(id String)] -> String (str "(:unit :id " (st/q id) " :st unreadable)")) (unreadableIds! ctx.dir))))
        (spend (map (fn [(l String)] -> String
                      (let [(mine (filter (fn [(c CUnit)] -> Bool (= c.lane l)) cus))]
                        (str "(:spend :lane " (st/q l) " :tokens " (n (fold (fn [(a Int64) (c CUnit)] -> Int64 (+ a c.tokens)) 0 mine))
                             " :costUsd " (costText (fold (fn [(a Int64) (c CUnit)] -> Int64 (+ a c.costMicro)) 0 mine)) ")"))) lanes))
        (esc (match (fileReadString (escalationsPath ctx.dir)) ((ok t) (filter (fn [(l String)] -> Bool (not (stringEmpty? (stringTrim l)))) (stringLines t))) ((err _) (list))))]
    (stringJoin (listAppend (listAppend rows spend)
                  (list (str "(:running (" (idList cus active?) "))")
                        (str "(:blocked (" (idList cus (fn [(c CUnit)] -> Bool (= c.st "blocked"))) "))")
                        (str "(:held (" (idList cus (fn [(c CUnit)] -> Bool (and (= c.st "blocked") (= c.await "mergeHold")))) "))")
                        (str "(:parked (" (stringJoin (map (fn [(p (Pair String String))] -> String (st/q (str (pairFirst p) ":" (optionOr (listHead (stringSplit (pairSecond p) "\n")) ""))) ) (parkedRows! ctx.dir)) " ") "))")
                        (str "(:escalations " (n (listLength esc)) ")")
                        (str "(:quarantined (" (stringJoin (map st/q (quarantinedIds ctx.dir)) " ") "))")
                        (match (storeReadError! ctx.dir) ((some e) (str "(:store :unreadable " (st/q e) ")")) ((none) "(:store :ok)"))))
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
    (utf8Clip pick 160))

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
    (map (fn [(p String)] -> String (gg/shrinkSig p (baseLinesOf wt (baseRef u) p) (nowLinesOf wt p) task)) u.owns))) "")

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
  (attachOrAddIn! rc "" u path)

; (:m :ref UNIT-AHEAD-GATING :do "a re-attached sh/UNIT is healed from a saved pre-onBase tip before freshBase! rebases it, so a stage killed mid-writer and a removed worktree do not turn the saved state stale")
fn ! attachOrAddIn! rc: RealCfg dir: String u: st/Task path: String -> (Result String String)
  (match (let [(_ (gitOut rc.repo (list "worktree" "prune")))] (w/addWt! rc.wt u.id u.base))
    ((ok p) (ok p))
    ((err e)
      (if (stringContains? e "already exists")
        (let [(a (fr/runOne (fr/job (list "git" "-C" rc.repo "worktree" "add" path (str "sh/" u.id)) rc.repo (fr/childEnv (list)))))]
          (if (= a.exit 0) (let [(_ (onBaseHealIn! dir path (baseRef u) u.id true))] (freshBase! rc u path)) (err (str "worktree attach failed: " (stringTrim a.out)))))
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

; (:m :ref TRIAL-PIN :do "--writer-model ALIAS pins the Leon form to one gateway alias: :model \"ALIAS\" joins the extra only when the flag is given, so a pinned run is served by that alias and no profile chain; --lease-sec N sets the lease the Leon wall budget derives from")
fn pinExtra rc: RealCfg extra: String -> String
  (if (stringEmpty? rc.writerModel) extra
    (str (if (stringEmpty? extra) "" (str extra " ")) ":model " (st/q rc.writerModel)))

; (:m :ref TRIAL-PIN :do "the whole agentReceipt line of the write child goes to <store>/runs/UNIT-leon.asn; the Res row and the journal verdict carry only a cut of it")
fn ! leonReceiptSave! dir: String id: String out: String -> Bool
  (let [(row (receiptRowOf out))]
    (if (stringEmpty? row) false
      (let [(_ (dirCreate (runsDir dir)))]
        (match (fileWrite (runPath dir id "leon" "asn") (str row "\n")) ((ok _) true) ((err _) false)))))

; (:m :ref LEON-TOOLROOT :do "the write stage hands the Leon run :toolRoot REPO, the conductor's own built checkout as an absolute path (a relative --repo is resolved here, since the unit worktree is another cwd), so check, test and forms in a unit worktree run that tree's bin/asl and a unit that edits CLI sources is not refused ERR_NATIVE_STALE; extra already naming :toolRoot is kept")
fn ! withToolRoot! extra: String root: String -> String
  (if (or (stringEmpty? root) (stringContains? extra ":toolRoot "))
    extra
    (str (if (stringEmpty? extra) "" (str extra " ")) ":toolRoot " (st/q (resultOr (realPath root) root))))

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

; (:m :ref FLEET-COMMIT-VIA-VCS :do "a unit with no :owns used to be committed by add -A; the vcs layer commits only named paths, so the dirty paths of the worktree are named here (untracked ones included)")
fn ! dirtyPaths! p: String -> (List String)
  (let [(r (gitOut p (list "-c" "core.quotePath=false" "status" "--porcelain" "--untracked-files=all")))]
    (if (!= r.exit 0) (list) (porcelainPaths (stringLines r.out))))

; (:m :ref FLEET-COMMIT-VIA-VCS :do "the paths of git status --porcelain lines: a quoted path is unquoted (backslash, quote, tab, newline escapes), and a rename or copy names both the old and the new path")
fn unquoteGit s: String -> String
  (if (and (>= (stringLength s) 2) (and (stringStartsWith? s "\"") (stringEndsWith? s "\"")))
    (unescapeGit (optionOr (stringSlice s 1 (- (stringLength s) 1)) s) 0 "")
    s)

fn unescapeGit s: String i: Int64 acc: String -> String
  (if (>= i (stringLength s))
    acc
    (let [(c (optionOr (stringSlice s i (+ i 1)) ""))]
      (if (and (= c "\\") (< (+ i 1) (stringLength s)))
        (let [(d (optionOr (stringSlice s (+ i 1) (+ i 2)) ""))]
          (unescapeGit s (+ i 2) (str acc (cond ((= d "t") "\t") ((= d "n") "\n") (else d)))))
        (unescapeGit s (+ i 1) (str acc c)))))

fn porcelainPaths lines: (List String) -> (List String)
  (listFlatMap (fn [(l String)] -> (List String)
                 (let [(path (optionOr (stringSlice l 3 (stringLength l)) ""))
                       (renamed (or (stringStartsWith? l "R") (or (stringStartsWith? l "C") (or (stringStartsWith? (optionOr (stringSlice l 1 2) "") "R") (stringStartsWith? (optionOr (stringSlice l 1 2) "") "C")))))]
                   (match (if renamed (stringIndexOf path " -> ") none)
                     ((some at) (list (unquoteGit (optionOr (stringSlice path 0 at) "")) (unquoteGit (optionOr (stringSlice path (+ at 4) (stringLength path)) ""))))
                     ((none) (list (unquoteGit path))))))
               (filter (fn [(l String)] -> Bool (> (stringLength l) 3)) lines))

; (:m :ref CONDUCTOR-ZERO-MERGE :do "the driver commit stages only the owned paths that changed; true when a commit landed")
fn ! commitWrite! p: String owns: (List String) id: String model: String toolRoot: String -> Bool
  (let [(changed (ownedChanges! p owns))]
    (if (listEmpty? changed) false
      (fp/driverCommitRow! p (if (listEmpty? owns) (dirtyPaths! p) changed) id model toolRoot)))

; (:m :ref COORD-WIP-RESCUE :do "progress counts commits past the base except wip rescue commits, found by their ASN message head (:c :a wip :do; a rescued tree is kept work, not a finished write")
fn pastArgs base: String -> (List String)
  (list "rev-list" "--count" "--invert-grep" "--grep=^(:c :a wip :do" (str base "..HEAD"))

fn ! commitsPast? p: String base: String -> Bool
  (if (not (worktreeValid? p)) true
    (let [(r (gitOut p (pastArgs base)))]
      (or (!= r.exit 0) (!= (stringTrim r.out) "0"))))

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

; (:m :ref UNIT-AHEAD-GATING :do "the paths the branch changed past the merge-base that lie outside the unit's :owns (git pathspecs, as ownedChanges! reads them), the grade ledger excepted; empty owns means every path is owned")
fn ! outsideOwned! p: String mb: String owns: (List String) -> (List String)
  (if (listEmpty? owns) (list)
    (let [(names (fn [(d fr/Done)] -> (List String) (filter (fn [(l String)] -> Bool (not (stringEmpty? l))) (map stringTrim (stringLines d.out)))))
          (all (names (gitOut p (list "diff" "--name-only" "--no-renames" mb "HEAD"))))
          (owned (names (gitOut p (listAppend (list "diff" "--name-only" "--no-renames" mb "HEAD" "--") owns))))]
      (filter (fn [(f String)] -> Bool (and (not (listContains? owned f)) (!= f ".asl/mem/grades.asn"))) all)))

; (:m :ref UNIT-AHEAD-GATING :do "the newest (:ahead ...) journal row of the unit, empty when none")
fn ! aheadRow! dir: String id: String -> String
  (optionOr (listLast (filter (fn [(l String)] -> Bool (stringStartsWith? l (str "(:ahead :unit " (st/q id) " "))) (stringLines (readOr (journalPath dir))))) "")

fn aheadRes p: String id: String verdict: String gate: String asserts: Int64 ms: Int64 -> Res
  (Res :tiers "" :ok (if (= verdict "gating") 1 0) :wt p :branch (str "sh/" id) :model "" :tokens 0 :costMicro 0 :claimedGreen 0
       :sig (if (= verdict "gating") "" (vacuousSig gate)) :ms ms :exit 0 :asserts asserts :verdict "")

; (:m :ref AHEAD-REVIEW-FAIL-LOOP :do "true when the newest review verdict in the unit's journal, a :from reviewing row to ready or blocked at stage review, is newer than its newest writer run, a (:profile :unit ...) row that writeResWith journals before every writer run; keyed on writer runs, not on the head, because a rebase onto a moved main and a writer's own commit both change the head while the failed review still stands (node2 2026-11-04: RELAY-PUSH-SHORTNAME head 0a32c45 failed review four times, each time sent straight back to review by the ahead check)")
fn ! reviewFailedSinceWriter? dir: String id: String -> Bool
  (let [(runHead (str "(:profile :unit " (st/q id) " "))
        (tHead (str "(:t :unit " (st/q id) " "))]
    (fold (fn [(failed Bool) (l String)] -> Bool
            (cond
              ((stringStartsWith? l runHead) false)
              ((and (stringStartsWith? l tHead) (and (stringContains? l " :from reviewing ") (and (stringContains? l " :stage review ") (or (stringContains? l " :to ready ") (stringContains? l " :to blocked "))))) true)
              (else failed)))
          false (journalLinesOf dir)))

; (:m :ref UNIT-AHEAD-GATING :do "a write whose gate failed still had its owned edits driver-committed, so a later claim found the work on sh/UNIT and ran another writer on it, whose doc-only change Leon judged vacuous against HEAD, forever (node2 2026-11-04: 27 of 41 branches ahead, never merged); a branch with commits past its base, no uncommitted owned change, no committed path outside :owns and a green unit gate is finished work: the write stage returns it as written without a writer run; a gate green on the merge-base too is the vacuous verdict unless the task is a regression guard, which goes to gating for the ladder; each verdict is one (:ahead ... :head SHA ... :verdict V) row, and a later claim on the same HEAD reuses it instead of running the gate and the base again, so the stage deadline is not spent twice")
fn ! aheadGreen! rc: RealCfg dir: String u: st/Task c: CUnit p: String -> (Option Res)
  (let [(_ (pathRemove (runPath dir u.id "ahead" "run")))
        (past (gitOut p (list "rev-list" "--count" (str (baseRef u) "..HEAD"))))
        (mb (stringTrim (gitOut p (list "merge-base" "HEAD" (baseRef u))).out))]
    (if (or (stringEmpty? u.gate) (or (reviewFailedSinceWriter? dir u.id) (or (!= past.exit 0) (or (= (stringTrim past.out) "0") (or (stringEmpty? mb) (or (not (listEmpty? (ownedChanges! p u.owns))) (not (listEmpty? (outsideOwned! p mb u.owns))))))))) none
      (let [(head (stringTrim (gitOut p (list "rev-parse" "HEAD")).out))
            (cached (aheadRow! dir u.id))]
        (if (stringContains? cached (str " :head " (st/q head) " :mb " (st/q mb) " :gate " (st/q u.gate) " "))
          (let [(v (sp/tokAfter cached ":verdict"))]
            (if (= v "writer") none (some (aheadRes p u.id v u.gate (optionOr (stringToInt64 (sp/tokAfter cached ":executed")) 0) 0))))
          (let [(cw (written c p (str "sh/" u.id)))
                (task (taskText dir u))
                (_ (dirCreate (runsDir dir)))
                (marker (runPath dir u.id "ahead" "run"))
                (_ (fileWrite marker (str "(:aheadCheck :unit " (st/q u.id) " :head " (st/q head) " :startedMs " (n (nowMs)) " :untilMs " (n (+ (nowMs) (* 2000 rc.gateSec))) ")\n")))
                (g (gatesRes rc.gateSec (gateCheckS dir) task u cw))
                (green (and (= g.exit 0) (> g.asserts 0)))
                (before (if green (redBefore! rc dir u cw) (pair -1 0)))
                (_ (pathRemove marker))
                (verdict (cond ((not green) "writer") ((and (= (pairFirst before) 0) (not (regressionGuard? task))) "vacuous") (else "gating")))
                (_ (fileAppend (journalPath dir) (str "(:ahead :unit " (st/q u.id) " :head " (st/q head) " :mb " (st/q mb) " :gate " (st/q u.gate) " :commits " (stringTrim past.out) " :gateExit " (n g.exit) " :executed " (n g.asserts) " :baseExit " (n (pairFirst before)) " :verdict " verdict ")\n")))]
            (if (= verdict "writer") none (some (aheadRes p u.id verdict u.gate g.asserts g.ms))))))))

; (:m :ref UNIT-AHEAD-GATING :do "the saved pre-onBase refs are keyed by unit id, never by branch name: refs/asex is shared by every worktree of the repo, and a detached worktree named refs/asex/preOnBase/HEAD, so another detached unit healed onto this unit's tip")
fn onBaseTipRef id: String -> String
  (str "refs/asex/preOnBase/" id)

fn onBaseMbRef id: String -> String
  (str "refs/asex/preOnBaseMb/" id)

fn ! headOf! p: String -> String
  (stringTrim (gitOut p (list "rev-parse" "HEAD")).out)

fn ! refSha! p: String ref: String -> String
  (let [(r (gitOut p (list "rev-parse" "--verify" "--quiet" (str ref "^{commit}"))))]
    (if (= r.exit 0) (stringTrim r.out) ""))

fn ! onBaseNote! dir: String row: String -> Unit
  (if (stringEmpty? dir) () (let [(_ (fileAppend (journalPath dir) (str row "\n")))] ()))

fn nulSplitLoop s: String bs: Bytes i: Int64 start: Int64 n: Int64 acc: (List String) -> (List String)
  (cond
    ((>= i n) (listReverse (cons (optionOr (stringSlice s start n) "") acc)))
    ((= (bytesGet bs i) 0) (nulSplitLoop s bs (+ i 1) (+ i 1) n (cons (optionOr (stringSlice s start i) "") acc)))
    (else (nulSplitLoop s bs (+ i 1) start n acc)))

fn nulFields s: String -> (List String)
  (let [(bs (stringToBytes s))]
    (filter (fn [(x String)] -> Bool (not (stringEmpty? x))) (nulSplitLoop s bs 0 0 (bytesLength bs) (list))))

; (:m :ref UNIT-AHEAD-GATING :do "a writer that committed under onBaseRun! made commits on the merge-base holding only the paths it wrote; the branch becomes the old tip plus one commit whose tree is the old tip's with each path the writer changed past the merge-base taken from the writer's HEAD (removed when the writer removed it), built in a scratch index, with the writer's message; the real index is then reset to it and the work tree is untouched; names are read NUL-separated so any path survives")
fn ! onBaseRebuild! p: String old: String mb: String -> Bool
  (let [(head (headOf! p))
        (idx (stringTrim (gitOut p (list "rev-parse" "--path-format=absolute" "--git-path" "onBaseIndex")).out))
        (gi (fn [(argv (List String))] -> fr/Done (fr/runOne (fr/job (listAppend (list "git" "-C" p) argv) p (fr/childEnv (list (str "GIT_INDEX_FILE=" idx)))))))
        (paths (nulFields (gitOut p (list "diff" "-z" "--name-only" "--no-renames" mb head)).out))
        (read (= (gi (list "read-tree" old)).exit 0))
        (staged (fold (fn [(ok Bool) (f String)] -> Bool
                        (and ok (let [(ls (optionOr (listHead (nulFields (gitOut p (list "ls-tree" "-z" head "--" f)).out)) ""))
                                      (words (stringSplit (optionOr (listHead (stringSplit ls "\t")) "") " "))]
                                  (if (stringEmpty? ls)
                                    (= (gi (list "update-index" "--force-remove" "--" f)).exit 0)
                                    (= (gi (list "update-index" "--add" "--cacheinfo" (str (optionOr (listHead words) "") "," (optionOr (listLast words) "") "," f))).exit 0)))))
                      read paths))
        (tree (if staged (stringTrim (gi (list "write-tree")).out) ""))
        (_ (pathRemove idx))
        (msg (stringTrim (gitOut p (list "log" "-1" "--format=%B" head)).out))
        (made (if (stringEmpty? tree) (fr/Done :idx 0 :exit 1 :out "" :ms 0 :verdict "exit") (gitOut p (list "commit-tree" tree "-p" old "-m" (if (stringEmpty? msg) "onBase rebuild" msg)))))
        (sha (stringTrim made.out))]
    (and (= made.exit 0) (and (not (stringEmpty? sha)) (= (gitOut p (list "reset" "-q" sha)).exit 0))))

; (:m :ref UNIT-AHEAD-GATING :do "brings sh/UNIT back to the tip saved by onBaseEnter!, right after the writer or on a later claim or wip rescue when the stage died mid-run; it acts only on the state enter left: HEAD at the saved merge-base is a soft reset to the tip, HEAD past it with merge-base(HEAD, base) still that merge-base and the tip not in HEAD is a writer commit rebuilt onto the tip, HEAD at the tip only drops the refs; anything else (the tree was recreated or rebased in between) is (:onBaseStale ...) and the refs are kept; the refs go only on success; no saved tip or no unit id, nothing to do")
fn ! onBaseHeal! dir: String p: String base: String id: String -> Bool
  (onBaseHealIn! dir p base id false)

; (:m :ref UNIT-AHEAD-GATING :do "hard is for a worktree just checked out again by attachOrAddIn!: its tree holds only the branch head, the staged earlier work went with the removed directory, so the restored tip is checked out into the tree as well")
fn ! onBaseHealIn! dir: String p: String base: String id: String hard: Bool -> Bool
  (let [(old (if (stringEmpty? id) "" (refSha! p (onBaseTipRef id))))]
    (if (stringEmpty? old) false
      (let [(mb (refSha! p (onBaseMbRef id)))
            (head (headOf! p))
            (mbNow (stringTrim (gitOut p (list "merge-base" "HEAD" base)).out))
            (done (cond
                    ((stringEmpty? mb) false)
                    ((= head old) true)
                    ((= head mb) (= (gitOut p (list "reset" "-q" "--soft" old)).exit 0))
                    ((and (= mbNow mb) (and (= (gitOut p (list "merge-base" "--is-ancestor" mb "HEAD")).exit 0) (!= (gitOut p (list "merge-base" "--is-ancestor" old "HEAD")).exit 0))) (onBaseRebuild! p old mb))
                    (else false)))
            (_ (if done
                 (let [(_ (gitOut p (list "update-ref" "-d" (onBaseTipRef id))))
                       (_ (gitOut p (list "update-ref" "-d" (onBaseMbRef id))))
                       (_ (if hard (gitOut p (list "reset" "-q" "--hard" "HEAD")) (fr/Done :idx 0 :exit 0 :out "" :ms 0 :verdict "exit")))]
                   ())
                 (onBaseNote! dir (str "(:onBaseStale :unit " (st/q id) " :head " (st/q head) " :tip " (st/q old) " :mb " (st/q mb) " :mbNow " (st/q mbNow) ")"))))]
        done)))

; (:m :ref UNIT-AHEAD-GATING :do "Leon's gate integrity reverts the changed files to HEAD, so on a branch already holding the unit's earlier commits it saw only the new edit; the writer runs with HEAD soft-reset to the merge-base, the earlier work staged, so the revert is measured against the unit base; the tip and the merge-base are saved first as unit-keyed refs (onBaseHeal! restores them when the stage dies mid-run); a saved tip that is still there means an earlier heal did not land, so enter refuses with (:onBaseRefused ...) rather than overwrite the only pointer to that tip, and the writer runs on HEAD as it is")
fn ! onBaseEnter! dir: String p: String base: String id: String -> (Option (Pair String String))
  (let [(head (headOf! p))
        (mb (stringTrim (gitOut p (list "merge-base" "HEAD" base)).out))]
    (cond
      ((or (stringEmpty? id) (or (stringEmpty? mb) (or (stringEmpty? head) (= mb head)))) none)
      ((not (stringEmpty? (refSha! p (onBaseTipRef id))))
        (let [(_ (onBaseNote! dir (str "(:onBaseRefused :unit " (st/q id) " :head " (st/q head) " :why \"a saved pre-onBase tip exists; heal first\")")))] none))
      ((!= (gitOut p (list "update-ref" (onBaseMbRef id) mb)).exit 0) none)
      ((!= (gitOut p (list "update-ref" (onBaseTipRef id) head)).exit 0) (let [(_ (gitOut p (list "update-ref" "-d" (onBaseMbRef id))))] none))
      ((!= (gitOut p (list "reset" "-q" "--soft" mb)).exit 0)
        (let [(_ (gitOut p (list "update-ref" "-d" (onBaseTipRef id))))
              (_ (gitOut p (list "update-ref" "-d" (onBaseMbRef id))))]
          none))
      (else (some (pair head mb)))))

fn ! onBaseRun! dir: String p: String base: String id: String run: (fn ! [] -> fr/Done) -> fr/Done
  (match (onBaseEnter! dir p base id)
    ((none) (run))
    ((some _)
      (let [(d (run))
            (_ (onBaseHeal! dir p base id))]
        d)))

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
; (:m :ref REVIEW-DEFER :do "both counts read only a directory that is its own git top level: git run in a plain directory walks up to an enclosing worktree and counted that branch's commits (conductorTest provider fail read 1 on a unit branch); not a top level is no count, an unreadable count as before")
fn ! noCommits? p: String base: String -> Bool
  (if (or (stringEmpty? p) (not (worktreeValid? p))) true
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
         (and (not (modelEscalatedSig? res.sig))
         (and (not (staleSig? res.sig))
              (and (not (vacuousSig? res.sig))
                   (and (providerFailSig? res.sig (pfPatterns row))
                        (and (noCommits? res.wt (baseRef u))
                             (<= (+ (pairFirst (pwLast ctx.dir c.id)) 1) (pfMaxInRow row)))))))))

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
        (bad (filter (fn [(k String)] -> Bool (not (listContains? (list ":staleWakeMax" ":blockedRetryMax" ":retryBackoffS") k))) keys))
        (m (optionOr (stringToInt64 (sp/tokAfter row ":staleWakeMax")) 1))
        (r (optionOr (stringToInt64 (sp/tokAfter row ":blockedRetryMax")) 2))
        (b (optionOr (stringToInt64 (sp/tokAfter row ":retryBackoffS")) 300))]
    (listAppend
      (map (fn [(k String)] -> String (str "unknown key " k)) bad)
      (listAppend
        (if (or (< m 1) (> m 100)) (list (str ":staleWakeMax " (n m) " outside 1..100")) (list))
        (listAppend
          (if (or (< r 0) (> r 20)) (list (str ":blockedRetryMax " (n r) " outside 0..20")) (list))
          (if (or (< b 1) (> b 86400)) (list (str ":retryBackoffS " (n b) " outside 1..86400")) (list))))))

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
    ((not (fileExists? path)) (attachOrAddIn! rc dir u path))
    ((worktreeValid? path) (let [(_ (onBaseHeal! dir path (baseRef u) u.id))] (reuseWt! rc u path)))
    (else
      (let [(aside (str rc.wt.base "/orphan-" u.id "-" (n (/ (nowNs) 1000000))))
            (mv (pathRename path aside))]
        (match mv
          ((err e) (err (str "orphan worktree dir not movable: " e)))
          ((ok _)
            (let [(_ (fileAppend (journalPath dir) (str "(:orphan :unit " (st/q u.id) " :moved " (st/q aside) ")\n")))
                  (_ (gitOut rc.repo (list "worktree" "prune")))]
              (attachOrAddIn! rc dir u path)))))))

; (:m :ref COND-TASK-SPEC :do "each owned file's state in the unit worktree at claim: its line count, -1 when it does not exist yet; directory entries (a trailing slash) are left out")
fn ! ownedStates! wt: String owns: (List String) -> (List (Pair String Int64))
  (map (fn [(p String)] -> (Pair String Int64)
         (pair p (match (fileReadString (str wt "/" p)) ((ok t) (listLength (stringLines t))) ((err _) -1))))
       (filter (fn [(p String)] -> Bool (not (stringEndsWith? p "/"))) owns))

; (:m :ref COND-TASK-SPEC :do "the brief the writer gets: the stored task text (never rewritten in the store) with the owned paths' states at claim added, then the prior note when there is one")
fn ! briefTask! wt: String dir: String u: st/Task prior: String -> String
  (let [(text (bf/briefFor (taskText dir u) (ownedStates! wt u.owns)))]
    (if (stringEmpty? prior) text (str text "\n\n" prior)))

; (:m :ref COND-MODEL-ESCALATE :do "the :stop of Leon's receipt: read from the final receipt row, and from the (:agentReceipt ...) form nested in an (:agent ... :receipt ...) wrapper when the row is the wrapper")
fn stopOf out: String -> String
  (stringTrim (stringReplace (stringReplace (sp/tokAfter (receiptRowOf out) ":stop") ")" "") "\"" ""))

; (:m :ref COND-MODEL-ESCALATE :do "Leon's receipt :stop modelEscalated means the model itself asked for help, which no rung of the ladder answers: the write result carries the signature modelEscalated: REASON (the :reason of the receipt's :escalate form, else the gate signature) and finish! parks the unit at once; a readStreak whose reason names (refusedWrites) stays a normal failure with the cause in the signature, so the ladder and the lead both see why writes did not land")
fn modelEscalatedSig out: String -> String
  (let [(row (receiptRowOf out))
        (reason (quotedAfter row ":reason \""))]
    (str "modelEscalated: " (if (stringEmpty? reason) (gateSig out) (utf8Clip reason 200))))

fn modelEscalatedSig? sig: String -> Bool
  (stringStartsWith? sig "modelEscalated: ")

fn writeFailSig out: String -> String
  (let [(row (receiptRowOf out))]
    (if (and (= (stopOf out) "readStreak") (stringContains? row "(refusedWrites)"))
      (str "refusedWrites: " (gateSig out))
      (gateSig out)))

fn ! writeRes rc: RealCfg dir: String u: st/Task c: CUnit -> Res
  (writeResWith runWrite! rc dir u c)

; (:m :ref COND-TASK-SPEC :do "the write stage with its Leon run injected, so a gate can record the task text the writer would receive; writeRes passes runWrite!")
fn ! writeResWith run: (fn ! [(rc RealCfg) (lane String) (id String) (prof String) (p String) (task String) (owns (List String)) (gates (List String)) (extra String)] -> fr/Done) rc: RealCfg dir: String u0: st/Task c: CUnit -> Res
  (let [(u (resolved! rc.repo u0))
        (path (w/wtPath rc.wt u.id))
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
              (_ (fileAppend (journalPath dir) (str "(:profile :unit " (st/q u.id) " :lane " (st/q c.lane) " :profile " (st/q prof) (if (stringEmpty? arm) "" (str " :arm " (st/q arm))) (if (stringEmpty? rc.writerModel) "" (str " :pin " (st/q rc.writerModel))) " :at " (n (/ (nowNs) 1000000)) ")\n")))
              (pv (vacuousAround! p (baseRef u) u.owns u.gate task (fn [] -> fr/Done (onBaseRun! dir p (baseRef u) u.id (fn [] -> fr/Done (run rc c.lane u.id prof p task u.owns (if (stringEmpty? u.gate) (list) (list u.gate)) (withToolRoot! (fp/withBase (pinExtra rc (armExtra arm)) (baseRef u)) rc.repo)))))))
              (d (pairFirst pv))
              (_ (leonReceiptSave! dir u.id d.out))
              (model (servedModel d.out))
              ; (:m :ref COND-RECOVER-C1 :do "a commit landed past the base during the run (the free pool's driver commit of a gate-passed row) is progress the gating stage can test, so a vacuous receipt does not block it: 21 of 30 vacuousGate units on node2 held such a commit and 16 of those were test-only diffs")
              (vacuous (and (pairSecond pv) (not (commitsPast? p (baseRef u)))))
              (stop (stopOf d.out))
              (modelEsc (and (= stop "modelEscalated") (not vacuous)))
              (_ (if vacuous false (commitWrite! p u.owns u.id model rc.repo)))
              ; (:m :ref CONDUCTOR-ZERO-MERGE :do "review diffs base...HEAD and merge trains the branch, so a write is progress only when a commit landed: an owned edit the driver could not commit was reviewed as an empty diff 6 times (NODE2-ASEX-DETACHED)")
              (noEdit (and (= d.exit 0) (not (commitsPast? p (baseRef u)))))]
          (Res :tiers "" :ok (if (and (= d.exit 0) (and (not noEdit) (and (not vacuous) (not modelEsc)))) 1 0) :wt p :branch (str "sh/" u.id) :model model :alias (servedAliasOf d.out) :tokens (leonTokens d.out) :costMicro (leonCost d.out (rs/costRows (readOr (str rc.home "/.asl/gateway.asn")) (readOr rc.lanes)) model) :claimedGreen 0
               :sig (cond (vacuous (vacuousSig u.gate)) (modelEsc (modelEscalatedSig d.out)) ((!= d.exit 0) (writeFailSig d.out)) (noEdit "noEdit") (else "")) :ms d.ms :exit d.exit :asserts 0 :verdict "")))))))))

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

; (:m :ref CONDUCTOR-MERGE-CHECK-FIX :do "budgets: merge-check-sec adopted 1200 (flag, RealCfg.mergeCheckSec) plus the train limit 3600 stay under the stage deadline, whose default is now 5400 (was 4200, which the sum of the old 900 and 3600 already exceeded)")
; (:m :ref CONDUCTOR-MERGE-CHECK :do "the merge-time audit asl/tools/coord/mergeCheck.asl in process on the unit branch against its merge base with dev, cli = the dev clone bin/asl, cache under the home; returns its exit (0 pass, 1 block, 3 unverified, 2 could not run) and receipt")
fn ! realMergeCheck! rc: RealCfg c: CUnit base: String -> (Pair Int64 String)
  (mc/run! (mc/Opts :repo rc.devRepo :base base :head c.branch :cli (str rc.devRepo "/bin/asl") :totalS rc.mergeCheckSec :stepS 300 :cache (str rc.home "/.asl/run/mergeCheck")))

; (:m :ref CONDUCTOR-MERGE-CHECK :do "the receipt row of one merge check lands in the journal whatever the verdict, so a merged unit shows what was checked")
fn ! mergeReceipt! store: String id: String ex: Int64 receipt: String -> Bool
  (ok? (fileAppend (journalPath store) (str "(:mergeReceipt :unit " (st/q id) " :exit " (n ex) " :at " (n (nowMs)) " " receipt ")\n")))

; (:m :ref CONDUCTOR-MERGE-CHECK :do "the text of one parenthesised list of a receipt, :structure or :regressions or :unverified, cut to 300 chars, for the signature of a block or a hold")
fn mergeCheckWhy receipt: String key: String -> String
  (let [(parts (stringSplit receipt (str " " key " (")))
        (rows (if (< (listLength parts) 2) "" (stringTrim (optionOr (listHead (stringSplit (optionOr (listGet parts 1) "") ") :")) ""))))]
    (utf8Clip rows 300))

; (:m :ref CONDUCTOR-MERGE-CHECK :do "a check that blocks leaves dev untouched and the unit blocked with verdict block and the sig mergeCheck: rows; one that could not verify (exit 3, or 2 when it could not run) holds the unit with verdict hold plus one lead-stream event; neither counts as a failed merge; exit 0 returns none and the train goes on")
fn mergeHoldWhy ex: Int64 receipt: String -> String
  (str "mergeCheck unverified exit " (n ex) ": " (mergeCheckWhy receipt ":unverified") (utf8Clip receipt 160))

fn ! mergeVerdictRes! store: String u: st/Task r: (Pair Int64 String) -> (Option Res)
  (let [(ex (pairFirst r))
        (receipt (pairSecond r))
        (_ (mergeReceipt! store u.id ex receipt))]
    (cond
      ((= ex 0) (none))
      ((= ex 1) (some (with (failRes (str "mergeCheck: " (mergeCheckWhy receipt ":structure") " " (mergeCheckWhy receipt ":regressions"))) :verdict "block")))
      (else
        (let [(why (mergeHoldWhy ex receipt))
              (_ (ls/emitAt! (dirOf store) (nowMs) "conductor" "warn" "mergeCheckHold" u.id u.id why))]
          (some (with (failRes why) :verdict "hold"))))))

; (:m :ref MERGECHECK-CLAMP :do "the budget literals live once: the train child's limit and the stage deadline default; the merge-check budget is clamped so it plus the train limit plus a 60 s margin stays under the stage deadline, whatever --merge-check-sec says; a --stage-sec below train limit + 120 s has no room for any check, so the 60 s floor applies and the sum can exceed the deadline (an operator choice, not defended)")
fn trainLimitSec -> Int64
  3600

fn stageSecDefault -> Int64
  5400

fn clampMergeCheckSec requested: Int64 stageSec: Int64 -> Int64
  (max 60 (min requested (- (- stageSec (trainLimitSec)) 60)))

fn ! mergeRes rc: RealCfg store: String u: st/Task c: CUnit -> Res
  (mergeResWith rc store u c realMergeCheck!)

fn ! mergeResWith rc: RealCfg store: String u: st/Task c: CUnit check: (fn ! [RealCfg CUnit String] -> (Pair Int64 String)) -> Res
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
              (mb (if (= fetched.exit 0) (gitOut rc.devRepo (list "merge-base" "HEAD" c.branch)) fetched))
              ; (:m :ref MERGECHECK-CLAMP :do "a failed fetch skips the check (the train below fails on the same cause with its own signature); a good fetch with no merge base is not a pass: the unit holds as unverified exit 3, so a branch unrelated to dev is never merged unchecked")
              (verdict (cond
                         ((and (= mb.exit 0) (not (stringEmpty? (stringTrim mb.out)))) (mergeVerdictRes! store u (check rc c (stringTrim mb.out))))
                         ((= fetched.exit 0) (mergeVerdictRes! store u (pair 3 "(:mergeCheck :verdict unverified :unverified (\"noMergeBase\") :structure () :regressions ())")))
                         (else (none))))]
          (match verdict
            ((some stopped) stopped)
            ((none)
              (let [(d (fr/runOneLimited (fr/job (list (str rc.devRepo "/bin/asl") "train" c.branch "--onto" "HEAD" "--repo" rc.devRepo "--commit") rc.devRepo (mergeEnv))
                                         (fr/limits (trainLimitSec) 200)))]
                (if (and (= fetched.exit 0) (and (= d.exit 0) (not (stringContains? d.out ":commitError"))))
                  (let [(_ (w/removeWt! rc.wt u.id true))]
                    (Res :tiers "" :ok 1 :wt "" :branch "" :model "" :tokens 0 :costMicro 0 :claimedGreen 0 :sig "" :ms d.ms :exit 0 :asserts 0 :verdict ""))
                  (let [(f (failRes (gateSig d.out)))] (with f :ms d.ms))))))))))

; (:m :ref CONDUCTOR :do "thin adapter for the COND2 ladder: its Ruling action (merge|fix|await|blocked) maps to the review verdict pass|fail|defer|block; an unknown action blocks")
fn rulingVerdict action: String -> String
  (cond ((= action "merge") "pass") ((= action "fix") "fail") ((= action "await") "defer") (else "block"))

; (:m :ref CONDUCTOR :do "review is the COND2 ladder (asl/tools/coord/ladder.asl); until it is wired every review defers and parks the unit")
fn reviewUnwired -> Res
  (Res :tiers "" :ok 0 :wt "" :branch "" :model "" :tokens 0 :costMicro 0 :claimedGreen 0 :sig "review ladder not wired" :ms 0 :exit 0 :asserts 0 :verdict "defer")

fn ! readOr path: String -> String
  (resultOr (fileReadString path) "")

; (:m :ref REVIEW-DEFER :do "a unit :base of HEAD or empty names the branch the conductor repo has checked out, as addWt! and freshBase! read it there; inside a unit worktree HEAD is the unit branch, so the stages work on the unit with that branch name (the HEAD sha when the repo is detached); an unreadable repo leaves the unit as it is")
fn ! repoBase! repo: String -> String
  (let [(b (gitOut repo (list "rev-parse" "--abbrev-ref" "HEAD")))
        (name (stringTrim b.out))]
    (cond
      ((or (stringEmpty? repo) (!= b.exit 0)) "")
      ((and (not (stringEmpty? name)) (!= name "HEAD")) name)
      (else (let [(s (gitOut repo (list "rev-parse" "HEAD")))] (if (= s.exit 0) (stringTrim s.out) "")))))

fn ! resolved! repo: String u: st/Task -> st/Task
  (if (or (stringEmpty? u.base) (= u.base "HEAD"))
    (let [(b (repoBase! repo))] (if (stringEmpty? b) u (with u :base b)))
    u)

; (:m :ref REVIEW-DEFER :do "the base a unit branch is measured against inside its worktree: planImport stores :base HEAD by default (80 of 170 node2 units), and HEAD in a unit worktree is the branch itself, so HEAD..HEAD read every write as noEdit and every ahead branch as not ahead; HEAD and empty both mean main")
fn baseRef u: st/Task -> String
  (if (or (stringEmpty? u.base) (= u.base "HEAD")) "main" u.base)

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

; (:m :ref AHEAD-WRITER-UNKNOWN :do "a unit that entered gating through the ahead check has no model on its write-to-gating row, and its failed or blocked write rows, which the stage journals with the served model, were ignored, so the writer stayed unknown and R1 deferred on writerFamily for ever (LL-BUF-RT, STD-CHECKSUMS): every write-stage row from writing counts, failed ones too, except a failed one that names no known model (a crashed run says unknown and must not hide an earlier known writer)")
; (:m :ref REVIEW-DEFER :do "the writer of the work under review: the newest write-to-gating journal row of the unit that names a writer: its served alias, else its model, unknown included so selection waits rather than fall back to an older round's writer; only a write the ahead check passed (model empty, no alias) is skipped, so the writer before it counts; the unit row's model when the journal names none")
fn ! writerOf! dir: String c: CUnit -> String
  (let [(head (str "(:t :unit " (st/q c.id) " "))
        (pick (fn [(l String)] -> String (let [(a (quotedAfter l ":alias \""))] (if (stringEmpty? a) (quotedAfter l ":model \"") a))))
        (rows (filter (fn [(l String)] -> Bool (and (stringStartsWith? l head) (and (stringContains? l " :from writing ") (and (stringContains? l " :stage write ") (and (not (stringEmpty? (pick l))) (or (stringContains? l " :to gating ") (!= (pick l) "unknown"))))))) (journalLinesOf dir)))]
    (match (listLast rows) ((some l) (pick l)) ((none) c.model)))

; (:m :ref REVIEW-NO-DIFF :do "a review never passes a change no reviewer was shown: a gone worktree, a failed git diff (missing base ref) or an empty diff ends the review before any model call: an empty diff as block, an unreadable one (gone worktree, failed git diff) as verdict requeue, which finish! turns into a transient move to ready (no fail count, capped through retries.asn)")
; (:m :ref LANE-UNAVAILABLE-MEMORY :do "laneUnavailable rows from the ladder are remembered in laneDead.asn with an until time of at plus the lane-ttl-sec stage flag (adopted 3600); while a row is live the review call for that alias returns a permanent error without calling the provider, so later reviews skip the lane and the ladder picks another; a row marked remembered is not stored again so its own echo does not extend the window; after the window the lane is tried once more; the first sighting of a lane sends one lead-stream warn keyed lane and cause")
fn laneDeadPath dir: String -> String
  (str dir "/laneDead.asn")

; (:m :ref LANE-UNAVAILABLE-MEMORY-FIX :do "ledger rows are read as forms, never by splitting text: a why with escaped quotes (a JSON error body) or the word :until in it stays one field; a line that is no laneDead form is dropped")
fn deadFields l: String -> (List asn/AsnField)
  (resultOr (st/rowFields l "laneDead") (list))

fn laneDeadRows dir: String -> (List String)
  (filter (fn [(l String)] -> Bool (not (listEmpty? (deadFields l)))) (stringLines (readOr (laneDeadPath dir))))

fn laneDeadLive dir: String nowMs: Int64 -> (List String)
  (filter (fn [(l String)] -> Bool (> (st/intField (deadFields l) "until") nowMs)) (laneDeadRows dir))

fn laneCause why: String -> String
  (l/causeOf why)

; (:m :ref LANE-UNAVAILABLE-MEMORY-FIX :do "the remembered error keeps the lane cause in a form permanentError? reads: credits as insufficient credit, a status as HTTP N; the word remembered keeps rememberDeadLanes! from storing it again")
fn rememberedErr cause: String why: String -> String
  (str "remembered lane unavailable " (if (= cause "credits") "insufficient credit" (if (= cause "permanent") "HTTP 403" (str "HTTP " cause))) ": " why)

fn ! skipDead dir: String nowMs: Int64 inner: (fn ! [String String] -> (Result String String)) -> (fn ! [String String] -> (Result String String))
  (let [(dead (laneDeadLive dir nowMs))]
    (fn [(alias String) (prompt String)] -> (Result String String)
      (match (listFind (fn [(l String)] -> Bool (= (st/textField (deadFields l) "lane") alias)) dead)
        ((some l) (err (rememberedErr (st/textField (deadFields l) "cause") (st/textField (deadFields l) "why"))))
        ((none) (inner alias prompt)))))

fn unavailFields l: String -> (List asn/AsnField)
  (resultOr (st/rowFields l "laneUnavailable") (list))

; (:m :ref LANE-UNAVAILABLE-MEMORY-FIX :do "the read-modify-write of laneDead.asn runs under a flock beside it so parallel stage children do not drop each other's rows, and a failed write is an error, not a stored row: no lead warn is sent for it")
fn ! rememberDeadLanes! dir: String ttlSec: Int64 nowMs: Int64 rows: (List String) -> (Result Int64 String)
  (let [(fresh (filter (fn [(l String)] -> Bool (and (stringStartsWith? l "(:laneUnavailable ") (not (stringContains? l "remembered")))) rows))]
    (if (listEmpty? fresh) (ok 0)
      (match (fileLockWait (str (laneDeadPath dir) ".lock") true 10000)
        ((err e) (err (str "laneDead lock: " e)))
        ((ok fd)
          (let [(lanes (map (fn [(l String)] -> String (st/textField (unavailFields l) "lane")) fresh))
                (kept (filter (fn [(l String)] -> Bool (not (listContains? lanes (st/textField (deadFields l) "lane")))) (laneDeadLive dir nowMs)))
                (added (map (fn [(l String)] -> String
                              (let [(why (st/textField (unavailFields l) "why"))]
                                (str "(:laneDead :lane " (st/textField (unavailFields l) "lane") " :cause " (laneCause why) " :why " (st/q why) " :at " (n nowMs) " :until " (n (+ nowMs (* ttlSec 1000))) ")")))
                            fresh))
                (tmp (str (laneDeadPath dir) "." (n (procSelf)) ".tmp"))
                (w (fileWrite tmp (str (stringJoin (listAppend kept added) "\n") "\n")))
                (r (match w ((err e) (err e)) ((ok _) (pathRename tmp (laneDeadPath dir)))))
                (_ (fdClose fd))]
            (match r
              ((err e) (err (str "laneDead write: " e)))
              ((ok _)
                (let [(_ (map (fn [(l String)] -> Bool
                                (let [(why (st/textField (unavailFields l) "why"))]
                                  (ls/emitAt! (dirOf dir) nowMs "conductor" "warn" "laneUnavailable" (str (st/textField (unavailFields l) "lane") ":" (laneCause why)) (st/textField (unavailFields l) "unit") why)))
                              fresh))]
                  (ok (listLength fresh))))))))))

fn ! realReview rc: RealCfg dir: String u: st/Task c: CUnit -> Res
  (let [(gatewayText (readOr (str rc.home "/.asl/gateway.asn")))
        (lanesText (readOr rc.lanes))
        (usage (runPath dir u.id "usage" "asn"))
        (_ (pathRemove usage))
        (diff (if (worktreeValid? c.wt) (gitOut c.wt (list "diff" (str (baseRef u) "...HEAD"))) (fr/Done :idx 0 :exit 128 :out "worktree gone" :ms 0 :verdict "exit")))
        (riskRaw (stringTrim (readOr (str dir "/tasks/" u.id ".risk"))))
        (risk (if (stringEmpty? riskRaw) "low" riskRaw))
        (writer (rs/writerAliasFor gatewayText lanesText (l/reviewWriter (writerOf! dir c) rc.writerAlias)))
        (ru (l/ReviewUnit :id u.id :task (taskText dir u) :risk risk :closureChanged false :writerAlias writer :writerChannel u.channel
                          :startRung (offeredRung! dir u.id) :fixesUsed c.fails :prior (list)))
        (call (skipDead dir (nowMs) (rs/callModelFor! rc.repo usage (rs/costRows gatewayText lanesText))))]
    (if (or (!= diff.exit 0) (stringEmpty? (stringTrim diff.out)))
      (Res :tiers "" :ok 0 :wt "" :branch "" :model "" :tokens 0 :costMicro 0 :claimedGreen 0
           :sig (if (!= diff.exit 0) (str "reviewDiffUnreadable: git diff " (baseRef u) "...HEAD exit " (n diff.exit) " " (repoClip diff.out)) (str "reviewDiffEmpty: no change past " (baseRef u)))
           :ms 0 :exit 0 :asserts 0 :verdict (if (!= diff.exit 0) "requeue" "block"))
    (match (rs/reviewUnit! gatewayText lanesText (pacesNow rc) rc.repo usage ru diff.out (readOr (runPath dir u.id "receipt" "asn")) call)
      ((err e) (failRes (str "ladder: " e)))
      ((ok r)
        (let [(_ (fileAppend (journalPath dir) (str (stringJoin r.rows "\n") "\n")))
              (_ (match (rememberDeadLanes! dir rc.laneTtlSec (nowMs) r.rows) ((err e) (ok? (fileAppend (journalPath dir) (str "(:laneDeadFailed :unit " (st/q u.id) " :why " (st/q e) ")\n")))) ((ok _) true)))]
          (Res :tiers (tiersOfRows r.rows) :ok 0 :wt "" :branch "" :model r.models :tokens r.tokens :costMicro r.costMicro :claimedGreen 0 :sig r.sig :ms 0 :exit 0 :asserts 0
               :verdict (rulingVerdict r.action)))))))

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
    (let [(spent (fold (fn [(m (Map String Int64)) (lane String)] -> (Map String Int64) (mapSet m lane (wakeUpTo! ctx lane (allowanceOf after lane)))) (mapEmpty) rising))]
      (+ (fold (fn [(a Int64) (lane String)] -> Int64 (+ a (mapGetOr spent lane 0))) 0 rising)
         (+ (deadAwaitWake! ctx (map pairFirst after)) (availWakeSpent! ctx after spent)))))

; (:m :ref REFRESH-WAKE-MISSED-RISE :do "a rise counts only between the before and after snapshots of one refresh, so a window that resets between two refresh ticks never rose and units parked on that lane slept on: a parked unit wakes when any lane its await names has allowance now. Tier names (free paid strong) do not count, since a tier with allowance only in the writer family would wake and re-park the unit every tick, and a unit whose newest await is quorumStarved stays parked, since its lanes had allowance and did not answer, so it keeps its rise wake and its starved cap")
fn availNames after: (List (Pair String Int64)) -> (List String)
  (map pairFirst (filter (fn [(p (Pair String Int64))] -> Bool (and (> (pairSecond p) 0) (not (listContains? (list "free" "paid" "strong") (pairFirst p))))) after))

; (:m :ref WAKE-LOWS :do "one pass over the journal keeps the newest await row per unit (:visits counts the lines visited, so a scan per parked unit shows as units times lines); starvedAwait? then looks the unit up instead of filtering every line again")
(schema AwaitScan (:f newest (Map String String)) (:f visits Int64))

fn awaitScan lines: (List String) -> AwaitScan
  (fold (fn [(s AwaitScan) (l String)] -> AwaitScan
          (if (stringStartsWith? l "(:await :unit ")
            (AwaitScan :newest (mapSet s.newest (st/textField (resultOr (st/rowFields l "await") (list)) "unit") l) :visits (+ s.visits 1))
            (AwaitScan :newest s.newest :visits (+ s.visits 1))))
        (AwaitScan :newest (mapEmpty) :visits 0) lines)

fn starvedAwait? scan: AwaitScan id: String -> Bool
  (stringContains? (mapGetOr scan.newest id "") ":why \"quorumStarved:")

; (:m :ref WAKE-LOWS :do "a herd wake is staggered: per tick at most as many units wake on a lane as that lane's allowance now, less those wake! already took on it this tick; the rest wake on later ticks")
fn allowanceOf after: (List (Pair String Int64)) lane: String -> Int64
  (pairSecond (optionOr (listFind (fn [(p (Pair String Int64))] -> Bool (= (pairFirst p) lane)) after) (pair lane 0)))

fn staggered picks: (List (Pair CUnit String)) after: (List (Pair String Int64)) spent: (Map String Int64) -> (List (Pair CUnit String))
  (pairFirst (fold (fn [(acc (Pair (List (Pair CUnit String)) (Map String Int64))) (p (Pair CUnit String))] -> (Pair (List (Pair CUnit String)) (Map String Int64))
                     (let [(lane (pairSecond p))
                           (used (mapGetOr (pairSecond acc) lane 0))]
                       (if (>= used (allowanceOf after lane)) acc
                         (pair (listAppend (pairFirst acc) (list p)) (mapSet (pairSecond acc) lane (+ used 1))))))
                   (pair (list) spent) picks))

; (:m :ref WAKE-LOWS :do "the wake plan of availWake!, pure: parked units whose await names a lane with allowance that is not live in laneDead, not starved by their newest await row, staggered per lane; :visits is the scan cost")
(schema AvailPlan (:f go (List (Pair CUnit String))) (:f visits Int64))

fn availPlan cus: (List CUnit) after: (List (Pair String Int64)) dead: (List String) lines: (List String) spent: (Map String Int64) -> AvailPlan
  (let [(avail (filter (fn [(nm String)] -> Bool (not (listContains? dead nm))) (availNames after)))
        (hit (fn [(c CUnit)] -> String (optionOr (listHead (filter (fn [(nm String)] -> Bool (listContains? avail nm)) (stringSplit c.await " "))) "")))
        (parked (filter (fn [(c CUnit)] -> Bool (and (= c.st "awaitReview") (and (= c.parked 1) (not (stringEmpty? (hit c)))))) cus))
        (scan (if (listEmpty? parked) (AwaitScan :newest (mapEmpty) :visits 0) (awaitScan lines)))
        (fresh (filter (fn [(c CUnit)] -> Bool (not (starvedAwait? scan c.id))) parked))]
    (AvailPlan :go (staggered (map (fn [(c CUnit)] -> (Pair CUnit String) (pair c (hit c))) fresh) after spent) :visits scan.visits))

fn ! availWakeSpent! ctx: Ctx after: (List (Pair String Int64)) spent: (Map String Int64) -> Int64
  (let [(cus (readCUnits! ctx.dir))
        (dead (map (fn [(l String)] -> String (st/textField (deadFields l) "lane")) (laneDeadLive ctx.dir (nowMs))))
        (parked (filter (fn [(c CUnit)] -> Bool (and (= c.st "awaitReview") (= c.parked 1))) cus))
        (plan (availPlan parked after dead (if (listEmpty? parked) (list) (journalLinesOf ctx.dir)) spent))
        (_ (map (fn [(p (Pair CUnit String))] -> CUnit (move! ctx (parkedOf (pairFirst p) 0) "awaitReview" "wake" "" 0 0 (str "available:" (pairSecond p)) 0)) plan.go))]
    (listLength plan.go))

fn ! availWake! ctx: Ctx after: (List (Pair String Int64)) -> Int64
  (availWakeSpent! ctx after (mapEmpty))

; (:m :ref REVIEW-PARK-DEADLANE :do "node2 2026-11-12: units parked on a lane that left lanes.asn or is remembered dead (commandCode with no credits) waited for an allowance refresh that never comes, 10 slept 1.5 h; a parked unit whose every awaited name is unknown to the lane snapshot or live in laneDead wakes and goes back to review on the lanes that exist")
fn deadAwait? await: String known: (List String) dead: (List String) -> Bool
  (let [(names (filter (fn [(s String)] -> Bool (not (stringEmpty? s))) (stringSplit await " ")))]
    (and (not (listEmpty? names))
         (listAll? (fn [(nm String)] -> Bool (or (listContains? dead nm) (not (listContains? known nm)))) names)))

fn ! deadAwaitWake! ctx: Ctx known: (List String) -> Int64
  (let [(dead (map (fn [(l String)] -> String (st/textField (deadFields l) "lane")) (laneDeadLive ctx.dir (nowMs))))
        (cus (filter (fn [(c CUnit)] -> Bool (and (= c.st "awaitReview") (and (= c.parked 1) (deadAwait? c.await known dead)))) (readCUnits! ctx.dir)))
        (_ (map (fn [(c CUnit)] -> CUnit (move! ctx (parkedOf c 0) "awaitReview" "wake" "" 0 0 (str "deadAwait:" c.await) 0)) cus))]
    (listLength cus))

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

fn ! realRes rc: RealCfg dir: String stage: String u0: st/Task c: CUnit -> Res
  (let [(u (resolved! rc.repo u0))]
  (cond
    ((= stage "write") (writeRes rc dir u c))
    ((= stage "gates") (gatesStage rc dir u c))
    ((= stage "review") (realReview rc dir u c))
    ((= stage "merge") (mergeRes rc dir u c))
    (else (failRes (str "unknown stage " stage)))))

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
             :home (st/opt args "home" (resultOr (getHomeDir) ".")) :keys (st/opt args "keys" (str repo "/.env.free")) :leaseSec (st/intOpt args "lease-sec" 3600) :gateSec 3600
             :lanes (st/opt args "lanes" (str repo "/.asl/mem/work/CAL/reviewLanes.asn")) :writerAlias (st/opt args "writer-alias" "") :profile (st/opt args "profile" "freeBulk")
             :attractorAb (= (st/opt args "attractor-ab" "off") "on") :leonPool (st/opt args "leon-pool" "") :writerModel (st/opt args "writer-model" "") :laneTtlSec (st/intOpt args "lane-ttl-sec" 3600) :mergeCheckSec (clampMergeCheckSec (st/intOpt args "merge-check-sec" 1200) (st/intOpt args "stage-sec" (stageSecDefault)))))

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
                    (list) (list "repo" "dev-repo" "dev" "worktrees" "archive" "home" "keys" "lanes" "writer-alias" "profile" "attractor-ab" "leon-pool" "writer-model" "lease-sec" "lane-ttl-sec" "merge-check-sec")))]
    (fn [(stage String) (u st/Task) (c CUnit)] -> (List String)
      (listAppend (list (str repo "/bin/asl") "run" (str repo "/asl/tools/coord/conductor.asl") "stage" stage u.id "--store" dir) pass)))

; (:m :ref MERGECHECK-CLAMP :do "the service Ctx in one function, so a test reads the stage deadline the conductor really runs with: --stage-sec or the one default literal")
fn ! realCtx args: (List String) dir: String rc: RealCfg -> Ctx
  (Ctx :dir dir :holder (str "conductor" (n (procSelf))) :ttlMs 3600000 :maxWait (st/intOpt args "max-wait" 30) :maxSame 3
       :stageSec (st/intOpt args "stage-sec" (stageSecDefault)) :maxDesc 200 :launch (realLaunch args dir) :pace (schedPace dir rc.home))

fn ! main args: (List String) -> (Result Int64 String)
  (let [(cmd (optionOr (listHead args) ""))
        (dir (st/opt args "store" (str (resultOr (getHomeDir) ".") "/.asl/run/conductor")))
        (rc (realCfg args dir))
        (ctx (realCtx args dir rc))]
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
