(module aslAgent/tests/vacuousAtDoneTest
  :x [runTests]
  :i [(aslAgent/core :a c) (aslAgent/main :a m)
      (aslHarness/tests/agentLoopRecorderKit :a rk) (aslAgent/tests/gitInitKit :a gk)])

; (:m :ref PERF-VACUOUS-GATES-AT-DONE :do "a gate green at baseline is skipped on writing turns while a red gate stays red; the turn its red gates pass, or a done turn, runs it on the final tree before the revert check")

fn writeReply content: String -> String
  (str "(:step :op \"write\" :file \"subject.txt\" :content \"" content "\\n\")")

fn runCount runs: String -> Int64
  (listLength (filter (fn [l] (= l "run")) (stringSplit runs "\n")))

fn ! runTests -> Bool
  (let [root (rk/freshRecorderRoot! "vacuousAtDone")
        wroteS (fileWrite (str root "/subject.txt") "green\n")
        wroteCfg (fileWrite (str root "/.asl.config.asn") "(:aslConfig :agentLoop (:specCheck false))")
        greenLog (str root ".greenRuns")
        redLog (str root ".redRuns")
        wroteGreen (fileWrite (str root ".green.sh") (str "echo run >> " greenLog "\necho '1 assertion(s) executed (1 passed)'\n"))
        wroteRed (fileWrite (str root ".red.sh") (str "echo run >> " redLog "\nif grep -q done " root "/subject.txt; then echo '1 assertion(s) executed (1 passed)'; else echo '1 assertion(s) executed (0 passed, 1 failed)'; exit 1; fi\n"))
        repo (gk/initGitRepo! root "vacuousAtDone" "vacuous-at-done@example.invalid")
        fixtureDir (str root "/tests/fixtures/agentLoop/mvp")
        dir (dirCreate fixtureDir)
        replies (list (writeReply "blue") (writeReply "teal") (writeReply "done") "(:step :op \"done\")")
        fixture (fileWrite (str fixtureDir "/vacuousAtDone.asn") (rk/scriptFixtureTextFromReplies! "vacuousAtDone" replies))
        form (str "(:agent :task \"fix subject\" :backend \"script/vacuousAtDone\" :root \"" (c/escapeAsn root)
               "\" :mode \"scout\" :owns (\"subject.txt\") :gates (\"sh " (c/escapeAsn root) ".green.sh\" \"sh " (c/escapeAsn root) ".red.sh\") :budget 30 :contextTokens 8000)")
        code (m/main (list form))
        journalDir (str root "/.asl/run/agentLoop")
        journalName (optionOr (listHead (filter (fn [n] (stringEndsWith? n ".journal")) (resultOr (dirList journalDir) (list)))) "")
        journal (resultOr (fileReadString (str journalDir "/" journalName)) "")
        greenCmd (str "sh " root ".green.sh")
        greenLines (filter (fn [l] (and (stringStartsWith? l "(:gate :cmd ") (stringContains? l (c/escapeAsn greenCmd)))) (stringSplit journal "\n"))
        greenRuns (runCount (resultOr (fileReadString greenLog) ""))
        redRuns (runCount (resultOr (fileReadString redLog) ""))
        cleaned (pathRemove root)]
    (do
      (assert (= (listLength greenLines) 1) (str "the baseline-green gate runs on the final tree once, in the turn the red gate passed, journal lines " (stringFromInt64 (listLength greenLines))))
      (assert (= greenRuns 3) (str "baseline, the final tree and the revert check, nothing on the red writing turns, ran " (stringFromInt64 greenRuns)))
      (assert (>= redRuns 4) (str "the red gate runs at baseline and on each of the three writing turns, ran " (stringFromInt64 redRuns)))
      true))
