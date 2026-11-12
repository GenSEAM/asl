(module aslAgent/tests/leonOrphanResidueTest
  :x [runTests]
  :i [(asl-forms/delegate :a d) (asl-tools/fleet/run :a fr) (aslHarness/tests/agentLoopRecorderKit :a rk)
      (aslAgent/main :a m) (aslAgent/pool :a pl) (aslAgent/gitOps :a go)])

; (:m :ref LEON-ORPHAN-RESIDUE :do "four residues of a dead parent: (A) a stand-in run blocked in a model call (a 40 s child) has the call ended, its child killed and itself killed within a bound once the parent dies; (B) the real (:agent) delegate's baseline gate is watched, so its sleeping child dies with the parent; (C) a pool child's form carries the pool pid as :parentPid; (D) a gate run watching a dead pid ends at once, and the integrity re-run is wired to that env. Every fixture process is forked through fleet/run with limits, killed on the way out, and its root removed")

fn ! freshRoot! tag: String -> String
  (let [base (optionOr (envGet "TMPDIR") "/tmp")
        path (str base "/leonOrphanResidueTest_" tag "_" (stringFromInt64 (procSelf)) "_" (stringFromInt64 (nowNs)))
        made (dirCreate path)]
    (resultOr (realPath path) path))

fn ! pidsIn! path: String -> (List Int64)
  (filter (fn [p] (> p 1))
    (map (fn [l] (optionOr (stringToInt64 (stringTrim l)) 0))
         (filter (fn [l] (not (stringEmpty? (stringTrim l)))) (stringLines (resultOr (fileReadString path) "")))))

fn ! alive! pid: Int64 -> Bool
  (resultOr (procAlive? pid) false)

fn ! aliveReaped! pid: Int64 -> Bool
  (do (procWaitPid pid false) (alive! pid))

fn ! waitFor! test: (fn [] -> Bool) deadlineNs: Int64 -> Bool
  (cond
    ((test) true)
    ((>= (monotonicNs) deadlineNs) false)
    (else (do (sleepMs 200) (waitFor! test deadlineNs))))

fn ! journalOf! root: String -> String
  (let [dir (str root "/.asl/run/agentLoop")
        name (optionOr (listHead (filter (fn [n] (stringEndsWith? n ".journal")) (resultOr (dirList dir) (list)))) "")]
    (if (stringEmpty? name) "" (resultOr (fileReadString (str dir "/" name)) "")))

fn ! killFork! f: (Result fr/Forked String) -> Bool
  (match f ((ok x) (do (fr/forkKill! x "done") true)) ((err _) false))

fn ! reapAll! pids: (List Int64) -> Bool
  (do (map (fn [p] (procKill p "SIGKILL")) (filter alive! pids)) true)

fn ! standInRun! root: String parent: Int64 -> Int64
  (let [watcher (m/parentWatch! (some parent) (str root "/lj.txt") 3 600)
        t0 (monotonicNs)
        out (fr/shellOut (str "cd '" root "'\necho $$ >> pids\nsleep 40 & echo $! >> pids\nwait") 60000)
        endedMs (/ (- (monotonicNs) t0) 1000000)
        wrote (fileWrite (str root "/callEnded") (stringFromInt64 endedMs))
        napped (sleepMs 30000)
        unwatched (m/parentUnwatch! watcher)]
    0)

fn ! scenarioModelCall! -> Bool
  (let [root (freshRoot! "call")
        lj (fileWrite (str root "/lj.txt") "")
        cli (fr/forkLimited! (str root "/cli.log") (fr/limits 150 8) (fn [] -> Int64 (do (sleepMs 120000) 0)))
        cliPid (match cli ((ok f) f.pid) ((err _) -1))
        run (fr/forkLimited! (str root "/run.log") (fr/limits 150 64) (fn [] -> Int64 (standInRun! root cliPid)))
        runPid (match run ((ok f) f.pid) ((err _) -1))
        started (waitFor! (fn [] (>= (listLength (pidsIn! (str root "/pids"))) 2)) (+ (monotonicNs) 30000000000))
        killedNs (monotonicNs)
        killed (match cli ((ok f) (do (procKill f.pid "SIGKILL") (procWaitPid f.pid false) true)) ((err _) false))
        recorded (pidsIn! (str root "/pids"))
        gone (waitFor! (fn [] (and (not (aliveReaped! runPid)) (not (listAny? alive! recorded)))) (+ killedNs 15000000000))
        goneSec (/ (- (monotonicNs) killedNs) 1000000000)
        callEnded (ok? (fileStat (str root "/callEnded")))
        journal (resultOr (fileReadString (str root "/lj.txt")) "")
        reaped (reapAll! (cons runPid recorded))
        ends (listAppend (list (killFork! run)) (list (killFork! cli)))
        cleaned (ok? (pathRemove root))]
    (do
      (assert (and (ok? cli) (ok? run)) "the CLI and run stand-ins fork")
      (assert started "the run reached its blocking model call")
      (assert killed "the parent is killed alone")
      (assert (>= (listLength recorded) 2) "the call recorded its shell and sleeping child")
      (assert callEnded "the blocked model call returned, not left to its 40 s")
      (assert gone "the call's children and the run itself are gone after the parent dies")
      (assert (< goneSec 15) "within a few seconds of the parent's death")
      (assert (stringContains? journal ":signal :parentGone") "the sidecar logs a parentGone signal")
      (assert cleaned "the fixture root is removed")
      true))

fn baselineGate -> String
  "echo $PPID >> ppids\nsleep 40 & echo $! >> pids\nwait\necho '(:gate :asserts 1 :failed 1)'\nexit 1\n"

fn ! scenarioBaseline! -> Bool
  (let [repo (resultOr (realPath ".") ".")
        root (freshRoot! "base")
        _cfg (fileWrite (str root "/.asl.config.asn") "(:aslConfig :agentLoop (:specCheck false))\n")
        _gate (fileWrite (str root "/slow.sh") (baselineGate))
        fixDir (str root "/tests/fixtures/agentLoop/mvp")
        _dir (dirCreate fixDir)
        _fix (fileWrite (str fixDir "/base.asn") (rk/scriptFixtureTextFromReplies! "base" (map (fn [_] "(:step :op \"note\" :text \"waiting\")") (range 0 20))))
        form (str "(:agent :task \"run the scripted turns\" :backend \"script/base\" :root \"" root "\" :owns (\"x.txt\") :gates (\"sh slow.sh\") :budget 20 :contextTokens 8000 :wallBudget 600 :gateTimeout 300)")
        ctx (d/DelegateCtx :rootDir repo :binDir repo :wsDir repo)
        standIn (fr/forkLimited! (str root "/standIn.log") (fr/limits 900 64)
                  (fn [] -> Int64 (let [o (d/agentStep ctx 1 (mapEmpty) form)] (do (fileWrite (str root "/standIn.out") o.line) 0))))
        started (waitFor! (fn [] (not (listEmpty? (pidsIn! (str root "/pids"))))) (+ (monotonicNs) 600000000000))
        killedNs (monotonicNs)
        killed (match standIn ((ok f) (do (procKill f.pid "SIGKILL") (procWaitPid f.pid false) true)) ((err _) false))
        recorded (listAppend (pidsIn! (str root "/ppids")) (pidsIn! (str root "/pids")))
        gone (waitFor! (fn [] (not (listAny? alive! recorded))) (+ killedNs 15000000000))
        goneSec (/ (- (monotonicNs) killedNs) 1000000000)
        journal (journalOf! root)
        reaped (reapAll! recorded)
        ended (killFork! standIn)
        cleaned (ok? (pathRemove root))]
    (do
      (assert (ok? standIn) "the CLI stand-in forks")
      (assert started "Leon reached its baseline gate")
      (assert killed "only the stand-in is killed")
      (assert (stringContains? journal ":baseline") "the first gate run is the baseline run")
      (assert (>= (listLength recorded) 2) "the baseline gate recorded Leon and its sleeping child")
      (assert gone "the baseline gate's sleeping child and Leon are gone after the parent dies")
      (assert (< goneSec 15) "within a few seconds, not at the 300 s gate timeout")
      (assert cleaned "the fixture root is removed")
      true))

fn ! scenarioPool! -> Bool
  (let [root (freshRoot! "pool")
        me (procSelf)
        runner (fn [repoRoot t] -> m/MainResult (do (fileWrite (str root "/form.txt") t.form) (m/MainResult :stdout "" :exitCode 0)))
        task (pl/PoolTask :idx 0 :form "(:agent :task \"t\")" :root root :owns (list) :claims (list) :wallMs 20000 :waitsFor (list) :chan "")
        slots (pl/runPoolWith! root (list (list task)) (pl/PoolLimits :slots 1 :laneMs 60000 :graceMs 5000 :maxDesc 16 :onOverlap "wait") runner)
        form (resultOr (fileReadString (str root "/form.txt")) "")
        cleaned (ok? (pathRemove root))]
    (do
      (assert (stringContains? form (str " :parentPid " (stringFromInt64 me))) "the pool child's form carries the pool pid as :parentPid")
      (assert (= (pl/withPoolParent "(:agent :task \"t\" :parentPid 7)" 42) "(:agent :task \"t\" :parentPid 7)") "a form that names a parent keeps it")
      (assert (= (pl/withPoolParent "(:agent :task \"t\")" 42) "(:agent :task \"t\" :parentPid 42)") "a form without one gains it")
      (assert cleaned "the fixture root is removed")
      true))

fn ! scenarioWatchEnv! -> Bool
  (let [root (freshRoot! "env")
        cli (fr/forkLimited! (str root "/cli.log") (fr/limits 30 4) (fn [] -> Int64 0))
        deadPid (match cli ((ok f) (do (procWaitPid f.pid false) f.pid)) ((err _) -1))
        t0 (monotonicNs)
        rows (go/runGates! (list (pair "g" "sleep 30")) root 60 none (some deadPid))
        secs (/ (- (monotonicNs) t0) 1000000000)
        repo (resultOr (realPath ".") ".")
        mainText (resultOr (fileReadString (str repo "/asl/packages/asl-agent/src/main.asl")) "")
        cleaned (ok? (pathRemove root))]
    (do
      (assert (> deadPid 1) "a short-lived process gives a dead pid")
      (assert (< secs 10) "a gate run watching a dead pid ends at once, not at its 30 s sleep")
      (assert (= (listLength rows) 1) "the watched gate still reports one row")
      (assert (stringContains? mainText "newGates (wallCapped ra.gateTimeout (wallLeft env.wallBudget (- (env.now) state.runStarted))) none (rl/writtenPaths executed.written) ra.parentPid ra.base)") "the integrity re-run is handed the watched parent pid (source anchor)")
      (assert cleaned "the fixture root is removed")
      true))

fn ! runTests -> Bool
  (let [a (scenarioModelCall!)
        b (scenarioBaseline!)
        c (scenarioPool!)
        e (scenarioWatchEnv!)]
    (and (and a b) (and c e)))
