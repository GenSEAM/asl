(module aslAgent/tests/greenDoneTest
  :x [runTests]
  :i [(aslAgent/core :a c) (aslAgent/main :a m)
      (aslHarness/tests/agentLoopRecorderKit :a rk) (aslAgent/tests/gitInitKit :a gk) (asl-tools/fleet/run :a fr) (aslAgent/gates :a g)])

; (:m :ref LEON-GREEN-NO-DONE :do "the loop cases run with :baseline false but BaseRed, which runs the baseline pass (LOOPRED-JAIL-SEED seeds the private caches it used to leave empty) so a gate red on the base closes the run through redBefore?'s baseline wiring. A :commit true run whose gate was red on the base or earlier in the session closes on the first all-green gate run after a write inside :owns, with the task's commit line or a harness-built one; a gate green before any edit never closes it, and a turn that refused a step does not")

(schema Closed (:f journal String) (:f message String) (:f subject String) (:f receipt String))

fn writeReply content: String -> String
  (str "(:step :op \"write\" :file \"subject.txt\" :content \"" content "\\n\")")

fn readReply n: Int64 -> String
  (str "(:step :op \"read\" :file \"subject.txt\" :start 1 :end " (stringFromInt64 n) ")")

fn doneGate root: String -> String
  (str "if grep -q done " root "/subject.txt; then echo '1 assertion(s) executed (1 passed)'; else echo '1 assertion(s) executed (0 passed, 1 failed)'; exit 1; fi\n")

fn noBadGate root: String -> String
  (str "if grep -q bad " root "/subject.txt; then echo '1 assertion(s) executed (0 passed, 1 failed)'; exit 1; else echo '1 assertion(s) executed (1 passed)'; fi\n")

fn ! closedRun! tag: String task: String gate: (fn [String] -> String) replies: (List String) -> Closed
  (closedRunIn! tag task gate replies "false")

fn ! closedRunIn! tag: String task: String gate: (fn [String] -> String) replies: (List String) baseline: String -> Closed
  (let [root (rk/freshRecorderRoot! tag)
        wroteS (fileWrite (str root "/subject.txt") "base\n")
        wroteCfg (fileWrite (str root "/.asl.config.asn") (str "(:aslConfig :agentLoop (:specCheck false :baseline " baseline "))"))
        wroteGate (fileWrite (str root ".gate.sh") (gate root))
        repo (gk/initGitRepo! root "greenDone" "green-done@example.invalid")
        fixtureDir (str root "/tests/fixtures/agentLoop/mvp")
        dir (dirCreate fixtureDir)
        fixture (fileWrite (str fixtureDir "/green" tag ".asn") (rk/scriptFixtureTextFromReplies! (str "green" tag) replies))
        form (str "(:agent :task \"" (c/escapeAsn task) "\" :backend \"script/green" tag "\" :root \"" (c/escapeAsn root)
               "\" :mode \"scout\" :owns (\"subject.txt\") :gates (\"sh " (c/escapeAsn root) ".gate.sh\") :budget 8 :contextTokens 8000 :commit true)")
        repoRoot (resultOr (realPath ".") ".")
        rootDir (match (envGet "ASL_ROOT_DIR") ((some r) (if (stringEmpty? r) repoRoot r)) ((none) repoRoot))
        res (m/mainWithRoots (list form) repoRoot rootDir)
        journalDir (str root "/.asl/run/agentLoop")
        journalName (optionOr (listHead (filter (fn [n] (stringEndsWith? n ".journal")) (resultOr (dirList journalDir) (list)))) "")
        journal (resultOr (fileReadString (str journalDir "/" journalName)) "")
        logged (fr/runOneLimited (fr/job (list "git" "log" "-1" "--format=%s" (str "--output=" root ".subject")) root (fr/childEnv (list))) (fr/limits 10 8))
        message (resultOr (fileReadString (str root ".subject")) "")
        subject (resultOr (fileReadString (str root "/subject.txt")) "")
        cleaned (and (ok? (pathRemove root)) (and (ok? (pathRemove (str root ".gate.sh"))) (ok? (pathRemove (str root ".subject")))))]
    (Closed :journal journal :message message :subject subject :receipt res.stdout))

fn clip s: String n: Int64 -> String
  (c/sliceOf s 0 (min n (stringLength s)))

fn replyTurns journal: String -> Int64
  (listLength (filter (fn [l] (and (stringStartsWith? l "(:turn ") (stringContains? l " :reply \""))) (stringSplit journal "\n")))

; (:m :ref LEON-GREEN-NO-DONE :do "grade gate (a): a gate that appends a line to the owned file on every run, failing on the first and passing on the second, goes green with no write by the model; the owned digest is taken before the gates run, so the change makes the next turn run the gate again instead of reusing the red result; only the write and owned-path clauses keep it from closing")
fn toggleGate root: String -> String
  (str "echo x >> " root "/subject.txt; n=$(wc -l < " root "/subject.txt | tr -d ' '); if [ $((n % 2)) -eq 1 ]; then echo '1 assertion(s) executed (1 passed)'; else echo '1 assertion(s) executed (0 passed, 1 failed)'; exit 1; fi\n")

fn receiptLine out: String -> String
  (optionOr (listHead (filter (fn [l] (stringContains? l "(:agentReceipt ")) (stringSplit out "\n"))) "")

fn statusOf out: String -> String
  (let [line (receiptLine out)]
    (match (stringIndexOf line "(:agentReceipt :status :")
      ((none) "")
      ((some k) (let [rest (c/sliceOf line (+ k 24) (stringLength line))]
        (c/sliceOf rest 0 (optionOr (stringIndexOf rest " ") (stringLength rest)))))))

fn ! runTests -> Bool
  (let [reads (list (readReply 1) (readReply 2) (readReply 3))
        quoted (closedRun! "Quoted" "make subject say done. Finish with (:done :commit \"(:c :a subject :do \\\"subject says done\\\" :g \\\"gate\\\" :ev (GREEN-QUOTED))\")."
                 doneGate (cons (writeReply "draft") (cons (writeReply "done") reads)))
        built (closedRun! "Built" "make subject say done" doneGate (cons (writeReply "draft") (cons (writeReply "done") reads)))
        baseGreen (closedRun! "BaseGreen" "keep subject free of the word" noBadGate (cons (writeReply "fine") reads))
        sessionRed (closedRun! "SessionRed" "keep subject free of the word" noBadGate (cons (writeReply "bad") (cons (writeReply "good") reads)))
        refused (closedRun! "Refused" "make subject say done" doneGate
                  (list (writeReply "draft") (str (writeReply "done") "\n(:step :op \"edit\" :file \"subject.txt\" :old \"no such text\" :new \"x\")") "(:step :op \"gate\")" (readReply 1)))
        noWrite (closedRun! "NoWrite" "make the gate pass" toggleGate (cons "(:step :op \"run\" :argv \"ls\")" (cons "(:step :op \"run\" :argv \"ls\")" reads)))
        baseRed (closedRunIn! "BaseRed" "make subject say done" doneGate (cons (writeReply "done") reads) "true")
        modelDone (closedRun! "ModelDone" "make subject say done" doneGate (list (writeReply "draft") (str (writeReply "done") "\n(:done)") (readReply 1)))
        escalated (closedRun! "Escalated" "make subject say done" doneGate (list (writeReply "draft") (str (writeReply "done") "\n(:escalate :reason \"need a second look\" :seen \"gate\" :tried \"write\")") (readReply 1)))]
    (do
      (assert (stringContains? quoted.journal "(:turn 2 :signal :greenDone :reason") "a gate that failed earlier in the session and is green after the owned write closes the run on that turn")
      (assert (= (replyTurns quoted.journal) 2) (str "no further turn is asked after the green gate, got " (stringFromInt64 (replyTurns quoted.journal))))
      (assert (stringContains? quoted.journal "(:result :status :ok") "the closed run ends ok")
      (assert (stringContains? quoted.journal "(:commit \"") "the closed run commits")
      (assert (stringStartsWith? quoted.message "(:c :a subject :do \"subject says done\" :g \"gate\" :ev (GREEN-QUOTED))") (str "the commit carries the line the task quotes, got " quoted.message))
      (assert (stringContains? built.journal "(:commit \"") "a task without a commit line still commits")
      (assert (stringStartsWith? built.message "(:c :a leon :do \"make subject say done\" :g \"sh ") (str "the harness builds the commit line from the task and the gates, got " built.message))
      (assert (not (stringContains? baseGreen.journal ":signal :greenDone")) "a gate that was never seen red does not close the run")
      (assert (= (replyTurns baseGreen.journal) 4) (str "the never-red run goes on through every scripted reply, got " (stringFromInt64 (replyTurns baseGreen.journal))))
      (assert (not (stringContains? baseGreen.journal "(:commit \"")) "the never-red run does not commit")
      (assert (stringContains? sessionRed.journal "(:turn 2 :signal :greenDoneHeld") (str "a gate green on the base that failed earlier in the session is held at the integrity check, since it passes on revert: " (receiptLine sessionRed.receipt)))
      (assert (not (stringContains? sessionRed.journal ":signal :greenDone :reason")) "a close that a (:done) would fail on gateIntegrity does not fire")
      (assert (= (replyTurns sessionRed.journal) 5) (str "the held run goes on through every scripted reply, got " (stringFromInt64 (replyTurns sessionRed.journal))))
      (assert (not (stringContains? sessionRed.receipt ":stop gateIntegrity")) "the held run is not turned into a gateIntegrity failure")
      (assert (= (statusOf sessionRed.receipt) (statusOf baseGreen.receipt)) (str "the held run ends as the never-red run with the same script does, got " (statusOf sessionRed.receipt) " vs " (statusOf baseGreen.receipt)))
      (assert (stringStartsWith? (receiptLine quoted.receipt) "(:agentReceipt :status :ok :stop greenDone") (str "the receipt of a harness close says greenDone (M2): " (receiptLine quoted.receipt)))
      (assert (stringContains? modelDone.journal ":status :ok") "a model (:done) on the green tree ends ok")
      (assert (stringStartsWith? (receiptLine modelDone.receipt) "(:agentReceipt :status :ok :stop done") (str "the receipt of a model close says done (M2): " (receiptLine modelDone.receipt)))
      (assert (not (stringContains? modelDone.journal ":signal :greenDone")) "a turn that sends (:done) is the model's close")
      (assert (not (stringContains? escalated.journal ":signal :greenDone")) "a same-turn (:escalate) wins over greenDone (L5)")
      (assert (stringContains? escalated.journal "(:turn 2 :signal :modelEscalated") "the escalating turn stops as modelEscalated")
      (assert (not (stringContains? noWrite.journal ":signal :greenDone")) (str "a gate that goes green with no write neither closes nor is held: " (receiptLine noWrite.receipt)))
      (assert (stringContains? noWrite.journal ":exit 0)") (str "the toggling gate went green with no write, so the case reaches the write and owned-path clauses: " (clip noWrite.journal 5000)))
      (assert (= (replyTurns noWrite.journal) 5) (str "the no-write run goes on through every scripted reply, got " (stringFromInt64 (replyTurns noWrite.journal))))
      (assert (stringContains? baseRed.journal "(:turn 1 :signal :greenDone :reason") (str "with the baseline on, a gate red on the base closes the run on the first green gate after the owned write: " (clip baseRed.journal 4000)))
      (assert (stringStartsWith? (receiptLine baseRed.receipt) "(:agentReceipt :status :ok :stop greenDone") (str "the baseline close ends ok as greenDone: " (receiptLine baseRed.receipt)))
      (assert (= baseRed.subject "done\n") (str "the baseline run's write landed, got " baseRed.subject))
      (assert (m/baselineRan? false "") "the baseline pass runs by default, so redBefore? reads the base row")
      (assert (not (m/baselineRan? false "(:aslConfig :agentLoop (:baseline false))")) "an :agentLoop :baseline false row turns it off")
      (assert (m/baselineRan? false "(:aslConfig :agentLoop (:baseline true :specCheck false))") "an explicit :baseline true keeps it")
      (assert (not (m/baselineRan? true "")) "a resumed run has no baseline pass")
      (assert (not (m/redBefore? (list "g1") true (list "g1") (list (g/makeGateResult "g1" 1 "" "" false 1)))) "with the baseline run and the gate green on the base, a failed session run does not make it red before (M1)")
      (assert (m/redBefore? (list "g1") false (list) (list (g/makeGateResult "g1" 1 "" "" false 1))) "without a baseline a failed session run makes it red before")
      (assert (not (m/redBefore? (list "g1") false (list) (list (g/makeGateResult "g1" 124 "" "" true 1)))) "a timed-out session run proves nothing")
      (assert (= refused.subject "done\n") (str "the write of the refused turn landed, got " refused.subject))
      (assert (not (stringContains? refused.journal "(:turn 2 :signal :greenDone :reason")) "a turn that refused a step is not closed on its green gate")
      (assert (stringContains? refused.journal "(:turn 3 :signal :greenDone :reason") "the next clean gate run closes it")
      (assert (m/redBefore? (list "g1" "g2") true (list "g1") (list)) "a baseline that ran and did not list a gate green proves it red before")
      (assert (not (m/redBefore? (list "g1" "g2") true (list "g1" "g2") (list))) "every gate green on the base and no failed run in the session: not red before")
      (assert (not (m/redBefore? (list "g1") false (list) (list))) "a baseline that did not run and no failed run in the session prove nothing")
      true))
