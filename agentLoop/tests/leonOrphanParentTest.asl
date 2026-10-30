(module asl/agentLoop/tests/leonOrphanParentTest
  :x [runTests]
  :i [(asl-forms/delegate :a d) (asl-tools/fleet/run :a fr) (aslHarness/tests/agentLoopRecorderKit :a rk) (asl/agentLoop/tests/gitInitKit :a kit)])

; (:m :ref LEON-ORPHAN-PARENT :do "a forked stand-in for the CLI runs the real (:agent) delegate step, which starts the native Leon in its own process group with the stand-in's pid as :parentPid; a gate sleeps 40 s. Killing the stand-in alone (not its tree) must end Leon and the gate's sleeping child within a few seconds; scripted provider, no network, every recorded pid is killed on the way out")
; (:m :ref LEON-ORPHAN-RESIDUE :do "the integrity scenario's gate is green while Leon's impl.txt exists and sleeps once the revert check removed it, so the sleep is the integrity re-run, which must be watched like a live gate")

schema Outcome (:f forked Bool) (:f started Bool) (:f killed Bool) (:f recorded Int64) (:f gone Bool) (:f goneSec Int64) (:f journal String) (:f cleaned Bool)

fn sleepAndRecord -> String
  "P=$PPID; echo $P >> ppids; ps -o ppid= -p $P >> ppids; sleep 40 & echo $! >> pids; wait"

fn slowGate -> String
  (str "if [ -f started ]; then " (sleepAndRecord) "; else touch started; fi\necho '(:gate :asserts 1 :failed 1)'\nexit 1\n")

fn integrityGate -> String
  (str "if [ -f impl.txt ]; then touch seen; echo '(:gate :asserts 1 :failed 0)'; exit 0; fi\nif [ -f seen ]; then " (sleepAndRecord) "; fi\necho '(:gate :asserts 1 :failed 1)'\nexit 1\n")

fn ! freshRoot! tag: String -> String
  (let [base (optionOr (envGet "TMPDIR") "/tmp")
        path (str base "/leonOrphanParentTest_" (stringFromInt64 (procSelf)) "_" (stringFromInt64 (nowNs)) "_" tag)
        made (dirCreate path)]
    (resultOr (realPath path) path))

fn ! pidsIn! path: String -> (List Int64)
  (filter (fn [p] (> p 1))
    (map (fn [l] (optionOr (stringToInt64 (stringTrim l)) 0))
         (filter (fn [l] (not (stringEmpty? (stringTrim l)))) (stringLines (resultOr (fileReadString path) "")))))

fn ! alive! pid: Int64 -> Bool
  (resultOr (procAlive? pid) false)

fn ! waitFor! test: (fn [] -> Bool) deadlineNs: Int64 -> Bool
  (cond
    ((test) true)
    ((>= (monotonicNs) deadlineNs) false)
    (else (do (sleepMs 200) (waitFor! test deadlineNs))))

fn ! journalOf! root: String -> String
  (let [dir (str root "/.asl/run/agentLoop")
        name (optionOr (listHead (filter (fn [n] (stringEndsWith? n ".journal")) (resultOr (dirList dir) (list)))) "")]
    (if (stringEmpty? name) "" (resultOr (fileReadString (str dir "/" name)) "")))

fn ! orphanRun! tag: String gate: String owns: String replies: (List String) repo: Bool -> Outcome
  (let [ws (resultOr (realPath ".") ".")
        root (freshRoot! tag)
        _git (and repo (and (ok? (fileWrite (str root "/subject.txt") "s\n")) (kit/initGitRepo! root "leonOrphanParentTest" "orphan@example.invalid")))
        _cfg (fileWrite (str root "/.asl.config.asn") "(:aslConfig :agentLoop (:specCheck false))\n")
        _gate (fileWrite (str root "/slow.sh") gate)
        fixDir (str root "/tests/fixtures/agentLoop/mvp")
        _dir (dirCreate fixDir)
        _fix (fileWrite (str fixDir "/" tag ".asn") (rk/scriptFixtureTextFromReplies! tag replies))
        form (str "(:agent :task \"run the scripted turns\" :backend \"script/" tag "\" :root \"" root "\" :owns (\"" owns "\") :gates (\"sh slow.sh\") :budget 20 :contextTokens 8000 :wallBudget 600 :gateTimeout 300)")
        ctx (d/DelegateCtx :rootDir ws :binDir ws :wsDir ws)
        standIn (fr/forkLimited! (str root "/standIn.log") (fr/limits 900 64)
                  (fn [] -> Int64 (let [o (d/agentStep ctx 1 (mapEmpty) form)] (do (fileWrite (str root "/standIn.out") o.line) 0))))
        started (waitFor! (fn [] (not (listEmpty? (pidsIn! (str root "/pids"))))) (+ (monotonicNs) 600000000000))
        killedNs (monotonicNs)
        killed (match standIn ((ok f) (do (procKill f.pid "SIGKILL") (procWaitPid f.pid false) true)) ((err _) false))
        recorded (listAppend (pidsIn! (str root "/ppids")) (pidsIn! (str root "/pids")))
        gone (waitFor! (fn [] (not (listAny? alive! recorded))) (+ killedNs 15000000000))
        goneSec (/ (- (monotonicNs) killedNs) 1000000000)
        journal (journalOf! root)
        _reap (map (fn [p] (procKill p "SIGKILL")) (filter alive! recorded))
        _lease (match standIn ((ok f) (fr/forkKill! f "done")) ((err _) (fr/ForkEnd :exit -1 :verdict "" :desc 0 :note "")))
        cleaned (ok? (pathRemove root))]
    (Outcome :forked (ok? standIn) :started started :killed killed :recorded (listLength recorded) :gone gone :goneSec goneSec :journal journal :cleaned cleaned))

fn ! runTests -> Bool
  (let [notes (map (fn [_] "(:step :op \"note\" :text \"waiting\")") (range 0 20))
        ; (:m :ref AGENTLOOP-MAIN-REDS :do "since fbcd05da7 and 3d81018b8 a turn that persisted no change skips the gates, so the slow gate runs only after a write that lands: two different writes of x.txt give the gate its first (touch started) and second (sleep) run")
        writes (list "(:step :op \"write\" :file \"x.txt\" :content \"a\")" "(:step :op \"write\" :file \"x.txt\" :content \"b\")")
        live (orphanRun! "orph" (slowGate) "x.txt" (listAppend writes notes) false)
        integ (orphanRun! "integ" (integrityGate) "impl.txt" (cons "(:step :op \"write\" :file \"impl.txt\" :content \"i\")" notes) true)]
    (do
      (assert live.forked "the CLI stand-in forks")
      (assert live.started "Leon started through agentStep reached its slow gate")
      (assert (= (d/withParentPid "(:agent :task \"t\")" 42) "(:agent :task \"t\" :parentPid 42)") "agentStep adds the CLI pid to the form")
      (assert (= (d/withParentPid "(:agent :task \"t\" :parentPid 7)" 42) "(:agent :task \"t\" :parentPid 7)") "a form that names a parent keeps it")
      (assert live.killed "only the stand-in is killed, not its tree")
      (assert (>= live.recorded 2) "the gate recorded Leon and its sleeping child")
      (assert live.gone "Leon and the gate's sleeping child are gone after the parent dies")
      (assert (< live.goneSec 15) "they are gone within a few seconds, not at the 600 s wall budget")
      (assert (stringContains? live.journal ":signal :parentGone") "Leon ends with a parentGone signal")
      (assert live.cleaned "the fixture root is removed")
      (assert (and integ.forked integ.killed) "the integrity stand-in forks and is killed alone")
      (assert integ.started "the revert check's re-run reached the sleeping gate")
      (assert (>= integ.recorded 2) "the integrity re-run recorded Leon and its sleeping child")
      (assert integ.gone "Leon and the integrity re-run's sleeping child are gone after the parent dies")
      (assert integ.cleaned "the integrity fixture root is removed")
      true))
