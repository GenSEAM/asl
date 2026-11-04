(module aslAgent/tests/doneNoWriteTest
  :x [runTests]
  :i [(aslAgent/context :a ctx) (aslAgent/core :a c) (aslAgent/main :a m)
      (aslHarness/tests/agentLoopRecorderKit :a rk) (aslAgent/tests/gitInitKit :a gk)])

; (:m :ref LEON-DONE-LOOP :do "node2 2026-11-01 (c884a797, 0e0d8062): a run whose gate was green before any write and whose owned files had not changed kept sending (:step :op done) for 14 to 20 turns because done alone does not end a run with nothing written; doneNoWriteTurns (default 2) done-only turns end it with :stop doneNoWrite")

fn doneReplies -> (List String)
  (map (fn [_] "(:step :op \"done\")") (range 0 5))

fn ! recordedRun! tag: String config: String -> rk/RecordedRun
  (let [root (rk/freshRecorderRoot! tag)
        wroteS (fileWrite (str root "/subject.txt") "green\n")
        wroteCfg (fileWrite (str root "/.asl.config.asn") config)
        repo (gk/initGitRepo! root "doneNoWrite" "done-no-write@example.invalid")
        fixtureDir (str root "/tests/fixtures/agentLoop/mvp")
        dir (dirCreate fixtureDir)
        fixture (fileWrite (str fixtureDir "/done" tag ".asn") (rk/scriptFixtureTextFromReplies! (str "done" tag) (doneReplies)))
        form (str "(:agent :task \"fix subject\" :backend \"script/done" tag "\" :root \""
               (c/escapeAsn root) "\" :mode \"scout\" :owns (\"subject.txt\") :gates (\"echo '1 assertion(s) executed (1 passed)'\") :budget 30 :contextTokens 8000)")
        code (m/main (list form))
        names (resultOr (dirList (str root "/.asl/run/agentLoop")) (list))
        journalName (optionOr (listHead (filter (fn [n] (stringEndsWith? n ".journal")) names)) "")
        text (if (stringEmpty? journalName) "" (resultOr (fileReadString (str root "/.asl/run/agentLoop/" journalName)) ""))
        cleaned (pathRemove root)]
    (rk/RecordedRun :exitCode code :journal text :sentLines (list)))

fn replyCount journal: String -> Int64
  (listLength (filter (fn [l] (and (stringStartsWith? l "(:turn ") (stringContains? l " :reply \""))) (stringSplit journal "\n")))

fn ! runTests -> Bool
  (let [cfg3 "(:aslConfig :agentLoop (:specCheck false :doneNoWriteTurns 3))"
        base (recordedRun! "base" "(:aslConfig :agentLoop (:specCheck false))")
        wide (recordedRun! "wide" cfg3)]
    (do
      (assert (stringContains? base.journal ":signal :doneNoWrite") "five done-only replies with a green gate and nothing written end with the doneNoWrite signal")
      (assert (<= (replyCount base.journal) 3) (str "the run ends within 3 turns, got " (stringFromInt64 (replyCount base.journal))))
      (assert (= (ctx/doneNoWriteTurnsIn cfg3) (some 3)) "doneNoWriteTurnsIn reads the :agentLoop row")
      (assert (= (ctx/doneNoWriteTurnsFor! "/nonexistent-root-doneNoWrite") 2) "no config file keeps the default 2")
      (assert (stringContains? wide.journal ":signal :doneNoWrite") "a configured 3 still ends the run")
      (assert (= (replyCount wide.journal) 3) (str "doneNoWriteTurns 3 runs three turns, got " (stringFromInt64 (replyCount wide.journal))))
      true))
