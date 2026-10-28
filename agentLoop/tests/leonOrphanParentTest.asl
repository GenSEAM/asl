(module asl/agentLoop/tests/leonOrphanParentTest
  :x [runTests]
  :i [(asl-forms/delegate :a d) (asl-tools/fleet/run :a fr) (aslHarness/tests/agentLoopRecorderKit :a rk)])

; (:m :ref LEON-ORPHAN-PARENT :do "a forked stand-in for the CLI runs the real (:agent) delegate step, which starts the native Leon in its own process group with the stand-in's pid as :parentPid; Leon's gate sleeps 40 s per turn. Killing the stand-in alone (not its tree) must end Leon and the gate's sleeping child within a few seconds; scripted provider, no network, every recorded pid is killed on the way out")

fn slowGate -> String
  "if [ -f started ]; then P=$PPID; echo $P >> ppids; ps -o ppid= -p $P >> ppids; sleep 40 & echo $! >> pids; wait; else touch started; fi\necho '(:gate :asserts 1 :failed 1)'\nexit 1\n"

fn ! freshRoot! -> String
  (let [base (optionOr (envGet "TMPDIR") "/tmp")
        path (str base "/leonOrphanParentTest_" (stringFromInt64 (procSelf)) "_" (stringFromInt64 (nowNs)))
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

fn ! runTests -> Bool
  (let [repo (resultOr (realPath ".") ".")
        root (freshRoot!)
        _cfg (fileWrite (str root "/.asl.config.asn") "(:aslConfig :agentLoop (:specCheck false))\n")
        _gate (fileWrite (str root "/slow.sh") (slowGate))
        fixDir (str root "/tests/fixtures/agentLoop/mvp")
        _dir (dirCreate fixDir)
        _fix (fileWrite (str fixDir "/orph.asn") (rk/scriptFixtureTextFromReplies! "orph" (map (fn [_] "(:step :op \"note\" :text \"waiting\")") (range 0 20))))
        form (str "(:agent :task \"run the scripted turns\" :backend \"script/orph\" :root \"" root "\" :owns (\"x.txt\") :gates (\"sh slow.sh\") :budget 20 :contextTokens 8000 :wallBudget 600 :gateTimeout 300)")
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
        _reap (map (fn [p] (procKill p "SIGKILL")) (filter alive! recorded))
        _lease (match standIn ((ok f) (fr/forkKill! f "done")) ((err _) (fr/ForkEnd :exit -1 :verdict "" :desc 0 :note "")))
        cleaned (ok? (pathRemove root))]
    (do
      (assert (ok? standIn) "the CLI stand-in forks")
      (assert started "Leon started through agentStep reached its slow gate")
      (assert (= (d/withParentPid "(:agent :task \"t\")" 42) "(:agent :task \"t\" :parentPid 42)") "agentStep adds the CLI pid to the form")
      (assert (= (d/withParentPid "(:agent :task \"t\" :parentPid 7)" 42) "(:agent :task \"t\" :parentPid 7)") "a form that names a parent keeps it")
      (assert killed "only the stand-in is killed, not its tree")
      (assert (>= (listLength recorded) 2) "the gate recorded Leon and its sleeping child")
      (assert gone "Leon and the gate's sleeping child are gone after the parent dies")
      (assert (< goneSec 15) "they are gone within a few seconds, not at the 600 s wall budget")
      (assert (stringContains? journal ":signal :parentGone") "Leon ends with a parentGone signal")
      (assert cleaned "the fixture root is removed")
      true))
