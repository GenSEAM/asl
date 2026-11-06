(module asl-tools/fleet/run
  :x [cacheEnv! cacheRows Job Done Limits Proc ProcOut Running RunningSep Lease Forked ForkEnd ForkStep forkLimited! forkAdvance! forkKill! job limits defaultLimits runPool runPoolLimited runPoolEach runOne runOneLimited heavy runShell! gateOut gateOutHost gateFiles stubHost! stubHostIn! stubHostPath stubHostFor! stubRemove! stubSweepDead! stubTrustedIn! stubDirsOwnedBy ownerPidOf stubPrefix stubVerifiedIn! privateDir? stubHostText runGuarded Guarded GuardStep guardStart! guardAdvance! guardLoop guardFds spawn spawnSep reapStaleLeases! reapLeasesIn! reapLeasesAt! leaseDir leasePath writeLease! writeLeaseAt! bornIn sameStart? psPairs descendantsOf psSnapshot procsOf procsAt pinOf pinsOf procSnapshot treeOf fenceOf fenced? killTree! killTreeWith! judge judgeSep fleetInt fleetGroupAt drainConfig! Drain drainFd stopGuard! ownGroup shellOut childEnv secretName? executedOf errorLinesOf builtBinary! nativeCliPath! nativeCli! nativeCliFor legacyHost! sideEnv quoteArgv]
  :i [(asl-tools/fleet/jobserver :a js)])

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
  (:f class String)
  (:f jsDir String))

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
  (:f known (List Int64))
  (:f tmp String :default ""))

; (:m :ref ORPHAN-EVAL-ESCAPE :do "the ProcOut shape asl/tools/nativeTest.asl's runProc/runProcIn already returns, kept separate here so a bounded guarded spawn can hand it straight back without that file importing a Running it does not need")
(schema ProcOut
  (:f exitCode Int64)
  (:f stdout String)
  (:f stderr String)
  (:f timedOut Bool :default false))

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
  (:f known (List Int64))
  (:f tmp String :default ""))

; (:m :ref ORPHAN-EVAL-ESCAPE :do "a row-keyed lease (by pgid) under ~/.asl/run/fleet/leases, per the ledger/coordination rules: no extra watchdog process and no shell script in the tree (D157, spawnSafety), just a record a later runGuarded call can find and act on")
(schema Lease
  (:f pgid Int64)
  (:f ownerPid Int64)
  (:f startNs Int64)
  (:f deadlineNs Int64)
  (:f wroteNs Int64)
  (:f pgidBorn Int64)
  (:f ownerBorn Int64))

fn job argv: (List String) cwd: String env: (List String) -> Job
  (Job :argv argv :cwd cwd :env env)

; (:m :ref GITCONFIG-GUARD :do "an inherited GIT_ variable reaches a child only when it names an identity, a transport or a prompt; GIT_DIR, GIT_WORK_TREE, GIT_INDEX_FILE, GIT_CONFIG_* and every other one is dropped, since a child that inherits them from a git hook or a fixture runs every git call against that repository (GIT_DIR=<main>/.git git init --bare set core.bare=true in the shared config); a caller that means one passes it as an override")
fn inheritedOk? name: String -> Bool
  (or (not (stringStartsWith? name "GIT_"))
      (listContains? (list "GIT_AUTHOR_NAME" "GIT_AUTHOR_EMAIL" "GIT_AUTHOR_DATE" "GIT_COMMITTER_NAME" "GIT_COMMITTER_EMAIL" "GIT_COMMITTER_DATE" "GIT_SSH" "GIT_SSH_COMMAND" "GIT_ASKPASS" "GIT_TERMINAL_PROMPT" "GIT_EDITOR" "GIT_PAGER") name))

fn secretName? name: String -> Bool
  (or (stringEndsWith? name "_API_KEY") (or (stringContains? name "TOKEN") (stringContains? name "SECRET")))

; (:m :ref CACHE-HOME-LEAK :do "the caches that key off HOME, each with its one override: a child started with another HOME (a test's temp home) reuses the shared caches only when it gets every row; ASL_CHECK_CACHE missing alone made a fresh-HOME vps.asl run 349894 ms against 4157 ms (node2, 2026-10-30). ASL_NATIVE_TEST_CACHE keys off HOME only in a linked worktree (nativeTest defaultCacheDirFor); the main checkout keeps .asl/cache/nativeTest, so the row is left out there unless set")
fn cacheRows -> (List (Pair String String))
  (list (pair "ASL_NATIVE_CLI_CACHE" "/.asl/run/nativeCli") (pair "ASL_HOST_CACHE_DIR" "/.asl/run/hosts") (pair "ASL_NATIVE_TEST_CACHE" "/.asl/run/nativeTest")
        (pair "ASL_NATIVE_ASL1_CACHE" "/.asl/run/asl1") (pair "ASL_CHECK_CACHE" "/.asl/cache/check") (pair "ASL_CORPUS_CACHE" "/.asl/run/corpusCache"))

; (:m :ref CACHE-HOME-LEAK :do "NAME=dir rows for this process's caches, as seen from cwd: the override when set and non-empty, else this HOME's default; pass them with a child's own HOME")
fn ! cacheEnv! -> (List String)
  (let [(home (optionOr (envGet "HOME") "/tmp"))
        (linked (match (fileStat ".git") ((ok st) (not st.isDir)) ((err _) false)))]
    (fold (fn [(acc (List String)) (r (Pair String String))] -> (List String)
            (let [(set (optionOr (envGet (pairFirst r)) ""))]
              (cond
                ((not (stringEmpty? set)) (listAppend acc (list (str (pairFirst r) "=" set))))
                ((and (= (pairFirst r) "ASL_NATIVE_TEST_CACHE") (not linked)) acc)
                (else (listAppend acc (list (str (pairFirst r) "=" home (pairSecond r))))))))
          (list) (cacheRows)))

; (:m :ref WT-FRESH-HOST-BUILD :do "a child given its own HOME and no ASL_NATIVE_TEST_CACHE gets this process's compile cache row from cacheEnv!: in a linked worktree the cache follows HOME, so a test's temp-HOME child recompiled 100 modules and the prelude on every start (gateway serve 36-39 s on node2, 2026-10-31) and outran its 30 s ready wait")
fn ! childEnv overrides: (List String) -> (List String)
  (let [(nameOf (fn [(row String)] -> String (optionOr (listHead (stringSplit row "=")) row)))
        (given (map nameOf overrides))
        (cache (if (and (listContains? given "HOME") (not (listContains? given "ASL_NATIVE_TEST_CACHE")))
                 (filter (fn [(row String)] -> Bool (= (nameOf row) "ASL_NATIVE_TEST_CACHE")) (cacheEnv!))
                 (list)))
        (rows (listAppend overrides cache))
        (names (map nameOf rows))]
    (listAppend rows
      (filter (fn [(row String)] -> Bool
                (let [(k (nameOf row))] (and (not (listContains? names k)) (and (not (secretName? k)) (inheritedOk? k)))))
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
  (Limits :timeoutMs (* timeoutS 1000) :maxDesc maxDesc :class "" :jsDir "")

; (:m :ref MACHINE-JOBSERVER :do "opt-in per call: a suite, build, clang or bench child takes a machine-wide CPU token of this class (train audit writer background exclusive) before exec and frees it on exit; the default class \"\" takes none, so short git and grep children and children of a token holder never queue behind the pool they run under; jsDir \"\" is ~/.asl/run/jobserver")
fn heavy lim: Limits cls: String dir: String -> Limits
  (Limits :timeoutMs lim.timeoutMs :maxDesc lim.maxDesc :class cls :jsDir dir)

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

; (:m :ref GITCONFIG-GUARD-SHELLOUT :do "processSpawn hands the child this process's whole environment, so shellOut opens the command with an unset of every inherited name inheritedOk? drops (GIT_DIR, GIT_WORK_TREE, GIT_CONFIG_* ...): a hook's or a fixture's repository variables never reach it; only plain shell names are listed, any other name is left for the child's shell to ignore")
fn ! gitUnsetPrefix -> String
  (let [(plain? (fn [(n String)] -> Bool (and (not (stringEmpty? n)) (not (listAny? (fn [(c String)] -> Bool (stringContains? n c)) (list " " ";" "&" "|" "$" "`" "'" "\"" "(" ")" "<" ">" "\\" "*" "?" "\n" "\t" "-" "."))))))
        (names (filter (fn [(n String)] -> Bool (and (not (inheritedOk? n)) (plain? n))) (map (fn [(row String)] -> String (optionOr (listHead (stringSplit row "=")) row)) (envList))))]
    (if (listEmpty? names) "" (str "unset " (stringJoin names " ") "; ")))

fn ! shellOut cmd: String timeoutMs: Int64 -> (Result String String)
  (match (processSpawn (str (gitUnsetPrefix) cmd))
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

; (:m :ref KILLTREE-NO-PINS :do "stop a guarded run from outside its own judge (a cancel, a dropped connection): the kill carries the groups and pins the guard recorded, so a setsid escapee the guard saw in the tree goes with it, where killTree! of the bare pid spares it")
fn ! stopGuard! g: Guarded -> Int64
  (let [(left (killTreeWith! g.run.pid g.run.groups g.run.known))
        (_ (dropTmp g.run.tmp))]
    left)

fn ! pumpOne r: Running -> (Pair Bool Running)
  (let [(o (readChunk r.outFd r.outOpen))
        (e (readChunk r.errFd r.errOpen))
        (got (str (pairSecond o) (pairSecond e)))]
    (pair (not (stringEmpty? got))
          (Running :idx r.idx :pid r.pid :outFd r.outFd :errFd r.errFd :text (str r.text got)
                   :outOpen (pairFirst o) :errOpen (pairFirst e) :startNs r.startNs :killed r.killed :groups r.groups :known r.known :tmp r.tmp)))

fn leadDigits s: String n: Int64 i: Int64 -> String
  (if (and (< i n) (stringContains? "0123456789" (optionOr (stringSlice s i (+ i 1)) "x")))
    (leadDigits s n (+ i 1))
    (optionOr (stringSlice s 0 i) ""))

(schema Drain
  (:f bytes Int64)
  (:f ms Int64))

; (:m :ref FR-KILL-DRAIN :do "the :fleet group starts at :fleet followed by a space and an opening paren or by an opening paren, so :fleetRun or another key that begins with fleet is not the group")
fn fleetGroupAt text: String -> (Option Int64)
  (match (stringIndexOf text ":fleet (")
    ((some g) (some g))
    ((none) (stringIndexOf text ":fleet(")))

; (:m :ref FR-KILL-DRAIN :do "a value of the :fleet group of .asl.config.asn under the root (ASL_ROOT, else the working directory): the digits after :KEY inside the group, the default when the file, the group or the key is absent or the value is outside lo..hi")
fn fleetInt text: String key: String dflt: Int64 lo: Int64 hi: Int64 -> Int64
  (match (fleetGroupAt text)
    ((none) dflt)
    ((some g)
      (let [(rest (optionOr (stringSlice text g (stringLength text)) ""))
            (end (optionOr (stringIndexOf rest ")") (stringLength rest)))
            (grp (optionOr (stringSlice rest 0 end) ""))]
        (match (stringIndexOf grp (str ":" key " "))
          ((none) dflt)
          ((some i)
            (let [(tail (stringTrim (optionOr (stringSlice grp (+ i (+ (stringLength key) 2)) (stringLength grp)) "")))
                  (digits (leadDigits tail (stringLength tail) 0))
                  (v (optionOr (stringToInt64 digits) -1))]
              (if (and (>= v lo) (<= v hi)) v dflt)))))))

; (:m :ref FR-KILL-DRAIN :do "after a judge kill the pipes are read on, bounded by :fleet :drainBytes (default 1048576, 0 turns the drain off) and :fleet :drainMs (default 300): the child died with output still in its pipes and the pump had not read it yet")
fn ! drainConfig! -> Drain
  (let [(text (resultOr (fileReadString (str (optionOr (envGet "ASL_ROOT") ".") "/.asl.config.asn")) ""))]
    (Drain :bytes (fleetInt text "drainBytes" 1048576 0 67108864) :ms (fleetInt text "drainMs" 300 0 5000)))

fn ! drainFd fd: Int64 isOpen: Bool cap: Int64 deadlineNs: Int64 acc: String -> (Pair Bool String)
  (cond
    ((not isOpen) (pair false acc))
    ((>= (stringLength acc) cap) (pair true acc))
    ((>= (monotonicNs) deadlineNs) (pair true acc))
    (else
      (let [(c (readChunk fd true))]
        (cond
          ((not (pairFirst c)) (pair false (str acc (pairSecond c))))
          ((stringEmpty? (pairSecond c)) (do (fdPoll (list (pair fd 1)) 10) (drainFd fd true cap deadlineNs acc)))
          (else (drainFd fd true cap deadlineNs (str acc (pairSecond c))))))))

fn ! judge lim: Limits now: Int64 snap: (List Proc) self: Int64 checked: Bool r: Running -> Running
  (let [(overTime (and (> lim.timeoutMs 0) (> (/ (- now r.startNs) 1000000) lim.timeoutMs)))
        (tree (if checked (treeOf snap r.pid r.groups r.known self) (pair (list) r.groups)))
        (groups (pairSecond tree))
        (known (if checked (addNew r.known (pinsOf snap (pairFirst tree))) r.known))
        (descN (if (and checked (> lim.maxDesc 0)) (listLength (pairFirst tree)) 0))
        (verdict (cond (overTime "timeout") ((> descN lim.maxDesc) "runaway") (else "")))]
    (if (stringEmpty? verdict)
      (Running :idx r.idx :pid r.pid :outFd r.outFd :errFd r.errFd :text r.text
               :outOpen r.outOpen :errOpen r.errOpen :startNs r.startNs :killed r.killed :groups groups :known known :tmp r.tmp)
      (let [(left (killTreeWith! r.pid groups known))
            (dc (drainConfig!))
            (dl (+ (monotonicNs) (* dc.ms 1000000)))
            (o (drainFd r.outFd r.outOpen dc.bytes dl ""))
            (e (drainFd r.errFd r.errOpen dc.bytes dl ""))
            (note (str "\n(:fleetRun :verdict :" verdict " :pid " r.pid " :desc " descN " :timeoutMs " lim.timeoutMs " :maxDesc " lim.maxDesc " :left " left ")\n"))]
        (Running :idx r.idx :pid r.pid :outFd r.outFd :errFd r.errFd :text (str r.text (pairSecond o) (pairSecond e) note)
                 :outOpen (pairFirst o) :errOpen (pairFirst e) :startNs r.startNs :killed verdict :groups groups :known known :tmp r.tmp))))

fn ! closeIfOpen fd: Int64 isOpen: Bool -> Int64
  (if isOpen (do (fdClose fd) 1) 0)

fn killedExit verdict: String -> Int64
  (if (= verdict "timeout") 124 125)

fn ! finish r: Running -> Done
  (let [(_ (closeIfOpen r.outFd r.outOpen))
        (_ (closeIfOpen r.errFd r.errOpen))
        (code (match (procWaitPid r.pid false) ((ok status) (optionOr status 1)) ((err _) 1)))
        (_ (dropTmp r.tmp))
        (killed (not (stringEmpty? r.killed)))]
    (Done :idx r.idx :exit (if killed (killedExit r.killed) code) :out r.text :ms (/ (- (monotonicNs) r.startNs) 1000000)
          :verdict (if killed r.killed "exit")))

; (:m :ref NOSELFHOST-RETRYCONC-20261017 :do "exported so a long-lived server/stub a test needs to interact with WHILE it runs (not just supervise start-to-finish like runOneLimited) still starts only through this module, per rule spawnSafety; the caller owns draining or redirecting Running's outFd/errFd (fr/spawn makes them non-blocking pipes, same as runOneLimited's own pool loop does) and must call killTree! on Running.pid at cleanup, never a bare procKill, so a verdict (or an explicit stop) takes the whole process tree, not just the one pid")
; (:m :ref TRAIN18-NOFOREIGN-20261018 :do "spawn no longer calls procSpawnv itself: spawnSep is the one process-spawning site in this file, and spawn builds on it (nice-prefixing its own argv first, same as before), converting the RunningSep it gets back into the Running shape poolLoop's pumpOne/judge/finish already consume (an empty text seed; pumpOne appends combined stdout+stderr into it a chunk at a time exactly as it already did when spawn held the pipes directly)")
; (:m :ref TMP-LEAK-RUNNER :do "every pooled or guarded child gets its own scratch dir <base>/aslRun-<pid>-<ns> in ASL_RUN_TMP (base: the job's TMPDIR row, else this process's, else /tmp; TMPDIR itself is never changed, so caches that live under it survive), and the runner removes exactly that dir after every verdict (exit, timeout, runaway): a test killed by the watchdog cannot clean up its own scratch, which left 200-400MB dirs per run in /tmp on node2")
fn tmpName dir: String -> Bool
  (and (stringContains? dir "/aslRun-") (not (stringEndsWith? dir "/")))

fn ! freshTmp env: (List String) -> (Pair String (List String))
  (let [(rows (filter (fn [(r String)] -> Bool (stringStartsWith? r "TMPDIR=")) env))
        (given (optionOr (listHead (map (fn [(r String)] -> String (stringReplace r "TMPDIR=" "")) rows)) ""))
        (raw (if (stringEmpty? given) (optionOr (envGet "TMPDIR") "/tmp") given))
        (base (if (and (> (stringLength raw) 1) (stringEndsWith? raw "/")) (optionOr (stringSlice raw 0 (- (stringLength raw) 1)) raw) raw))
        (dir (str base "/aslRun-" (stringFromInt64 (procSelf)) "-" (stringFromInt64 (monotonicNs))))]
    (if (ok? (dirCreate dir))
      (pair dir (cons (str "ASL_RUN_TMP=" dir) (filter (fn [(r String)] -> Bool (not (stringStartsWith? r "ASL_RUN_TMP="))) env)))
      (pair "" env)))

fn ! dropTmp dir: String -> Bool
  (if (tmpName dir) (ok? (pathRemove dir)) false)

fn ! spawn idx: Int64 j: Job -> (Result Running Done)
  (spawnIn idx j "" j.env)

fn ! spawnPooled idx: Int64 j: Job -> (Result Running Done)
  (let [(t (freshTmp j.env))]
    (spawnIn idx j (pairFirst t) (pairSecond t)))

fn ! spawnIn idx: Int64 j: Job tmp: String env: (List String) -> (Result Running Done)
  (match (spawnSep (listAppend (list "nice" "-n" "15") j.argv) j.cwd env)
    ((err po) (let [(_ (dropTmp tmp))] (err (Done :idx idx :exit po.exitCode :out po.stderr :ms 0 :verdict "spawnFailed"))))
    ((ok r) (ok (Running :idx idx :pid r.pid :outFd r.outFd :errFd r.errFd :text "" :outOpen r.outOpen :errOpen r.errOpen :startNs r.startNs :killed r.killed :groups r.groups :known r.known :tmp tmp))))

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
                      :startNs r.startNs :killed r.killed :groups r.groups :known r.known :tmp r.tmp)))

fn ! judgeSep lim: Limits now: Int64 snap: (List Proc) self: Int64 checked: Bool r: RunningSep -> RunningSep
  (let [(overTime (and (> lim.timeoutMs 0) (> (/ (- now r.startNs) 1000000) lim.timeoutMs)))
        (tree (if checked (treeOf snap r.pid r.groups r.known self) (pair (list) r.groups)))
        (groups (pairSecond tree))
        (known (if checked (addNew r.known (pinsOf snap (pairFirst tree))) r.known))
        (descN (if (and checked (> lim.maxDesc 0)) (listLength (pairFirst tree)) 0))
        (verdict (cond (overTime "timeout") ((> descN lim.maxDesc) "runaway") (else "")))]
    (if (stringEmpty? verdict)
      (RunningSep :pid r.pid :outFd r.outFd :errFd r.errFd :outText r.outText :errText r.errText
                  :outOpen r.outOpen :errOpen r.errOpen :startNs r.startNs :killed r.killed :groups groups :known known :tmp r.tmp)
      (let [(left (killTreeWith! r.pid groups known))
            (dc (drainConfig!))
            (dl (+ (monotonicNs) (* dc.ms 1000000)))
            (o (drainFd r.outFd r.outOpen dc.bytes dl ""))
            (e (drainFd r.errFd r.errOpen dc.bytes dl ""))
            (note (str "\n(:fleetRun :verdict :" verdict " :pid " r.pid " :desc " descN " :timeoutMs " lim.timeoutMs " :maxDesc " lim.maxDesc " :left " left ")\n"))]
        (RunningSep :pid r.pid :outFd r.outFd :errFd r.errFd :outText (str r.outText (pairSecond o)) :errText (str r.errText (pairSecond e) note)
                    :outOpen (pairFirst o) :errOpen (pairFirst e) :startNs r.startNs :killed verdict :groups groups :known known :tmp r.tmp))))

fn ! finishSep r: RunningSep -> ProcOut
  (let [(_ (closeIfOpen r.outFd r.outOpen))
        (_ (closeIfOpen r.errFd r.errOpen))
        (code (match (procWaitPid r.pid false) ((ok status) (optionOr status 1)) ((err _) 1)))
        (_ (dropTmp r.tmp))
        (killed (not (stringEmpty? r.killed)))]
    (ProcOut :exitCode (if killed (killedExit r.killed) code) :stdout r.outText :stderr r.errText
             :timedOut (= r.killed "timeout")))

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
         :deadlineNs (optionOr (fieldInt text ":deadlineNs ") 0)
         :wroteNs (optionOr (fieldInt text ":wroteNs ") 0)
         :pgidBorn (optionOr (fieldInt text ":pgidBorn ") 0)
         :ownerBorn (optionOr (fieldInt text ":ownerBorn ") 0))

; (:m :ref FR-LEASE-REAPER-RACE :do "a lease carries the wall clock time it was written (:wroteNs) and the start time (seconds, from ps etime) of the group leader and of the owner (:pgidBorn, :ownerBorn, 0 when the process was not in the snapshot): a pid alone is not an identity once pids wrap, so the reaper compares the start time too")
fn ! writeLeaseAt! pgid: Int64 ownerPid: Int64 startNs: Int64 deadlineNs: Int64 wroteNs: Int64 pgidBorn: Int64 ownerBorn: Int64 -> Bool
  (and (ok? (dirCreate (leaseDir)))
       (ok? (fileWrite (leasePath pgid) (str "(:pgid " pgid " :ownerPid " ownerPid " :startNs " startNs " :deadlineNs " deadlineNs " :wroteNs " wroteNs " :pgidBorn " pgidBorn " :ownerBorn " ownerBorn ")\n"))))

fn bornIn snap: (List Proc) pid: Int64 -> Int64
  (match (listFind (fn [(p Proc)] -> Bool (= p.pid pid)) snap)
    ((some p) (max 0 p.born))
    ((none) 0))

fn sameStart? recorded: Int64 live: Int64 -> Bool
  (let [(d (- recorded live))]
    (and (> recorded 0) (and (> live 0) (<= (if (< d 0) (- 0 d) d) 2))))

fn ! writeLease! pgid: Int64 ownerPid: Int64 startNs: Int64 deadlineNs: Int64 -> Bool
  (let [(snap (procSnapshot))]
    (writeLeaseAt! pgid ownerPid startNs deadlineNs (nowNs) (bornIn snap pgid) (bornIn snap ownerPid)))

fn ! removeLease! pgid: Int64 -> Bool
  (ok? (pathRemove (leasePath pgid)))

; (:m :ref ORPHAN-EVAL-ESCAPE :do "a backstop deadline even with no caller-set timeout: spawnSafety forbids an unbounded lease, so an unset timeoutMs still gets a bounded (if generous) deadline rather than one that never expires")
fn ! leaseDeadline startNs: Int64 timeoutMs: Int64 -> Int64
  (+ startNs (* (if (> timeoutMs 0) timeoutMs 3600000) 1000000))

; (:m :ref FR-LEASE-REAPER-RACE :do "a lease written after the process snapshot was taken belongs to an owner forked after it, which the snapshot cannot hold: it is kept (parallel starts killed each others live groups, claimFailed exit -9 on node2). The lease names its group leader and owner by pid and start time: a leader pid that is live now with another start time, or a lease row without a recorded start time while its leader pid is live, is a reused pid: the row is dropped and nothing is killed. Otherwise an owner that is not live with the recorded start time, or a lease past its deadline, gets the group killed and the row removed")
fn ! reapLeaseFile! dir: String now: Int64 snap: (List Proc) snapNs: Int64 name: String -> Bool
  (let [(path (str dir "/" name))
        (lease (parseLease (resultOr (fileReadString path) "")))
        (expired (and (> lease.deadlineNs 0) (> now lease.deadlineNs)))
        (newer (> lease.wroteNs snapNs))
        (leaderLive (bornIn snap lease.pgid))
        (leaderThere (listAny? (fn [(p Proc)] -> Bool (= p.pid lease.pgid)) snap))
        (reused (and leaderThere (not (sameStart? lease.pgidBorn leaderLive))))
        (ownerThere (listAny? (fn [(p Proc)] -> Bool (= p.pid lease.ownerPid)) snap))
        (ownerSame (and ownerThere (or (<= lease.ownerBorn 0) (sameStart? lease.ownerBorn (bornIn snap lease.ownerPid)))))]
    (cond
      ((<= lease.pgid 0) false)
      (newer false)
      (reused (do (pathRemove path) true))
      ((or (not ownerSame) expired)
        (let [(_ (killTreeWith! lease.pgid (list lease.pgid) (list)))
              (_ (pathRemove path))]
          true))
      (else false)))

fn ! reapLeasesAt! dir: String snap: (List Proc) self: Int64 snapNs: Int64 -> Int64
  (let [(now (monotonicNs))
        (names (if (listAny? (fn [(p Proc)] -> Bool (= p.pid self)) snap) (resultOr (dirList dir) (list)) (list)))]
    (fold (fn [(n Int64) (name String)] -> Int64 (if (reapLeaseFile! dir now snap snapNs name) (+ n 1) n)) 0 names))

fn ! reapLeasesIn! dir: String snap: (List Proc) self: Int64 -> Int64
  (reapLeasesAt! dir snap self (nowNs))

fn ! reapStaleLeases! -> Int64
  (let [(snapNs (nowNs))
        (snap (procSnapshot))]
    (reapLeasesAt! (leaseDir) snap (procSelf) snapNs))

; (:m :ref GW-SESSION-BIND :do "a guarded run a caller steps itself: guardStart! reaps stale leases, spawns and writes the lease; each guardAdvance! pumps output once and judges the limits, returning the ProcOut when the child has ended, so a single-threaded server can park the run and look at it between other work; guardFds is what to poll. guardLoop and runGuarded are this same step in a blocking loop")
(schema Guarded
  (:f run RunningSep)
  (:f lim Limits)
  (:f lastCheck Int64))

(schema GuardStep
  (:f out (Option ProcOut))
  (:f guard Guarded)
  (:f progress Bool))

fn ! guardSpawn argv: (List String) cwd: String env: (List String) -> (Result RunningSep ProcOut)
  (let [(t (freshTmp env))]
    (match (spawnSep argv cwd (pairSecond t))
      ((err d) (let [(_ (dropTmp (pairFirst t)))] (err d)))
      ((ok r) (ok (RunningSep :pid r.pid :outFd r.outFd :errFd r.errFd :outText r.outText :errText r.errText :outOpen r.outOpen :errOpen r.errOpen :startNs r.startNs :killed r.killed :groups r.groups :known r.known :tmp (pairFirst t))))))

fn ! guardStart! argv: (List String) cwd: String env: (List String) lim: Limits -> (Result Guarded ProcOut)
  (let [(_ (reapStaleLeases!))
        (g (js/acquire lim.jsDir lim.class (stringFromInt64 (monotonicNs)) lim.timeoutMs))]
    (if (= g.state "expired")
      (err (ProcOut :exitCode 124 :stdout "" :stderr (str "(:fleetRun :verdict :tokenWait :class " lim.class " :timeoutMs " lim.timeoutMs ")\n")))
      (match (guardSpawn argv cwd env)
        ((err d) (let [(_ (js/releaseIdxs lim.jsDir g.idxs))] (err d)))
        ((ok r0) (let [(r (if (listEmpty? g.idxs) r0 (let [(_ (js/bind lim.jsDir g.idxs r0.pid lim.class g.startNs))] (startedAtSep r0 g.startNs))))
                       (_ (writeLease! r.pid (procSelf) r.startNs (leaseDeadline r.startNs lim.timeoutMs)))]
                   (ok (Guarded :run r :lim lim :lastCheck 0)))))))

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
        (self (if checked (procSelf) -1))
        (r2 (judgeSep lim now snap self checked r1))
        (over? (or (not (stringEmpty? r2.killed)) (and (not r2.outOpen) (not r2.errOpen))))
        (g2 (Guarded :run r2 :lim lim :lastCheck (if checked now g.lastCheck)))]
    (if over?
      (let [(o (finishSep r2)) (_ (removeLease! r2.pid)) (_ (js/releasePid lim.jsDir lim.class r2.pid))]
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
      (let [(g (js/want lim.jsDir lim.class (stringFromInt64 next) lim.timeoutMs))]
        (cond
          ((= g.state "expired")
           (let [(d (Done :idx next :exit 124 :out (str "(:fleetRun :verdict :tokenWait :class " lim.class " :timeoutMs " lim.timeoutMs ")\n") :ms (/ (- (monotonicNs) g.startNs) 1000000) :verdict "tokenWait"))]
             (poolLoop jobs (+ next 1) slots lim running (cons d done) lastCheck admit onDone (onDone state d))))
          ((= g.state "wait")
           (if (listEmpty? running)
             (let [(_ (sleepMs (js/backoffMs g.startNs)))] (poolLoop jobs next slots lim running done lastCheck admit onDone state))
             (poolPump jobs next slots lim running done lastCheck admit onDone state)))
          (else
           (match (spawnPooled next (optionOr (listGet jobs next) (job (list) "." (list))))
             ((err d) (let [(_ (js/releaseIdxs lim.jsDir g.idxs))] (poolLoop jobs (+ next 1) slots lim running (cons d done) lastCheck admit onDone (onDone state d))))
             ((ok r0) (let [(r (if (listEmpty? g.idxs) r0 (let [(_ (js/bind lim.jsDir g.idxs r0.pid lim.class g.startNs))] (startedAt r0 g.startNs))))]
                        (poolLoop jobs (+ next 1) slots lim (listAppend running (list r)) done lastCheck admit onDone state))))))))
    (poolPump jobs next slots lim running done lastCheck admit onDone state))

fn startedAt r: Running ns: Int64 -> Running
  (Running :idx r.idx :pid r.pid :outFd r.outFd :errFd r.errFd :text r.text :outOpen r.outOpen :errOpen r.errOpen :startNs ns :killed r.killed :groups r.groups :known r.known :tmp r.tmp)

fn startedAtSep r: RunningSep ns: Int64 -> RunningSep
  (RunningSep :pid r.pid :outFd r.outFd :errFd r.errFd :outText r.outText :errText r.errText :outOpen r.outOpen :errOpen r.errOpen :startNs ns :killed r.killed :groups r.groups :known r.known :tmp r.tmp)

fn ! poolPump jobs: (List Job) next: Int64 slots: Int64 lim: Limits running: (List Running) done: (List Done) lastCheck: Int64 admit: (fn [Int64] -> Bool) onDone: (fn [S Done] -> S) state: S -> (Pair (List Done) S)
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
            (_ (fold (fn [(n Int64) (r Running)] -> Int64 (+ n (js/releasePid lim.jsDir lim.class r.pid))) 0 closed))
            (nextState (fold onDone state finished))]
        ; (:m :ref RUNASL-POOLLOOP-FDPOLL-TYPE-20261017 :do "fix: the two if branches disagreed in type (fdPoll's own (Result (List (Pair Int64 Int64)) String) vs the else branch's bare Unit) -- a latent mismatch only a full native rebuild's whole-program check surfaces, not the normal incremental path; fdPoll's own result was always discarded here (it is called only to block until a socket is ready or the 50ms timeout passes, never consulted), so the true branch now discards it explicitly too, making both branches Unit with no change in runtime behavior")
        (do (if (and (not progress) (listEmpty? closed)) (let [(_ (fdPoll (openFds still) 50))] ()) ())
            (poolLoop jobs next slots lim still (listAppend finished done) (if checked now lastCheck) admit onDone nextState))))

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
  (let [(d (runOneLimited (job (list "sh" "-c" cmd) cwd env) lim))]
    (with d :out (gateOutHost (stubHostFor! cmd) cmd d.out)))

; (:m :ref GATE-ASSERTS-FROM-LEDGER :do "the executed-assert count of a gate was read from any line of the gate's own stdout, so a command that echoed '5 assertion(s) executed' passed the conductor's asserts>0 check without running a suite. Now a gate counts only in the declared form ./bin/asl test FILE... (or asl test): the host prints one verdict line per FILE after the suite's own output, the lines must be exactly the declared files' verdicts and the last lines of the output; any other count or FAIL line is rewritten to 'claimed' or '(unrecorded) FAIL' and a marker row says why. A gate whose own files are modified by the unit under test (bin/asl itself) is not covered.")
; (:m :ref GATE-ASSERTS-FROM-LEDGER :do "test stand-in for the host's test command in hermetic fixtures: greenN.asl prints N passed, redN.asl fails after N asserts, any other file is run as sh and its 'assert ' lines are the count; stubHost! writes it once to a fixed path and returns the path, a gate is then (str (stubHost!) \" test greenN.asl\"), which has the declared form")
fn stubHostText -> String
  "#!/bin/sh\n[ \"$1\" = test ] || exit 2\nshift\nrc=0\nfor f in \"$@\"; do\n  b=${f##*/}\n  case \"$b\" in\n    green*.asl) n=${b#green}; n=${n%.asl}; echo \"$f: $n assertion(s) executed ($n passed)\" ;;\n    red*.asl) n=${b#red}; n=${n%.asl}; echo \"suite: ERR_TYPE boom in $b\"; echo \"FAIL $f: ERR_ASSERT: assertion failed: red (after $n asserts)\"; rc=1 ;;\n    *) out=$(sh \"$f\" 2>&1); r=$?; [ -z \"$out\" ] || printf '%s\\n' \"$out\"; n=$(printf '%s\\n' \"$out\" | /usr/bin/grep -c '^assert '); e=$(printf '%s\\n' \"$out\" | /usr/bin/grep -o 'ERR_[A-Z_]*' | head -1); if [ $r -eq 0 ]; then echo \"$f: $n assertion(s) executed ($n passed)\"; else echo \"FAIL $f: ${e:-exit $r} (after $n asserts)\"; rc=1; fi ;;\n  esac\ndone\nexit $rc\n"

; (:m :ref GATE-ASSERTS-FROM-LEDGER :do "a stand-in install belongs to the process that made it: /tmp/aslStubHost-PID-TOKEN, TOKEN from the pid and the clock. Production trusts a stub head only from such a dir whose PID is alive and is the running process or one of its ancestors, so a dir left behind or planted by a unit (dead pid, unrelated pid, the old fixed name) is refused")
fn stubPrefix -> String
  "/tmp/aslStubHost-"

; (:m :ref GATE-ASSERTS-FROM-LEDGER :do "the stand-in host is trusted only from a private install: dir is a real directory (lstat, no symlink), mode 700, owned by the caller, and bin/asl holds exactly the stand-in text; stubHostIn! never reuses what it finds, it rewrites bin/asl through a temp name and verifies again, and any failed check returns the empty string so the caller fails closed; is the same check without writing, and is what lets runShell! accept the stand-in head: where no test installed it, the head is undeclared")
fn ! privateDir? dir: String -> Bool
  (match (fileLstat dir)
    ((err _) false)
    ((ok st) (and st.isDir (and (= (mod st.mode 512) 448) (= (runOne (job (list "test" "-O" dir) dir (childEnv (list)))).exit 0)))))

fn ! stubVerifiedIn! dir: String -> Bool
  (and (privateDir? dir)
    (match (fileLstat (str dir "/bin/asl"))
      ((err _) false)
      ((ok st) (and st.isFile (= (resultOr (fileReadString (str dir "/bin/asl")) "") (stubHostText))))))

fn ownerPidOf dir: String -> Int64
  (if (stringStartsWith? dir (stubPrefix))
    (optionOr (stringToInt64 (optionOr (listHead (stringSplit (optionOr (stringSlice dir (stringLength (stubPrefix)) (stringLength dir)) "") "-")) "")) 0)
    0)

fn ! parentOf pid: Int64 -> Int64
  (let [(d (runOneLimited (job (list "ps" "-o" "ppid=" "-p" (stringFromInt64 pid)) "." (childEnv (list))) (limits 5 4)))]
    (if (= d.exit 0) (optionOr (stringToInt64 (stringTrim d.out)) 0) 0))

fn ! ancestorFrom? at: Int64 pid: Int64 depth: Int64 -> Bool
  (cond ((= at pid) true) ((or (<= at 1) (> depth 64)) false) (else (ancestorFrom? (parentOf at) pid (+ depth 1))))

fn ! ancestorOrSelf? pid: Int64 -> Bool
  (and (> pid 1) (ancestorFrom? (procSelf) pid 0))

fn ! stubOwnerLive? dir: String -> Bool
  (let [(pid (ownerPidOf dir))]
    (and (> pid 1) (and (= (runOneLimited (job (list "kill" "-0" (stringFromInt64 pid)) "." (childEnv (list))) (limits 5 4)).exit 0) (ancestorOrSelf? pid))))

fn ! stubTrustedIn! dir: String -> Bool
  (and (stubOwnerLive? dir) (stubVerifiedIn! dir))

fn ! stubHostFor! cmd: String -> String
  (let [(head (optionOr (listHead (filter (fn [(t String)] -> Bool (not (stringEmpty? t))) (stringSplit (stringTrim cmd) " "))) ""))
        (suffix "/bin/asl")]
    (if (and (stringStartsWith? head (stubPrefix)) (stringEndsWith? head suffix))
      (if (stubTrustedIn! (optionOr (stringSlice head 0 (- (stringLength head) (stringLength suffix))) "")) head "")
      ""))

fn ! stubDirsOwnedBy pid: Int64 -> (List String)
  (match (dirList "/tmp")
    ((err _) (list))
    ((ok names) (map (fn [(n String)] -> String (str "/tmp/" n)) (filter (fn [(n String)] -> Bool (stringStartsWith? (str "/tmp/" n "-") (str (stubPrefix) (stringFromInt64 pid) "-"))) names))))

fn ! stubHostPath -> String
  (match (listHead (filter stubVerifiedIn! (stubDirsOwnedBy (procSelf))))
    ((some d) (str d "/bin/asl"))
    ((none) ""))

fn ! stubHostIn! dir: String -> String
  (let [(existed (ok? (fileLstat dir)))
        (made (if existed true (and (ok? (dirCreate dir)) (= (runOne (job (list "sh" "-c" (str "chmod 700 '" dir "'")) "." (childEnv (list)))).exit 0))))
        (tmp (str dir "/bin/asl." (stringFromInt64 (procSelf)) "." (stringFromInt64 (monotonicNs))))]
    (if (and made (privateDir? dir))
      (let [(_ (dirCreate (str dir "/bin")))
            (_ (fileWrite tmp (stubHostText)))
            (r (runOne (job (list "sh" "-c" (str "chmod 755 '" tmp "' && mv '" tmp "' '" dir "/bin/asl'")) dir (childEnv (list)))))]
        (if (stubVerifiedIn! dir) (str dir "/bin/asl") ""))
      ""))

fn ! stubSweepDead! -> Bool
  (match (dirList "/tmp")
    ((err _) false)
    ((ok names)
      (let [(dead (filter (fn [(d String)] -> Bool (and (stringStartsWith? d (stubPrefix)) (and (privateDir? d) (or (<= (ownerPidOf d) 1) (not (= (runOneLimited (job (list "kill" "-0" (stringFromInt64 (ownerPidOf d))) "." (childEnv (list))) (limits 5 4)).exit 0)))))) (map (fn [(n String)] -> String (str "/tmp/" n)) names)))]
        (listAll? (fn [(d String)] -> Bool (= (runOne (job (list "rm" "-rf" d) "." (childEnv (list)))).exit 0)) dead))))

; (:m :ref GATE-ASSERTS-FROM-LEDGER :do "stubHost! installs this process's stand-in (one dir per process, a token from pid and clock) after sweeping dirs whose owner is gone, stubRemove! deletes it, tests call it on their way out")
fn ! stubHost! -> String
  (let [(_ (stubSweepDead!))
        (own (stubHostPath))]
    (if (stringEmpty? own)
      (stubHostIn! (str (stubPrefix) (stringFromInt64 (procSelf)) "-" (optionOr (stringSlice (bytesSha256 (stringToBytes (str (stringFromInt64 (procSelf)) ":" (stringFromInt64 (monotonicNs)) ":" (stubHostText)))) 0 16) "")))
      (stubHostIn! (optionOr (stringSlice own 0 (- (stringLength own) 8)) ""))))

fn ! stubRemove! -> Bool
  (listAll? (fn [(d String)] -> Bool (and (privateDir? d) (= (runOne (job (list "rm" "-rf" d) "." (childEnv (list)))).exit 0))) (stubDirsOwnedBy (procSelf)))

fn gateFiles cmd: String host: String -> (List String)
  (let [(toks (filter (fn [(t String)] -> Bool (not (stringEmpty? t))) (stringSplit (stringTrim cmd) " ")))
        (bad (list ";" "&" "|" "<" ">" "$" "`" "\"" "'" "(" ")" "*" "?" "{" "}" "\\" "~" "!" "#"))
        (files (listDrop toks 2))]
    (if (and (>= (listLength toks) 3)
             (or (listAny? (fn [(h String)] -> Bool (= h (optionOr (listHead toks) ""))) (list "./bin/asl" "bin/asl" "asl"))
                 (and (not (stringEmpty? host)) (= (optionOr (listHead toks) "") host)))
             (= (optionOr (listGet toks 1) "") "test")
             (not (listAny? (fn [(f String)] -> Bool (or (not (stringEndsWith? f ".asl")) (listAny? (fn [(c String)] -> Bool (stringContains? f c)) bad))) files)))
      files
      (list)))

fn verdictFor line: String file: String -> Bool
  (or (and (stringStartsWith? line (str file ": ")) (stringContains? line " assertion(s) executed") (stringEndsWith? line " passed)"))
      (stringStartsWith? line (str "FAIL " file ": ")))

fn claimed line: String -> String
  (cond ((stringContains? line " assertion(s) executed") (stringReplace line " assertion(s) executed" " assertion(s) claimed"))
        ((stringStartsWith? line "FAIL ") (str "(unrecorded) " line))
        (else line))

fn gateOut cmd: String out: String -> String
  (gateOutHost "" cmd out)

fn gateOutHost host: String cmd: String out: String -> String
  (let [(files (gateFiles cmd host))
        (lines (stringLines out))
        (body (filter (fn [(l String)] -> Bool (not (stringEmpty? l))) lines))
        (k (listLength files))
        (tail (listDrop body (max 0 (- (listLength body) k))))
        (isVerdict (fn [(l String)] -> Bool (listAny? (fn [(f String)] -> Bool (verdictFor l f)) files)))
        (isPass (fn [(l String)] -> Bool (and (isVerdict l) (not (stringStartsWith? l "FAIL ")))))
        (all (listLength (filter isVerdict body)))
        (okShape (and (> k 0) (= all k) (= (listLength (filter isPass tail)) (listLength (filter isPass body)))))
        (neutral (stringJoin (map claimed lines) "\n"))
        (marker (cond ((= k 0) "(:gateFormUndeclared :want \"./bin/asl test FILE.asl...\")")
                      (okShape "")
                      (else (str "(:gateVerdictInvalid :files " (stringFromInt64 k) " :verdictLines " (stringFromInt64 all) ")"))))]
    (if okShape
      (let [(kept (stringJoin (map (fn [(l String)] -> String (if (isVerdict l) l (claimed l))) lines) "\n"))] kept)
      (str neutral (if (stringEndsWith? neutral "\n") "" "\n") marker "\n")))

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

; (:m :ref LEON-POOL-SPAWNSAFETY :do "a child that is a fork of this process, not an exec: for an in-process task (Leon's pool) that must not take the caller down when it traps; it gets the same lease, timeoutMs, maxDesc and killTree verdicts as a guarded spawn; lim.class must be empty, since a jobserver token binds to an exec'd child")
(schema Forked
  (:f pid Int64)
  (:f lim Limits)
  (:f startNs Int64)
  (:f lastCheck Int64)
  (:f groups (List Int64))
  (:f known (List Int64)))

(schema ForkEnd
  (:f exit Int64)
  (:f verdict String)
  (:f desc Int64)
  (:f note String))

(schema ForkStep
  (:f end (Option ForkEnd))
  (:f fork Forked))

fn ! cFork -> (Result Int64 String)
  (foreign "c" "fork" "-> i32 !neg")

fn ! cExit code: Int64 -> Int64
  (foreign "c" "_exit" "i32 -> i64")

fn ! cSetpgid pid: Int64 pgid: Int64 -> Int64
  (foreign "c" "setpgid" "i32 i32 -> i32")

fn ! cOpen path: String mode: String -> (Result Handle String)
  (foreign "c" "fopen" "cstr cstr -> handle:fclose !null")

fn ! cFileno f: Handle -> Int64
  (foreign "c" "fileno" "handle:fclose -> i32")

fn ! cDup2 from: Int64 to: Int64 -> (Result Int64 String)
  (foreign "c" "dup2" "i32 i32 -> i32 !neg")

fn ! redirectTo! log: String -> Bool
  (match (cOpen log "w")
    ((err _) false)
    ((ok h) (let [(fd (cFileno h))] (and (ok? (cDup2 fd 1)) (ok? (cDup2 fd 2))))))

; (:m :ref LEON-POOL-SPAWNSAFETY :do "the child leads its own process group (set on both sides of the fork, so the group exists before the parent's first tree walk) with stdout and stderr in log, runs body and leaves by _exit with its result, or with 125 when it cannot set its group or open its log, so the parent's stdio buffers are not flushed twice; a trap in body exits the child alone")
fn ! forkLimited! log: String lim: Limits body: (fn [] -> Int64) -> (Result Forked String)
  (cond
    ((not (stringEmpty? lim.class)) (err (str "forkLimited!: lim.class must be empty, a jobserver token cannot bind to a fork: " lim.class)))
    ((<= lim.timeoutMs 0) (err "forkLimited!: timeoutMs must be positive, a fork child is never unbounded"))
    (else
      (let [(_ (reapStaleLeases!))]
        (match (cFork)
          ((ok 0) (ok (Forked :pid (cExit (if (and (>= (cSetpgid 0 0) 0) (redirectTo! log)) (body) 125))
                              :lim lim :startNs 0 :lastCheck 0 :groups (list) :known (list))))
          ((ok pid) (let [(_ (cSetpgid pid pid))
                          (now (monotonicNs))
                          (_ (writeLease! pid (procSelf) now (leaseDeadline now lim.timeoutMs)))]
                      (ok (Forked :pid pid :lim lim :startNs now :lastCheck 0 :groups (list pid) :known (list)))))
          ((err e) (err e))))))

fn forkNote f: Forked verdict: String desc: Int64 left: Int64 -> String
  (str "(:fleetRun :verdict :" verdict " :pid " f.pid " :desc " desc " :timeoutMs " f.lim.timeoutMs " :maxDesc " f.lim.maxDesc " :left " left ")")

; (:m :ref LEON-POOL-SPAWNSAFETY :do "a caller-made verdict (its own deadline): the same tree kill and reap as a limit verdict")
fn ! forkKill! f: Forked verdict: String -> ForkEnd
  (let [(left (killTreeWith! f.pid f.groups f.known))
        (_ (procWaitPid f.pid false))
        (_ (removeLease! f.pid))]
    (ForkEnd :exit -1 :verdict verdict :desc (listLength f.known) :note (forkNote f verdict (listLength f.known) left)))

; (:m :ref LEON-POOL-SPAWNSAFETY :do "one non-blocking step: reap if the child ended, else judge timeoutMs every step and the descendant count every checkEveryNs, killing the whole tree on a timeout or runaway verdict")
fn ! forkAdvance! f: Forked -> ForkStep
  (match (procWaitPid f.pid true)
    ((ok (some code)) (let [(_ (removeLease! f.pid))] (ForkStep :end (some (ForkEnd :exit code :verdict "" :desc 0 :note "")) :fork f)))
    ((err _) (let [(left (killTreeWith! f.pid f.groups f.known)) (_ (removeLease! f.pid))]
               (ForkStep :end (some (ForkEnd :exit -1 :verdict "" :desc 0 :note (forkNote f "waitFailed" 0 left))) :fork f)))
    ((ok (none))
      (let [(now (monotonicNs))
            (overTime (and (> f.lim.timeoutMs 0) (> (/ (- now f.startNs) 1000000) f.lim.timeoutMs)))
            (checked (and (> f.lim.maxDesc 0) (>= (- now f.lastCheck) (checkEveryNs))))
            (snap (if checked (procSnapshot) (list)))
            (tree (if checked (treeOf snap f.pid f.groups f.known (procSelf)) (pair f.known f.groups)))
            (f2 (Forked :pid f.pid :lim f.lim :startNs f.startNs :lastCheck (if checked now f.lastCheck)
                        :groups (pairSecond tree) :known (addNew f.known (pinsOf snap (pairFirst tree)))))
            (descN (if checked (listLength (pairFirst tree)) 0))]
        (cond
          (overTime (ForkStep :end (some (forkKill! f2 "timeout")) :fork f2))
          ((> descN f.lim.maxDesc) (let [(e (forkKill! f2 "runaway"))]
                                     (ForkStep :end (some (ForkEnd :exit e.exit :verdict e.verdict :desc descN :note (forkNote f2 "runaway" descN 0))) :fork f2)))
          (else (ForkStep :end none :fork f2))))))
