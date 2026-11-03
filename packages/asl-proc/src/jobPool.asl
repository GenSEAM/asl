(module asl-proc/jobPool
  :x [Job Done Limits Proc job limits defaultLimits runPool runPoolLimited runPoolEach runOne runOneLimited psPairs descendantsOf psSnapshot procsOf procsAt pinOf pinsOf procSnapshot treeOf fenceOf fenced? killTree! shellOut childEnv secretName? executedOf errorLinesOf quoteArgv]
  :i [])

; (:m :ref HL-FIXWAVE-M4 :do "the bounded-job, process-tree-killing engine asl/tools/fleet/run.asl carries (watchdog timeout, descendant cap, group-wide SIGSTOP/SIGKILL) moved here verbatim so the published asl/ subtree (asl-cli/nativeBuild.asl, asl-cli/native.asl) can build and run its own native CLI without importing tools/, which lives outside asl/ and is absent from a standalone checkout; asl/tools/fleet/run.asl keeps its own copy for its many existing callers (fleetRunTest.asl and the fleetCompareTest/fleetGuardTest/fleetWatchTest/fleetReceiptTest/fleetRedBeforeTest families, none of them under asl/), since re-exporting a schema type under a second module name is not available here")

(schema Job
  (:f argv (List String))
  (:f cwd String)
  (:f env (List String)))

(schema Done
  (:f idx Int64)
  (:f exit Int64)
  (:f out String)
  (:f ms Int64)
  (:f verdict String))

(schema Limits
  (:f timeoutMs Int64)
  (:f maxDesc Int64)
  (:f owner Int64 :default 0))

(schema Proc
  (:f pid Int64)
  (:f ppid Int64)
  (:f pgid Int64)
  (:f age Int64 :default -1)
  (:f born Int64 :default -1))

(schema Running
  (:f idx Int64)
  (:f pid Int64)
  (:f outFd Int64)
  (:f errFd Int64)
  (:f text String)
  (:f outOpen Bool)
  (:f errOpen Bool)
  (:f startNs Int64)
  (:f killed String)
  (:f groups (List Int64))
  (:f known (List Int64)))

fn job argv: (List String) cwd: String env: (List String) -> Job
  (Job :argv argv :cwd cwd :env env)

fn secretName? name: String -> Bool
  (or (stringEndsWith? name "_API_KEY") (or (stringContains? name "TOKEN") (stringContains? name "SECRET")))

fn ! childEnv overrides: (List String) -> (List String)
  (let [(nameOf (fn [(row String)] -> String (optionOr (listHead (stringSplit row "=")) row)))
        (names (map nameOf overrides))]
    (listAppend overrides
      (filter (fn [(row String)] -> Bool
                (let [(k (nameOf row))] (and (not (listContains? names k)) (not (secretName? k)))))
              (envList))))

fn quoteArgv argv: (List String) -> String
  (stringJoin argv " ")

fn ! readChunk fd: Int64 isOpen: Bool -> (Pair Bool String)
  (if (not isOpen) (pair false "")
    (match (fdRead fd 65536)
      ((ok chunk) (if (stringEmpty? chunk) (let [(_ (fdClose fd))] (pair false "")) (pair true chunk)))
      ((err _) (pair true ""))))

fn limits timeoutS: Int64 maxDesc: Int64 -> Limits
  (Limits :timeoutMs (* timeoutS 1000) :maxDesc maxDesc)

fn defaultLimits -> Limits
  (limits 1800 64)

fn psRow acc: (List (Pair Int64 Int64)) line: String -> (List (Pair Int64 Int64))
  (let [(ws (filter (fn [(w String)] -> Bool (not (stringEmpty? w))) (stringSplit (stringTrim line) " ")))
        (stat (optionOr (listGet ws 2) ""))]
    (if (stringStartsWith? stat "Z")
      acc
      (match (stringToInt64 (optionOr (listGet ws 0) ""))
        ((none) acc)
        ((some pid) (match (stringToInt64 (optionOr (listGet ws 1) ""))
                      ((none) acc)
                      ((some ppid) (cons (pair pid ppid) acc)))))))

fn psPairs text: String -> (List (Pair Int64 Int64))
  (fold psRow (list) (stringLines text))

fn childMap pairs: (List (Pair Int64 Int64)) -> (Map Int64 (List Int64))
  (fold (fn [(m (Map Int64 (List Int64))) (p (Pair Int64 Int64))] -> (Map Int64 (List Int64))
          (mapSet m (pairSecond p) (cons (pairFirst p) (optionOr (mapGet m (pairSecond p)) (list)))))
        (mapEmpty) pairs)

fn walkDesc m: (Map Int64 (List Int64)) frontier: (List Int64) acc: (List Int64) -> (List Int64)
  (if (or (listEmpty? frontier) (> (listLength acc) 100000))
    acc
    (let [(next (fold (fn [(a (List Int64)) (p Int64)] -> (List Int64) (listAppend a (optionOr (mapGet m p) (list)))) (list) frontier))]
      (walkDesc m next (listAppend acc next))))

fn descendantsOf pairs: (List (Pair Int64 Int64)) root: Int64 -> (List Int64)
  (walkDesc (childMap pairs) (list root) (list))

fn ! shellOut cmd: String timeoutMs: Int64 -> (Result String String)
  (match (processSpawn cmd)
    ((err e) (err (str "spawn failed: " e)))
    ((ok h) (match (processWait h timeoutMs)
              ((err e) (err (str "wait failed: " e)))
              ((ok o) (if (= o.exitCode 0) (ok o.stdout) (err (str "exit " o.exitCode ": " (stringTrim o.stderr))))))))

; (:m :ref NODE2-SIGSTOP-RC :do "a user manager (comm systemd) or an sshd process is never a snapshot row, so no tree killer can reach it or walk through it")
fn guardedComm? comm: String -> Bool
  (let [(base (optionOr (listLast (stringSplit comm "/")) comm))]
    (or (= base "systemd") (stringStartsWith? base "sshd")))

; (:m :ref KILL-SETSID-ESCAPEE :do "ps etime ([[dd-]hh:]mm:ss, the only elapsed-time column both procps and BSD ps print) as seconds; anything else is -1, unknown")
fn etimeSeconds text: String -> Int64
  (let [(dayParts (stringSplit text "-"))
        (days (if (= (listLength dayParts) 2) (optionOr (stringToInt64 (optionOr (listHead dayParts) "")) -1) 0))
        (clock (stringSplit (optionOr (listLast dayParts) "") ":"))
        (nums (map (fn [(c String)] -> Int64 (optionOr (stringToInt64 c) -1)) clock))]
    (if (or (stringEmpty? text) (or (> (listLength dayParts) 2) (or (< days 0) (or (< (listLength nums) 2) (or (> (listLength nums) 3) (listAny? (fn [(n Int64)] -> Bool (< n 0)) nums))))))
      -1
      (+ (* days 86400) (fold (fn [(acc Int64) (n Int64)] -> Int64 (+ (* acc 60) n)) 0 nums))))

fn procRow acc: (List Proc) line: String -> (List Proc)
  (let [(ws (filter (fn [(w String)] -> Bool (not (stringEmpty? w))) (stringSplit (stringTrim line) " ")))
        (stat (optionOr (listGet ws 3) ""))
        (num (fn [(i Int64)] -> Int64 (optionOr (stringToInt64 (optionOr (listGet ws i) "")) -1)))]
    (if (or (stringStartsWith? stat "Z") (or (guardedComm? (optionOr (listGet ws 5) "")) (or (< (num 0) 1) (or (< (num 1) 0) (< (num 2) 0)))))
      acc
      (cons (Proc :pid (num 0) :ppid (num 1) :pgid (num 2) :age (etimeSeconds (optionOr (listGet ws 4) ""))) acc)))

fn procsOf text: String -> (List Proc)
  (fold procRow (list) (stringLines text))

; (:m :ref KILL-SETSID-ESCAPEE :do "rows of a ps text taken at nowSec: born is nowSec minus etime, -1 when etime is unknown; the snapshot uses the wall clock, a test passes its own")
fn procsAt text: String nowSec: Int64 -> (List Proc)
  (map (fn [(p Proc)] -> Proc (Proc :pid p.pid :ppid p.ppid :pgid p.pgid :age p.age :born (if (< p.age 0) -1 (- nowSec p.age)))) (procsOf text))

fn pinBase -> Int64
  8388608

; (:m :ref KILL-SETSID-ESCAPEE :do "a known entry is a bare pid or a pin, born * 2^23 + pid, recorded when the pid was seen in the tree; pids stay below 2^23 on Linux and macOS")
; (:m :ref PIN-PID-BITS :do "a pid outside 1..2^23-1 stays bare, so it can never decode as another pid; Linux caps pid_max at 2^22 (PID_MAX_LIMIT) and macOS pids stay below 100000, so no live pid is left unpinned")
fn pinOf pid: Int64 born: Int64 -> Int64
  (if (or (< born 0) (or (< pid 1) (>= pid (pinBase)))) pid (+ (* born (pinBase)) pid))

fn pinPid k: Int64 -> Int64
  (- k (* (/ k (pinBase)) (pinBase)))

fn pinBorn k: Int64 -> Int64
  (/ k (pinBase))

fn pinsOf procs: (List Proc) pids: (List Int64) -> (List Int64)
  (map (fn [(pid Int64)] -> Int64 (match (listHead (filter (fn [(p Proc)] -> Bool (= p.pid pid)) procs)) ((some p) (pinOf pid p.born)) ((none) pid))) pids)

fn knownPid? known: (List Int64) pid: Int64 -> Bool
  (listAny? (fn [(k Int64)] -> Bool (= (pinPid k) pid)) known)

; (:m :ref KILL-SETSID-ESCAPEE :do "g is the very process that was recorded: a pin for g whose birth matches g's current birth within 2 s; a reused pid has a later birth and a bare pid never matches")
fn pinnedLive? procs: (List Proc) known: (List Int64) g: Int64 -> Bool
  (match (listHead (filter (fn [(p Proc)] -> Bool (= p.pid g)) procs))
    ((none) false)
    ((some p) (and (>= p.born 0) (listAny? (fn [(k Int64)] -> Bool (and (= (pinPid k) g) (and (> (pinBorn k) 0) (and (<= (- (pinBorn k) p.born) 2) (>= (- (pinBorn k) p.born) -2))))) known))))

fn ! procSnapshot -> (List Proc)
  (procsAt (resultOr (shellOut "ps -A -o pid= -o ppid= -o pgid= -o stat= -o etime= -o comm=" 10000) "") (/ (nowNs) 1000000000))

fn ! psSnapshot -> (List (Pair Int64 Int64))
  (map (fn [(p Proc)] -> (Pair Int64 Int64) (pair p.pid p.ppid)) (procSnapshot))

fn addNew xs: (List Int64) ys: (List Int64) -> (List Int64)
  (fold (fn [(acc (List Int64)) (y Int64)] -> (List Int64) (if (listContains? acc y) acc (cons y acc))) xs ys)

fn ownGroup procs: (List Proc) self: Int64 -> Int64
  (match (listHead (filter (fn [(p Proc)] -> Bool (= p.pid self)) procs)) ((some p) p.pgid) ((none) -1))

fn lineageUp procs: (List Proc) pid: Int64 acc: (List Int64) -> (List Int64)
  (if (or (<= pid 1) (or (listContains? acc pid) (> (listLength acc) 512)))
    acc
    (match (listHead (filter (fn [(p Proc)] -> Bool (= p.pid pid)) procs))
      ((some p) (lineageUp procs p.ppid (cons pid acc)))
      ((none) (cons pid acc))))

; (:m :ref NODE2-SIGSTOP-RC :do "the fence of a killer: itself and every ancestor up to init, and the groups they are in; no tree walk adds a fenced pid or group, so a killer never stops itself, its parent chain or a group one of them sits in")
fn fenceOf procs: (List Proc) self: Int64 -> (Pair (List Int64) (List Int64))
  (let [(up (lineageUp procs self (list)))]
    (pair up (map (fn [(p Proc)] -> Int64 p.pgid) (filter (fn [(p Proc)] -> Bool (listContains? up p.pid)) procs))))

fn fenced? procs: (List Proc) root: Int64 self: Int64 -> Bool
  (or (<= root 1) (listContains? (pairFirst (fenceOf procs self)) root))

fn leaderGone? procs: (List Proc) g: Int64 -> Bool
  (listEmpty? (filter (fn [(p Proc)] -> Bool (= p.pid g)) procs))

; (:m :ref KILL-SETSID-ESCAPEE :do "g started no earlier than the root (ps etime, 1 s resolution): a known pid that setsid away from the job is younger than the job, a foreign process that ended up in known is older; unknown ages never qualify")
fn bornAfter? procs: (List Proc) root: Int64 g: Int64 -> Bool
  (let [(ageOf (fn [(pid Int64)] -> Int64 (match (listHead (filter (fn [(p Proc)] -> Bool (= p.pid pid)) procs)) ((some p) p.age) ((none) -1))))
        (rootAge (ageOf root))
        (age (ageOf g))]
    (and (>= rootAge 0) (and (>= age 0) (<= age rootAge))))

; (:m :ref NODE2-SIGSTOP-RC :do "a member's group joins the tree only when its leader is a member, or was one (known) and is gone or started no earlier than the root (bornAfter?): a member sitting in a foreign group no longer pulls that whole group, and everything hanging off it, into the kill")
fn treeStep procs: (List Proc) root: Int64 members: (List Int64) groups: (List Int64) known: (List Int64) fence: (Pair (List Int64) (List Int64)) rounds: Int64 -> (Pair (List Int64) (List Int64))
  (let [(adopt (fn [(g Int64)] -> Bool (and (> g 1) (and (not (listContains? (pairSecond fence) g)) (or (listContains? members g) (or (and (knownPid? known g) (leaderGone? procs g)) (and (pinnedLive? procs known g) (bornAfter? procs root g))))))))
        (gs (addNew groups (filter adopt (map (fn [(p Proc)] -> Int64 p.pgid) (filter (fn [(p Proc)] -> Bool (listContains? members p.pid)) procs)))))
        (more (map (fn [(p Proc)] -> Int64 p.pid)
                   (filter (fn [(p Proc)] -> Bool (and (> p.pid 1)
                                                       (and (not (listContains? (pairFirst fence) p.pid))
                                                            (and (not (listContains? members p.pid))
                                                                 (or (listContains? members p.ppid) (listContains? gs p.pgid))))))
                           procs)))]
    (if (or (listEmpty? more) (<= rounds 0))
      (pair members gs)
      (treeStep procs root (addNew members more) gs known fence (- rounds 1))))

; (:m :ref NODE2-SIGSTOP-RC :do "a remembered group stays only when a known pid still holds it (an orphan of init or a child in the lineage, or a pinned pid whose birth still matches: an orphan a subreaper such as systemd --user adopted has a ppid that is neither 1 nor in the lineage) and its leader is gone, in the lineage, or known and started no earlier than the root (a setsid escapee); a live leader older than the root (a foreign sleeper or a user manager that ended up in known) never anchors its group")
fn anchoredGroups procs: (List Proc) root: Int64 groups: (List Int64) known: (List Int64) lineage: (List Int64) -> (List Int64)
  (let [(anchors (filter (fn [(p Proc)] -> Bool (and (knownPid? known p.pid) (or (= p.ppid 1) (or (listContains? lineage p.ppid) (pinnedLive? procs known p.pid))))) procs))
        (held (map (fn [(p Proc)] -> Int64 p.pgid) anchors))
        (ours (fn [(g Int64)] -> Bool (or (listContains? lineage g) (or (leaderGone? procs g) (and (pinnedLive? procs known g) (bornAfter? procs root g))))))]
    (filter (fn [(g Int64)] -> Bool (or (= g root) (and (listContains? held g) (ours g)))) groups))

; (:m :ref NODE2-SIGSTOP-RC :do "self is the killer's pid: a root of 0 or 1 (every process descends from them; a failed pid parse once froze all of node2's user processes) or a root in the killer's fence gives an empty tree")
fn treeOf procs: (List Proc) root: Int64 groups: (List Int64) known: (List Int64) self: Int64 -> (Pair (List Int64) (List Int64))
  (let [(fence (fenceOf procs self))]
    (if (fenced? procs root self)
      (pair (list) (list))
      (let [(lineage (cons root (filter (fn [(p Int64)] -> Bool (not (listContains? (pairFirst fence) p))) (descendantsOf (map (fn [(p Proc)] -> (Pair Int64 Int64) (pair p.pid p.ppid)) procs) root))))
            (start (filter (fn [(g Int64)] -> Bool (and (> g 1) (not (listContains? (pairSecond fence) g)))) (addNew (anchoredGroups procs root groups known lineage) (list root))))
            (seed (cons root (map (fn [(p Proc)] -> Int64 p.pid) (filter (fn [(p Proc)] -> Bool (and (> p.pid 1) (and (!= p.pid root) (and (not (listContains? (pairFirst fence) p.pid)) (listContains? start p.pgid))))) procs))))
            (t (treeStep procs root seed start known fence 10000))]
        (pair (filter (fn [(p Int64)] -> Bool (!= p root)) (pairFirst t)) (pairSecond t)))))

fn ! signalAll pids: (List Int64) sig: String -> Int64
  (fold (fn [(n Int64) (p Int64)] -> Int64 (match (procKill p sig) ((ok _) (+ n 1)) ((err _) n))) 0 pids)

fn ! signalGroups groups: (List Int64) sig: String -> Int64
  (signalAll (map (fn [(g Int64)] -> Int64 (- 0 g)) (filter (fn [(g Int64)] -> Bool (> g 1)) groups)) sig)

fn ! freeze! root: Int64 seen: (List Int64) groups: (List Int64) known: (List Int64) rounds: Int64 -> (Pair (List Int64) (List Int64))
  (let [(snap (procSnapshot))
        (t (treeOf snap root groups (addNew known seen) (procSelf)))
        (gs (pairSecond t))
        (now (cons root (pairFirst t)))
        (fresh (filter (fn [(p Int64)] -> Bool (not (listContains? seen p))) now))
        (_ (signalGroups gs "SIGSTOP"))
        (_ (signalAll fresh "SIGSTOP"))]
    (if (or (listEmpty? fresh) (<= rounds 0))
      (pair (addNew seen fresh) gs)
      (freeze! root (addNew seen fresh) gs known (- rounds 1))))

; (:m :ref NODE2-SIGSTOP-RC :do "a fenced root signals nothing; otherwise every pid and group a freeze stopped gets SIGKILL in the same round, and the killer is never among them")
fn ! killRounds root: Int64 groups: (List Int64) known: (List Int64) rounds: Int64 -> Int64
  (if (fenced? (procSnapshot) root (procSelf))
    0
    (let [(frozen (freeze! root (list) groups known 20))
          (gs (pairSecond frozen))
          (_ (signalGroups gs "SIGKILL"))
          (_ (signalAll (pairFirst frozen) "SIGKILL"))
          (_ (sleepMs 50))
          (snap (procSnapshot))
          (left (pairFirst (treeOf snap root gs (addNew known (pairFirst frozen)) (procSelf))))]
      (if (or (listEmpty? left) (<= rounds 0))
        (listLength left)
        (killRounds root gs (addNew known (pairFirst frozen)) (- rounds 1)))))

fn ! killTreeWith! root: Int64 groups: (List Int64) known: (List Int64) -> Int64
  (killRounds root groups known 5)

fn ! killTree! root: Int64 -> Int64
  (killTreeWith! root (list) (list))

fn ! pumpOne r: Running -> (Pair Bool Running)
  (let [(o (readChunk r.outFd r.outOpen))
        (e (readChunk r.errFd r.errOpen))
        (got (str (pairSecond o) (pairSecond e)))]
    (pair (not (stringEmpty? got))
          (Running :idx r.idx :pid r.pid :outFd r.outFd :errFd r.errFd :text (str r.text got)
                   :outOpen (pairFirst o) :errOpen (pairFirst e) :startNs r.startNs :killed r.killed :groups r.groups :known r.known)))

; (:m :ref BUILD-DETACHED-ESCAPE :do "a run whose Limits names an owner pid ends, tree and all, at the first check after that owner is gone: a killed bin/asl left its cold aslNativeBuild orphaned under init spawning -O2 clang parts of ~1.2 GB each (node2, 2026-10-31)")
fn ! judge lim: Limits now: Int64 snap: (List Proc) self: Int64 checked: Bool r: Running -> Running
  (let [(overTime (and (> lim.timeoutMs 0) (> (/ (- now r.startNs) 1000000) lim.timeoutMs)))
        (tree (if checked (treeOf snap r.pid r.groups r.known self) (pair (list) r.groups)))
        (groups (pairSecond tree))
        (known (if checked (addNew r.known (pinsOf snap (pairFirst tree))) r.known))
        (descN (if (and checked (> lim.maxDesc 0)) (listLength (pairFirst tree)) 0))
        (ownerGone (and checked (and (> lim.owner 1) (not (resultOr (procAlive? lim.owner) false)))))
        (verdict (cond (overTime "timeout") ((> descN lim.maxDesc) "runaway") (ownerGone "owner-gone") (else "")))]
    (if (stringEmpty? verdict)
      (Running :idx r.idx :pid r.pid :outFd r.outFd :errFd r.errFd :text r.text
               :outOpen r.outOpen :errOpen r.errOpen :startNs r.startNs :killed r.killed :groups groups :known known)
      (let [(left (killTreeWith! r.pid groups known))
            (note (str "\n(:fleetRun :verdict :" verdict " :pid " r.pid " :desc " descN " :timeoutMs " lim.timeoutMs " :maxDesc " lim.maxDesc " :left " left ")\n"))]
        (Running :idx r.idx :pid r.pid :outFd r.outFd :errFd r.errFd :text (str r.text note)
                 :outOpen r.outOpen :errOpen r.errOpen :startNs r.startNs :killed verdict :groups groups :known known))))

fn ! closeIfOpen fd: Int64 isOpen: Bool -> Int64
  (if isOpen (do (fdClose fd) 1) 0)

fn killedExit verdict: String -> Int64
  (if (= verdict "timeout") 124 125)

fn ! finish r: Running -> Done
  (let [(_ (closeIfOpen r.outFd r.outOpen))
        (_ (closeIfOpen r.errFd r.errOpen))
        (code (match (procWaitPid r.pid false) ((ok status) (optionOr status 1)) ((err _) 1)))
        (killed (not (stringEmpty? r.killed)))]
    (Done :idx r.idx :exit (if killed (killedExit r.killed) code) :out r.text :ms (/ (- (monotonicNs) r.startNs) 1000000)
          :verdict (if killed r.killed "exit")))

fn ! spawn idx: Int64 j: Job -> (Result Running Done)
  (let [(start (monotonicNs))]
    (match (procSpawnv (listAppend (list "nice" "-n" "15") j.argv) (some j.cwd) (some (withPwd j.cwd j.env)))
      ((err e) (err (Done :idx idx :exit 127 :out (str "spawn failed: " (quoteArgv j.argv) ": " e) :ms 0 :verdict "spawnFailed")))
      ((ok p) (let [(_ (fdClose p.stdin)) (_ (fdNonBlocking p.stdout true)) (_ (fdNonBlocking p.stderr true))]
                (ok (Running :idx idx :pid p.pid :outFd p.stdout :errFd p.stderr :text "" :outOpen true :errOpen true :startNs start :killed "" :groups (list p.pid) :known (list)))))))

fn openFds rs: (List Running) -> (List (Pair Int64 Int64))
  (fold (fn [(acc (List (Pair Int64 Int64))) (r Running)] -> (List (Pair Int64 Int64))
          (listAppend acc (listAppend (if r.outOpen (list (pair r.outFd 1)) (list)) (if r.errOpen (list (pair r.errFd 1)) (list)))))
        (list) rs)

fn checkEveryNs -> Int64
  250000000

fn ! poolLoop jobs: (List Job) next: Int64 slots: Int64 lim: Limits running: (List Running) done: (List Done) lastCheck: Int64 admit: (fn [Int64] -> Bool) onDone: (fn [S Done] -> S) state: S -> (Pair (List Done) S)
  (if (and (< (listLength running) slots) (< next (listLength jobs)))
    (if (not (admit next))
      (poolLoop jobs (listLength jobs) slots lim running done lastCheck admit onDone state)
      (match (spawn next (optionOr (listGet jobs next) (job (list) "." (list))))
        ((err d) (poolLoop jobs (+ next 1) slots lim running (cons d done) lastCheck admit onDone (onDone state d)))
        ((ok r) (poolLoop jobs (+ next 1) slots lim (listAppend running (list r)) done lastCheck admit onDone state))))
    (if (listEmpty? running)
      (pair (listSortBy (fn [(d Done)] -> Int64 d.idx) done) state)
      (let [(pumped (map pumpOne running))
            (progress (fold (fn [(acc Bool) (p (Pair Bool Running))] -> Bool (or acc (pairFirst p))) false pumped))
            (now (monotonicNs))
            (checked (and (> lim.maxDesc 0) (>= (- now lastCheck) (checkEveryNs))))
            (snap (if checked (procSnapshot) (list)))
            (self (if checked (procSelf) -1))
            (states (map (fn [(r Running)] -> Running (judge lim now snap self checked r)) (map pairSecond pumped)))
            (over? (fn [(r Running)] -> Bool (or (not (stringEmpty? r.killed)) (and (not r.outOpen) (not r.errOpen)))))
            (closed (filter over? states))
            (still (filter (fn [(r Running)] -> Bool (not (over? r))) states))
            (finished (map finish closed))
            (nextState (fold onDone state finished))]
        (do (if (and (not progress) (listEmpty? closed)) (let [(_ (fdPoll (openFds still) 50))] ()) ())
            (poolLoop jobs next slots lim still (listAppend finished done) (if checked now lastCheck) admit onDone nextState)))))

fn ! runPoolLimited jobs: (List Job) slots: Int64 lim: Limits -> (List Done)
  (pairFirst (poolLoop jobs 0 (if (< slots 1) 1 slots) lim (list) (list) 0 (fn [(i Int64)] -> Bool true) (fn [(n Int64) (d Done)] -> Int64 (+ n 1)) 0))

fn ! runPoolEach jobs: (List Job) slots: Int64 lim: Limits admit: (fn [Int64] -> Bool) onDone: (fn [S Done] -> S) state: S -> (Pair (List Done) S)
  (poolLoop jobs 0 (if (< slots 1) 1 slots) lim (list) (list) 0 admit onDone state)

fn ! runPool jobs: (List Job) slots: Int64 -> (List Done)
  (runPoolLimited jobs slots (defaultLimits))

fn ! runOneLimited j: Job lim: Limits -> Done
  (optionOr (listHead (runPoolLimited (list j) 1 lim)) (Done :idx 0 :exit 127 :out "no result" :ms 0 :verdict "spawnFailed"))

fn ! runOne j: Job -> Done
  (runOneLimited j (defaultLimits))

fn numberBefore text: String marker: String -> (Option Int64)
  (let [(parts (stringSplit text marker))]
    (if (< (listLength parts) 2) (none)
      (let [(before (optionOr (listGet parts (- (listLength parts) 2)) ""))
            (words (stringSplit (stringTrim before) " "))]
        (stringToInt64 (stringReplace (optionOr (listLast words) "") "(" "")))))

fn executedOf text: String -> (Option Int64)
  (let [(lines (filter (fn [(l String)] -> Bool (or (stringContains? l " assertion(s) executed") (stringStartsWith? l "FAIL "))) (stringLines text)))]
    (match (listLast lines)
      ((none) (none))
      ((some l) (if (stringStartsWith? l "FAIL ")
                  (match (numberBefore text " asserts)") ((some n) (some n)) ((none) (some 0)))
                  (numberBefore l " passed)")))))

fn errorLinesOf text: String -> (List String)
  (fold (fn [(acc (List String)) (l String)] -> (List String)
          (let [(at (stringSplit l ": ERR_"))]
            (if (and (>= (listLength at) 2) (not (stringStartsWith? l "FAIL ")))
              (listAppend acc (list (str "ERR_" (stringJoin (optionOr (listTail at) (list)) ": ERR_"))))
              acc)))
        (list) (stringLines text))

fn withPwd cwd: String env: (List String) -> (List String)
  (if (stringStartsWith? cwd "/")
    (cons (str "PWD=" cwd) (filter (fn [(row String)] -> Bool (not (stringStartsWith? row "PWD="))) env))
    (filter (fn [(row String)] -> Bool (not (stringStartsWith? row "PWD="))) env))
