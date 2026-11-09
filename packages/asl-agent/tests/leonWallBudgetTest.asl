(module aslAgent/tests/leonWallBudgetTest
  :x [runTests]
  :i [(aslAgent/main :a m) (aslAgent/loop :a lp) (aslAgent/gateIntegrity :a gi)
      (aslAgent/tests/gitInitKit :a kit) (aslHarness/tests/agentLoopRecorderKit :a rk)])

; (:m :ref LEON-WALLBUDGET-ORPHAN :do "a scripted run whose gate sleeps far past a 5 s :wallBudget ends by itself near the budget, its gate's own sleeping child is killed with the gate's process group, and a reviewer the gateway cannot serve leaves a green gated run needsReview with :reviewer unavailable and exit 0; a gitignored file Leon wrote is code under test and gets the revert check; scripted providers only, no network")

fn ! freshRoot! tag: String -> String
  (let [base (optionOr (envGet "TMPDIR") "/tmp")
        path (str base "/leonWallBudgetTest_" (stringFromInt64 (procSelf)) "_" (stringFromInt64 (nowNs)) "_" tag)
        made (dirCreate path)]
    (resultOr (realPath path) path))

fn ! runForm! root: String id: String fixture: String form: String -> Int64
  (let [dir (str root "/tests/fixtures/agentLoop/mvp")
        made (dirCreate dir)
        wrote (fileWrite (str dir "/" id ".asn") fixture)]
    (m/main (list form)))

fn ! journalOf! root: String -> String
  (let [dir (str root "/.asl/run/agentLoop")
        name (optionOr (listHead (filter (fn [n] (stringEndsWith? n ".journal")) (resultOr (dirList dir) (list)))) "")]
    (if (stringEmpty? name) "" (resultOr (fileReadString (str dir "/" name)) "")))

fn ! pidsOf! root: String -> (List Int64)
  (map (fn [l] (optionOr (stringToInt64 (stringTrim l)) 0))
       (filter (fn [l] (not (stringEmpty? (stringTrim l)))) (stringLines (resultOr (fileReadString (str root "/pids")) ""))))

fn ! alive! pid: Int64 -> Bool
  (and (> pid 0) (resultOr (procAlive? pid) false))

fn slowGate -> String
  "if [ -f started ]; then sleep 40 & echo $! >> pids; wait; else touch started; fi\necho '(:gate :asserts 1 :failed 1)'\nexit 1\n"

fn fileGate -> String
  "if [ -f scratch/w.txt ]; then echo '(:gate :asserts 1 :failed 0)'; else echo '(:gate :asserts 1 :failed 1)'; exit 1; fi\n"

fn downMessage -> String
  "Gateway HTTP error 502: Bad Gateway profile mimo: no model answered (mimoPro); last error: circuit breaker open for commandCode"

fn withGradeError text: String message: String -> String
  (stringReplace text "  )\n)\n" (str "  )\n  :gradeError \"" message "\"\n)\n"))

fn writeReply -> String
  "(:step :op \"write\" :file \"scratch/w.txt\" :content \"w\")"

fn agentForm id: String root: String gates: String extra: String -> String
  (str "(:agent :task \"run the scripted turns\" :backend \"script/" id "\" :root \"" root "\" :mode \"implement\" :budget 20 :contextTokens 8000 :gates (" gates ")" extra ")")

fn ! reviewRoot! tag: String -> String
  (let [root (freshRoot! tag)
        files (and (ok? (fileWrite (str root "/subject.txt") "s\n"))
                (and (ok? (fileWrite (str root "/.gitignore") "scratch/\n")) (ok? (fileWrite (str root "/gate.sh") (fileGate)))))
        repo (kit/initGitRepo! root "leonWallBudgetTest" "wall@example.invalid")
        dir (dirCreate (str root "/scratch"))]
    root)

fn ! runTests -> Bool
  (let [wallRoot (freshRoot! "wall")
        _cfg (fileWrite (str wallRoot "/.asl.config.asn") "(:aslConfig :agentLoop (:specCheck false :wallGateMinSec 1 :wallReserveSec 1))\n")
        _gate (fileWrite (str wallRoot "/slow.sh") (slowGate))
        notes (map (fn [i] (str "(:step :op \"write\" :file \"x.txt\" :content \"w" (stringFromInt64 i) "\")")) (range 0 20))
        startNs (nowNs)
        wallExit (runForm! wallRoot "wall" (rk/scriptFixtureTextFromReplies! "wall" notes)
                   (agentForm "wall" wallRoot "\"sh slow.sh\"" " :owns (\"x.txt\") :wallBudget 5 :gateTimeout 60"))
        wallSec (/ (- (nowNs) startNs) 1000000000)
        wallJournal (journalOf! wallRoot)
        pids (pidsOf! wallRoot)
        liveAfter (filter alive! pids)
        _reap (map (fn [p] (procKill p "SIGKILL")) liveAfter)
        downRoot (reviewRoot! "down")
        downExit (runForm! downRoot "down" (withGradeError (rk/scriptFixtureTextFromReplies! "down" (list (writeReply))) (downMessage))
                   (agentForm "down" downRoot "\"sh gate.sh\"" " :owns (\"scratch/w.txt\")"))
        downJournal (journalOf! downRoot)
        badRoot (reviewRoot! "bad")
        badExit (runForm! badRoot "bad" (withGradeError (rk/scriptFixtureTextFromReplies! "bad" (list (writeReply))) "the grader reply was not a verdict")
                  (agentForm "bad" badRoot "\"sh gate.sh\"" " :owns (\"scratch/w.txt\")"))
        badJournal (journalOf! badRoot)
        cleaned (and (ok? (pathRemove wallRoot)) (and (ok? (pathRemove downRoot)) (ok? (pathRemove badRoot))))]
    (do
      (assert (= (lp/loopBoundary false 0 9 "" false 1.0 10.0 5 6.0 0.5 2 20 0 3 0 0) "wallBudget") "a run past its wall budget stops at the turn boundary")
      (assert (= (lp/loopBoundary false 0 9 "" false 1.0 10.0 5 4.0 0.5 2 20 0 3 0 0) "continue") "a run inside its wall budget goes on")
      (assert (= (lp/loopBoundary false 0 9 "" false 1.0 10.0 0 600.0 0.5 2 20 0 3 0 0) "continue") "no wall budget, no wall stop")
      (assert (stringContains? wallJournal ":signal :wallBudget") "the scripted run ends on its wall budget signal")
      (assert (stringContains? wallJournal "s spent of the 4 s wall budget after") "the signal names the spent budget: 5 s less the 1 s :wallReserveSec")
      (assert (stringContains? wallJournal "(:result :status :escalated") "the wall stop ends the run escalated")
      (assert (!= wallExit 0) "a wall-budget stop is not a success")
      (assert (< wallSec 20) "a run whose gate sleeps 40 s per turn ends within its 5 s budget plus margin")
      (assert (not (listEmpty? pids)) "the slow gate started its sleeping child")
      (assert (listEmpty? liveAfter) "the gate's sleeping child died with the gate's process group at the capped timeout")
      (assert (= downExit 0) "a green gated run whose reviewer the gateway cannot serve exits 0")
      (assert (stringContains? downJournal ":status :needsReview") "the unserved review stays visible as needsReview")
      (assert (stringContains? downJournal ":specCheck (:verdict unavailable :reviewer unavailable") "the receipt says the reviewer is unavailable")
      (assert (stringContains? downJournal "(:gateIntegrity :ok true") "the revert check passes for the written file")
      (assert (not (stringContains? downJournal "revertCheck skipped")) "a gitignored file Leon wrote is code under test, not skipped as a gate file")
      (assert (!= badExit 0) "a reviewer error that is not unavailability still fails the run")
      (assert (stringContains? badJournal ":specCheck (:verdict fail") "that error is a fail verdict")
      (assert (= (gi/implFiles (list "scratch/w.txt" "scratch/wTest.asl" "tests/a.sh" "lib/test_x.py" "gate.sh") (list "sh gate.sh")) (list "scratch/w.txt"))
        "gate files are the files a gate names and test files; the rest is code under test")
      (assert cleaned "the fixture roots are removed")
      true))
