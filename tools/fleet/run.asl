(module asl-tools/fleet/run
  :x [Job Done Limits Proc ProcOut Running RunningSep Lease job limits defaultLimits runPool runPoolLimited runPoolEach runOne runOneLimited runShell! runGuarded Guarded GuardStep guardStart! guardAdvance! guardFds spawn spawnSep reapStaleLeases! leaseDir leasePath writeLease! psPairs descendantsOf psSnapshot procsOf procSnapshot treeOf killTree! ownGroup shellOut childEnv secretName? executedOf errorLinesOf builtBinary! nativeCliPath! nativeCli! nativeCliFor legacyHost! sideEnv quoteArgv]
  :i [])

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
  (:f maxDesc Int64))

(schema Proc
  (:f pid Int64)
  (:f ppid Int64)
  (:f pgid Int64))

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

; (:m :ref ORPHAN-EVAL-ESCAPE :do "the ProcOut shape asl/tools/nativeTest.asl's runProc/runProcIn already returns, kept separate here so a bounded guarded spawn can hand it straight back without that file importing a Running it does not need")
(schema ProcOut
  (:f exitCode Int64)
  (:f stdout String)
  (:f stderr String))

(schema RunningSep
  (:f pid Int64)
  (:f outFd Int64)
  (:f errFd Int64)
  (:f outText String)
  (:f errText String)
  (:f outOpen Bool)
  (:f errOpen Bool)
  (:f startNs Int64)
  (:f killed String)
  (:f groups (List Int64))
  (:f known (List Int64)))

; (:m :ref ORPHAN-EVAL-ESCAPE :do "a row-keyed lease (by pgid) under ~/.asl/run/fleet/leases, per the ledger/coordination rules: no extra watchdog process and no shell script in the tree (D157, spawnSafety), just a record a later runGuarded call can find and act on")
(schema Lease
  (:f pgid Int64)
  (:f ownerPid Int64)
  (:f startNs Int64)
  (:f deadlineNs Int64))

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

; (:m :ref HL-FIXWAVE :do "HL-DELETE retired asl/host/out/asl-host for good: builtBinary! used to fall back to it whenever bin/asl was present but not yet proven fresh (avoiding every parallel caller tripping bin/asl's rebuild lock at once); there is no longer a second, always-ready binary to fall back to, so the only honest answer is bin/asl itself (fresh or not -- bin/asl's own lock protocol already serializes concurrent rebuilders) or nothing")
fn ! builtBinary! root: String -> (Option String)
  (let [(cli (str root "/bin/asl"))] (if (fileExists? cli) (some (resultOr (realPath cli) cli)) (none)))

fn ! nativeCliPath! -> (Result String String)
  (let [(override (optionOr (envGet "ASL_NATIVE_CLI") ""))
        (root (optionOr (envGet "ASL_ROOT") "."))]
    (if (not (stringEmpty? override)) (ok (resultOr (realPath override) override))
      (match (builtBinary! root)
        ((some p) (ok p))
        ((none) (err (str "no native CLI at " root
                          "/bin/asl (there is no host to fall back to since HL-DELETE); build it with sh " root "/asl/host/build.sh; set ASL_NATIVE_CLI to override (the running executable is never the CLI)"))))))

fn ! nativeCli! -> String
  (match (nativeCliPath!)
    ((ok h) h)
    ((err e) (do (eprintln (str "fleet: " e)) "native-cli-not-found")))

fn ! legacyHost! -> String
  (nativeCli!)

fn ! nativeCliFor side: String -> String
  (optionOr (builtBinary! side) (nativeCli!))

fn ! sideEnv side: String -> (List String)
  (let [(prelude (str side "/asl/prelude/prelude.asl"))]
    (childEnv (if (fileExists? prelude)
                (list (str "ASL_ROOT=" side) (str "ASL_PRELUDE=" prelude))
                (list (str "ASL_ROOT=" side)))))

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

fn procRow acc: (List Proc) line: String -> (List Proc)
  (let [(ws (filter (fn [(w String)] -> Bool (not (stringEmpty? w))) (stringSplit (stringTrim line) " ")))
        (stat (optionOr (listGet ws 3) ""))
        (num (fn [(i Int64)] -> Int64 (optionOr (stringToInt64 (optionOr (listGet ws i) "")) -1)))]
    (if (or (stringStartsWith? stat "Z") (or (< (num 0) 1) (or (< (num 1) 0) (< (num 2) 0))))
      acc
      (cons (Proc :pid (num 0) :ppid (num 1) :pgid (num 2)) acc)))

fn procsOf text: String -> (List Proc)
  (fold procRow (list) (stringLines text))

fn ! procSnapshot -> (List Proc)
  (procsOf (resultOr (shellOut "ps -A -o pid= -o ppid= -o pgid= -o stat=" 10000) ""))

fn ! psSnapshot -> (List (Pair Int64 Int64))
  (map (fn [(p Proc)] -> (Pair Int64 Int64) (pair p.pid p.ppid)) (procSnapshot))

fn addNew xs: (List Int64) ys: (List Int64) -> (List Int64)
  (fold (fn [(acc (List Int64)) (y Int64)] -> (List Int64) (if (listContains? acc y) acc (cons y acc))) xs ys)

fn ownGroup procs: (List Proc) self: Int64 -> Int64
  (match (listHead (filter (fn [(p Proc)] -> Bool (= p.pid self)) procs)) ((some p) p.pgid) ((none) -1))

fn treeStep procs: (List Proc) members: (List Int64) groups: (List Int64) own: Int64 rounds: Int64 -> (Pair (List Int64) (List Int64))
  (let [(gs (addNew groups (filter (fn [(g Int64)] -> Bool (and (> g 1) (!= g own)))
                                   (map (fn [(p Proc)] -> Int64 p.pgid) (filter (fn [(p Proc)] -> Bool (listContains? members p.pid)) procs)))))
        (more (map (fn [(p Proc)] -> Int64 p.pid)
                   (filter (fn [(p Proc)] -> Bool (and (not (listContains? members p.pid))
                                                       (or (listContains? members p.ppid) (listContains? gs p.pgid))))
                           procs)))]
    (if (or (listEmpty? more) (<= rounds 0))
      (pair members gs)
      (treeStep procs (addNew members more) gs own (- rounds 1))))

fn anchoredGroups procs: (List Proc) root: Int64 groups: (List Int64) known: (List Int64) -> (List Int64)
  (let [(lineage (cons root (descendantsOf (map (fn [(p Proc)] -> (Pair Int64 Int64) (pair p.pid p.ppid)) procs) root)))
        (anchors (filter (fn [(p Proc)] -> Bool (and (listContains? known p.pid) (or (= p.ppid 1) (listContains? lineage p.ppid)))) procs))
        (held (map (fn [(p Proc)] -> Int64 p.pgid) anchors))]
    (filter (fn [(g Int64)] -> Bool (or (= g root) (listContains? held g))) groups))

fn treeOf procs: (List Proc) root: Int64 groups: (List Int64) known: (List Int64) own: Int64 -> (Pair (List Int64) (List Int64))
  (let [(start (filter (fn [(g Int64)] -> Bool (and (> g 1) (!= g own))) (addNew (anchoredGroups procs root groups known) (list root))))
        (seed (cons root (map (fn [(p Proc)] -> Int64 p.pid) (filter (fn [(p Proc)] -> Bool (and (!= p.pid root) (listContains? start p.pgid))) procs))))
        (t (treeStep procs seed start own 10000))]
    (pair (filter (fn [(p Int64)] -> Bool (!= p root)) (pairFirst t)) (pairSecond t)))

fn ! signalAll pids: (List Int64) sig: String -> Int64
  (fold (fn [(n Int64) (p Int64)] -> Int64 (match (procKill p sig) ((ok _) (+ n 1)) ((err _) n))) 0 pids)

fn ! signalGroups groups: (List Int64) sig: String -> Int64
  (signalAll (map (fn [(g Int64)] -> Int64 (- 0 g)) (filter (fn [(g Int64)] -> Bool (> g 1)) groups)) sig)

fn ! freeze! root: Int64 seen: (List Int64) groups: (List Int64) known: (List Int64) rounds: Int64 -> (Pair (List Int64) (List Int64))
  (let [(snap (procSnapshot))
        (t (treeOf snap root groups (addNew known seen) (ownGroup snap (procSelf))))
        (gs (pairSecond t))
        (now (cons root (pairFirst t)))
        (fresh (filter (fn [(p Int64)] -> Bool (not (listContains? seen p))) now))
        (_ (signalGroups gs "SIGSTOP"))
        (_ (signalAll fresh "SIGSTOP"))]
    (if (or (listEmpty? fresh) (<= rounds 0))
      (pair (addNew seen fresh) gs)
      (freeze! root (addNew seen fresh) gs known (- rounds 1))))

fn ! killRounds root: Int64 groups: (List Int64) known: (List Int64) rounds: Int64 -> Int64
  (let [(frozen (freeze! root (list) groups known 20))
        (gs (pairSecond frozen))
        (_ (signalGroups gs "SIGKILL"))
        (_ (signalAll (pairFirst frozen) "SIGKILL"))
        (_ (sleepMs 50))
        (snap (procSnapshot))
        (left (pairFirst (treeOf snap root gs (addNew known (pairFirst frozen)) (ownGroup snap (procSelf)))))]
    (if (or (listEmpty? left) (<= rounds 0))
      (listLength left)
      (killRounds root gs (addNew known (pairFirst frozen)) (- rounds 1))))

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

fn ! judge lim: Limits now: Int64 snap: (List Proc) own: Int64 checked: Bool r: Running -> Running
  (let [(overTime (and (> lim.timeoutMs 0) (> (/ (- now r.startNs) 1000000) lim.timeoutMs)))
        (tree (if checked (treeOf snap r.pid r.groups r.known own) (pair (list) r.groups)))
        (groups (pairSecond tree))
        (known (if checked (pairFirst tree) r.known))
        (descN (if (and checked (> lim.maxDesc 0)) (listLength (pairFirst tree)) 0))
        (verdict (cond (overTime "timeout") ((> descN lim.maxDesc) "runaway") (else "")))]
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

; (:m :ref NOSELFHOST-RETRYCONC-20261017 :do "exported so a long-lived server/stub a test needs to interact with WHILE it runs (not just supervise start-to-finish like runOneLimited) still starts only through this module, per rule spawnSafety; the caller owns draining or redirecting Running's outFd/errFd (fr/spawn makes them non-blocking pipes, same as runOneLimited's own pool loop does) and must call killTree! on Running.pid at cleanup, never a bare procKill, so a verdict (or an explicit stop) takes the whole process tree, not just the one pid")
; (:m :ref TRAIN18-NOFOREIGN-20261018 :do "spawn no longer calls procSpawnv itself: spawnSep is the one process-spawning site in this file, and spawn builds on it (nice-prefixing its own argv first, same as before), converting the RunningSep it gets back into the Running shape poolLoop's pumpOne/judge/finish already consume (an empty text seed; pumpOne appends combined stdout+stderr into it a chunk at a time exactly as it already did when spawn held the pipes directly)")
fn ! spawn idx: Int64 j: Job -> (Result Running Done)
  (match (spawnSep (listAppend (list "nice" "-n" "15") j.argv) j.cwd j.env)
    ((err po) (err (Done :idx idx :exit po.exitCode :out po.stderr :ms 0 :verdict "spawnFailed")))
    ((ok r) (ok (Running :idx idx :pid r.pid :outFd r.outFd :errFd r.errFd :text "" :outOpen r.outOpen :errOpen r.errOpen :startNs r.startNs :killed r.killed :groups r.groups :known r.known))))

fn checkEveryNs -> Int64
  250000000

; (:m :ref ORPHAN-EVAL-ESCAPE :do "asl/tools/nativeTest.asl's runOne/evalExpression! spawn test and eval binaries via bare runProcIn: no timeout, no process-group tracking, no killTree, so a driver that dies or is killed mid-run leaves the child (and any grandchild it forked) running with ppid 1; runGuarded is the same bounded machinery runPool already proves (Limits timeout + maxDesc, own process group, killTreeWith! on verdict), kept with separate stdout/stderr since that is the ProcOut shape nativeTest consumes, plus a detached watchdog subprocess that kills the job's whole tree the moment the calling process itself is gone, which no in-process polling loop can detect about itself")
fn ! pumpOneSep r: RunningSep -> (Pair Bool RunningSep)
  (let [(o (readChunk r.outFd r.outOpen))
        (e (readChunk r.errFd r.errOpen))]
    (pair (or (not (stringEmpty? (pairSecond o))) (not (stringEmpty? (pairSecond e))))
          (RunningSep :pid r.pid :outFd r.outFd :errFd r.errFd
                      :outText (str r.outText (pairSecond o)) :errText (str r.errText (pairSecond e))
                      :outOpen (pairFirst o) :errOpen (pairFirst e)
                      :startNs r.startNs :killed r.killed :groups r.groups :known r.known)))

fn ! judgeSep lim: Limits now: Int64 snap: (List Proc) own: Int64 checked: Bool r: RunningSep -> RunningSep
  (let [(overTime (and (> lim.timeoutMs 0) (> (/ (- now r.startNs) 1000000) lim.timeoutMs)))
        (tree (if checked (treeOf snap r.pid r.groups r.known own) (pair (list) r.groups)))
        (groups (pairSecond tree))
        (known (if checked (pairFirst tree) r.known))
        (descN (if (and checked (> lim.maxDesc 0)) (listLength (pairFirst tree)) 0))
        (verdict (cond (overTime "timeout") ((> descN lim.maxDesc) "runaway") (else "")))]
    (if (stringEmpty? verdict)
      (RunningSep :pid r.pid :outFd r.outFd :errFd r.errFd :outText r.outText :errText r.errText
                  :outOpen r.outOpen :errOpen r.errOpen :startNs r.startNs :killed r.killed :groups groups :known known)
      (let [(left (killTreeWith! r.pid groups known))
            (note (str "\n(:fleetRun :verdict :" verdict " :pid " r.pid " :desc " descN " :timeoutMs " lim.timeoutMs " :maxDesc " lim.maxDesc " :left " left ")\n"))]
        (RunningSep :pid r.pid :outFd r.outFd :errFd r.errFd :outText r.outText :errText (str r.errText note)
                    :outOpen r.outOpen :errOpen r.errOpen :startNs r.startNs :killed verdict :groups groups :known known))))

fn ! finishSep r: RunningSep -> ProcOut
  (let [(_ (closeIfOpen r.outFd r.outOpen))
        (_ (closeIfOpen r.errFd r.errOpen))
        (code (match (procWaitPid r.pid false) ((ok status) (optionOr status 1)) ((err _) 1)))
        (killed (not (stringEmpty? r.killed)))]
    (ProcOut :exitCode (if killed (killedExit r.killed) code) :stdout r.outText :stderr r.errText))

fn ! spawnSep argv: (List String) cwd: String env: (List String) -> (Result RunningSep ProcOut)
  (let [(start (monotonicNs))]
    (match (procSpawnv argv (some cwd) (some (withPwd cwd env)))
      ((err e) (err (ProcOut :exitCode 127 :stdout "" :stderr (str "spawn failed: " (quoteArgv argv) ": " e))))
      ((ok p) (let [(_ (fdClose p.stdin)) (_ (fdNonBlocking p.stdout true)) (_ (fdNonBlocking p.stderr true))]
                (ok (RunningSep :pid p.pid :outFd p.stdout :errFd p.stderr :outText "" :errText ""
                      :outOpen true :errOpen true :startNs start :killed "" :groups (list p.pid) :known (list)))))))

; (:m :ref ORPHAN-EVAL-ESCAPE :do "a detached /bin/sh watchdog was rejected: D157 forbids shell in the tree, and a watchdog process is itself a child with no timeout/descendant-limit accounting through this file, exactly the escape spawnSafety forbids. Lease reaping replaces it: no extra process, no shell text, just a row-keyed record under ~/.asl/run/fleet/leases a later runGuarded call can find and act on")
fn ! leaseDir -> String
  (str (optionOr (envGet "HOME") "/tmp") "/.asl/run/fleet/leases")

fn ! leasePath pgid: Int64 -> String
  (str (leaseDir) "/" pgid ".asn")

fn ! fieldInt text: String key: String -> (Option Int64)
  (match (stringIndexOf text key)
    ((none) (none))
    ((some i) (let [(rest (stringTrim (optionOr (stringSlice text (+ i (stringLength key)) (stringLength text)) "")))
                    (tok (stringReplace (optionOr (listHead (stringSplit rest " ")) "") ")" ""))]
                (stringToInt64 tok))))

fn ! parseLease text: String -> Lease
  (Lease :pgid (optionOr (fieldInt text ":pgid ") 0)
         :ownerPid (optionOr (fieldInt text ":ownerPid ") 0)
         :startNs (optionOr (fieldInt text ":startNs ") 0)
         :deadlineNs (optionOr (fieldInt text ":deadlineNs ") 0))

fn ! writeLease! pgid: Int64 ownerPid: Int64 startNs: Int64 deadlineNs: Int64 -> Bool
  (and (ok? (dirCreate (leaseDir)))
       (ok? (fileWrite (leasePath pgid) (str "(:pgid " pgid " :ownerPid " ownerPid " :startNs " startNs " :deadlineNs " deadlineNs ")\n"))))

fn ! removeLease! pgid: Int64 -> Bool
  (ok? (pathRemove (leasePath pgid)))

; (:m :ref ORPHAN-EVAL-ESCAPE :do "a backstop deadline even with no caller-set timeout: spawnSafety forbids an unbounded lease, so an unset timeoutMs still gets a bounded (if generous) deadline rather than one that never expires")
fn ! leaseDeadline startNs: Int64 timeoutMs: Int64 -> Int64
  (+ startNs (* (if (> timeoutMs 0) timeoutMs 3600000) 1000000))

fn ! reapLeaseFile! now: Int64 alive: (List Int64) name: String -> Bool
  (let [(path (str (leaseDir) "/" name))
        (lease (parseLease (resultOr (fileReadString path) "")))
        (expired (and (> lease.deadlineNs 0) (> now lease.deadlineNs)))
        (ownerGone (not (listContains? alive lease.ownerPid)))]
    (if (and (> lease.pgid 0) (or ownerGone expired))
      (let [(_ (killTreeWith! lease.pgid (list lease.pgid) (list)))
            (_ (removeLease! lease.pgid))]
        true)
      false))

; (:m :ref ORPHAN-EVAL-ESCAPE :do "every runGuarded call reaps first: a caller that died mid-job left its lease behind with nothing watching it, so the next call anywhere is what finds and kills the orphaned tree")
fn ! reapStaleLeases! -> Int64
  (let [(now (monotonicNs))
        (alive (map (fn [(p Proc)] -> Int64 p.pid) (procSnapshot)))
        (names (resultOr (dirList (leaseDir)) (list)))]
    (fold (fn [(n Int64) (name String)] -> Int64 (if (reapLeaseFile! now alive name) (+ n 1) n)) 0 names))

; (:m :ref GW-SESSION-BIND :do "a guarded run a caller steps itself: guardStart! reaps stale leases, spawns and writes the lease; each guardAdvance! pumps output once and judges the limits, returning the ProcOut when the child has ended, so a single-threaded server can park the run and look at it between other work; guardFds is what to poll. guardLoop and runGuarded are this same step in a blocking loop")
(schema Guarded
  (:f run RunningSep)
  (:f lim Limits)
  (:f lastCheck Int64))

(schema GuardStep
  (:f out (Option ProcOut))
  (:f guard Guarded)
  (:f progress Bool))

fn ! guardStart! argv: (List String) cwd: String env: (List String) lim: Limits -> (Result Guarded ProcOut)
  (let [(_ (reapStaleLeases!))]
    (match (spawnSep argv cwd env)
      ((err d) (err d))
      ((ok r) (let [(_ (writeLease! r.pid (procSelf) r.startNs (leaseDeadline r.startNs lim.timeoutMs)))]
                (ok (Guarded :run r :lim lim :lastCheck 0))))))

fn guardFds g: Guarded -> (List (Pair Int64 Int64))
  (listAppend (if g.run.outOpen (list (pair g.run.outFd 1)) (list)) (if g.run.errOpen (list (pair g.run.errFd 1)) (list)))

fn ! guardAdvance! g: Guarded -> GuardStep
  (let [(lim g.lim)
        (pumped (pumpOneSep g.run))
        (progress (pairFirst pumped))
        (r1 (pairSecond pumped))
        (now (monotonicNs))
        (checked (and (> lim.maxDesc 0) (>= (- now g.lastCheck) (checkEveryNs))))
        (snap (if checked (procSnapshot) (list)))
        (own (if checked (ownGroup snap (procSelf)) -1))
        (r2 (judgeSep lim now snap own checked r1))
        (over? (or (not (stringEmpty? r2.killed)) (and (not r2.outOpen) (not r2.errOpen))))
        (g2 (Guarded :run r2 :lim lim :lastCheck (if checked now g.lastCheck)))]
    (if over?
      (let [(o (finishSep r2)) (_ (removeLease! r2.pid))]
        (GuardStep :out (some o) :guard g2 :progress progress))
      (GuardStep :out none :guard g2 :progress progress)))

fn ! guardLoop g: Guarded -> ProcOut
  (let [(s (guardAdvance! g))]
    (match s.out
      ((some o) o)
      ((none)
       (do (if (not s.progress)
             (fdPoll (guardFds s.guard) 50)
             (ok (list)))
           (guardLoop s.guard)))))

; (:m :ref ORPHAN-EVAL-ESCAPE :do "argv runs exactly as given, no auto-nice prefix: mirrors runProcIn's existing contract so nativeTest.asl's runOne/evalExpression! call sites (one of which already prefixes its own nice -n 15) can swap to this with no argv change")
fn ! runGuarded argv: (List String) cwd: String env: (List String) lim: Limits -> ProcOut
  (match (guardStart! argv cwd env lim)
    ((err d) d)
    ((ok g) (guardLoop g)))

fn openFds rs: (List Running) -> (List (Pair Int64 Int64))
  (fold (fn [(acc (List (Pair Int64 Int64))) (r Running)] -> (List (Pair Int64 Int64))
          (listAppend acc (listAppend (if r.outOpen (list (pair r.outFd 1)) (list)) (if r.errOpen (list (pair r.errFd 1)) (list)))))
        (list) rs)

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
            (own (if checked (ownGroup snap (procSelf)) -1))
            (states (map (fn [(r Running)] -> Running (judge lim now snap own checked r)) (map pairSecond pumped)))
            (over? (fn [(r Running)] -> Bool (or (not (stringEmpty? r.killed)) (and (not r.outOpen) (not r.errOpen)))))
            (closed (filter over? states))
            (still (filter (fn [(r Running)] -> Bool (not (over? r))) states))
            (finished (map finish closed))
            (nextState (fold onDone state finished))]
        ; (:m :ref RUNASL-POOLLOOP-FDPOLL-TYPE-20261017 :do "fix: the two if branches disagreed in type (fdPoll's own (Result (List (Pair Int64 Int64)) String) vs the else branch's bare Unit) -- a latent mismatch only a full native rebuild's whole-program check surfaces, not the normal incremental path; fdPoll's own result was always discarded here (it is called only to block until a socket is ready or the 50ms timeout passes, never consulted), so the true branch now discards it explicitly too, making both branches Unit with no change in runtime behavior")
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

; (:m :ref TRAIN18-NOFOREIGN-20261018 :do "the one place a (list \"sh\" \"-c\" cmd) argv literal is built for a caller that only has a command string, not an argv list already; freePool.asl's runGate! used to build this literal itself (a second textual sh -c site outside this file), this gives it (and any future command-string caller) the same single site runOneLimited's callers with an argv already in hand use")
fn ! runShell! cmd: String cwd: String env: (List String) lim: Limits -> Done
  (runOneLimited (job (list "sh" "-c" cmd) cwd env) lim)

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
