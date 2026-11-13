(module aslAgent/tests/revertSweepLoopTest
  :x [runTests]
  :i [(aslAgent/core :a c) (aslAgent/main :a m)
      (aslHarness/tests/agentLoopRecorderKit :a rk) (aslAgent/tests/gitInitKit :a gk)])

; (:m :ref LEON-REVERT-NO-RESTORE :do "grade M2: a revert entry a killed run left behind (subject.txt at its HEAD text, the working text in the .bak) is put back when the next run starts, and the journal names it in (:revertSwept ...)")

fn ! runTests -> Bool
  (let [root (rk/freshRecorderRoot! "revertSweep")
        wroteS (fileWrite (str root "/subject.txt") "green\n")
        wroteCfg (fileWrite (str root "/.asl.config.asn") "(:aslConfig :agentLoop (:specCheck false))")
        repo (gk/initGitRepo! root "revertSweep" "revert-sweep@example.invalid")
        stem (str root "/.asl/run/revert/deadSession-subject.txt")
        made (ok? (dirCreate (str root "/.asl/run/revert")))
        entry (and (ok? (fileWrite (str stem ".path") "subject.txt")) (ok? (fileWrite (str stem ".bak") "red\n")))
        fixtureDir (str root "/tests/fixtures/agentLoop/mvp")
        dir (dirCreate fixtureDir)
        fixture (fileWrite (str fixtureDir "/rsweep.asn") (rk/scriptFixtureTextFromReplies! "rsweep" (list "(:done)")))
        code (m/main (list (str "(:agent :task \"check subject\" :backend \"script/rsweep\" :root \"" (c/escapeAsn root) "\" :mode \"scout\" :budget 3 :contextTokens 8000)")))
        names (resultOr (dirList (str root "/.asl/run/agentLoop")) (list))
        journalName (optionOr (listHead (filter (fn [n] (stringEndsWith? n ".journal")) names)) "")
        text (resultOr (fileReadString (str root "/.asl/run/agentLoop/" journalName)) "")
        after (resultOr (fileReadString (str root "/subject.txt")) "")
        left (resultOr (dirList (str root "/.asl/run/revert")) (list))
        cleaned (pathRemove root)]
    (do
      (assert (and repo (and made entry)) "the repo and the dead run's revert entry are set up")
      (assert (stringContains? text "(:revertSwept :files (\"subject.txt\"))") "the run's journal names the swept file")
      (assert (= after "red\n") "subject.txt holds the dead run's working text again")
      (assert (listEmpty? left) "the swept entry is gone")
      true))
