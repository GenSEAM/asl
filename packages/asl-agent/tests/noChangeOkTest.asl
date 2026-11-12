(module aslAgent/tests/noChangeOkTest
  :x [runTests]
  :i [(aslAgent/core :a c) (aslAgent/main :a m)
      (aslHarness/tests/agentLoopRecorderKit :a rk) (aslAgent/tests/gitInitKit :a gk)])

; (:m :ref LEON-OK-WITHOUT-CHANGE :do "a run whose only edit was rejected ended :status :ok because its declared gate was already green; with an :owns brief and no persisted change the run must end needsReview with :signal :noChange, while the same run with an accepted edit stays ok")

fn gate -> String
  "grep -q -E 'beta|gamma' task.txt && echo '1 assertion(s) executed (1 passed)'"

fn ! sessionRun! tag: String old: String -> rk/RecordedRun
  (let [root (rk/freshRecorderRoot! tag)
        wroteS (fileWrite (str root "/task.txt") "alpha\n")
        repo (gk/initGitRepo! root "noChange" "no-change@example.invalid")
        dirty (fileWrite (str root "/task.txt") "beta\n")
        cfg (fileWrite (str root "/.asl.config.asn") "(:aslConfig :agentLoop (:specCheck false))")
        fixtureDir (str root "/tests/fixtures/agentLoop/mvp")
        dir (dirCreate fixtureDir)
        replies (list (str "(:step :op \"edit\" :file \"task.txt\" :old \"" old "\" :new \"gamma\")") "(:step :op \"done\")")
        fixture (fileWrite (str fixtureDir "/" tag ".asn") (rk/scriptFixtureTextFromReplies! tag replies))
        form (str "(:agent :task \"change alpha to beta\" :backend \"script/" tag "\" :root \"" (c/escapeAsn root)
               "\" :mode \"scout\" :owns (\"task.txt\") :gates (\"" (c/escapeAsn (gate)) "\") :budget 6 :contextTokens 8000)")
        code (m/main (list form))
        names (resultOr (dirList (str root "/.asl/run/agentLoop")) (list))
        journalName (optionOr (listHead (filter (fn [n] (stringEndsWith? n ".journal")) names)) "")
        text (if (stringEmpty? journalName) "" (resultOr (fileReadString (str root "/.asl/run/agentLoop/" journalName)) ""))
        cleaned (pathRemove root)]
    (rk/RecordedRun :exitCode code :journal text :sentLines (list)))

fn ! runTests -> Bool
  (let [bad (sessionRun! "noChangeBad" "absent")
        good (sessionRun! "noChangeGood" "beta")]
    (do
      (assert (stringContains? bad.journal ":status :rejected") "the scripted edit with an absent :old is rejected")
      (assert (not (stringContains? bad.journal "(:result :status :ok")) "a run with no persisted change does not end :status :ok")
      (assert (stringContains? bad.journal ":signal :noChange") "the run journals :signal :noChange")
      (assert (stringContains? bad.journal "(:result :status :needsReview") "the run ends needsReview")
      (assert (stringContains? good.journal "(:result :status :ok") "control: the accepted edit ends :status :ok")
      (assert (not (stringContains? good.journal ":signal :noChange")) "control: no noChange signal")
      true))
