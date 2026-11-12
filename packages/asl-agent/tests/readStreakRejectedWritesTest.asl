(module aslAgent/tests/readStreakRejectedWritesTest
  :x [runTests]
  :i [(aslAgent/core :a c) (aslAgent/main :a m)
      (aslHarness/tests/agentLoopRecorderKit :a rk) (aslAgent/tests/gitInitKit :a gk)])

; (:m :ref LEON-READSTREAK-REJECTED-WRITES :do "a run ended readStreak 12 turns without a write while a gate was red although the writer sent txn ops every few turns, all refused; writeAttempt? knew only write and edit, so a refused txn or delete counted as a read-only turn; the gates here are red and the escalate threshold is 4, so five refused txn turns end the run before the fix and none do after, while five read turns still end it")

fn ! recordedRun! tag: String replies: (List String) -> rk/RecordedRun
  (let [root (rk/freshRecorderRoot! tag)
        wroteS (fileWrite (str root "/subject.txt") "green\n")
        wroteCfg (fileWrite (str root "/.asl.config.asn") "(:aslConfig :agentLoop (:specCheck false :readStreakEscalate 4 :readStreakNudge 3 :stalledTurnCap 50 :readOnlyTurnCap 50))")
        repo (gk/initGitRepo! root "readStreakRej" "read-streak-rej@example.invalid")
        fixtureDir (str root "/tests/fixtures/agentLoop/mvp")
        dir (dirCreate fixtureDir)
        fixture (fileWrite (str fixtureDir "/rs" tag ".asn") (rk/scriptFixtureTextFromReplies! (str "rs" tag) replies))
        form (str "(:agent :task \"fix subject\" :backend \"script/rs" tag "\" :root \""
               (c/escapeAsn root) "\" :mode \"scout\" :owns (\"subject.txt\") :gates (\"echo '1 assertion(s) executed (0 passed)'; exit 1\") :budget 30 :contextTokens 8000)")
        code (m/main (list form))
        names (resultOr (dirList (str root "/.asl/run/agentLoop")) (list))
        journalName (optionOr (listHead (filter (fn [n] (stringEndsWith? n ".journal")) names)) "")
        text (if (stringEmpty? journalName) "" (resultOr (fileReadString (str root "/.asl/run/agentLoop/" journalName)) ""))
        cleaned (pathRemove root)]
    (rk/RecordedRun :exitCode code :journal text :sentLines (list)))

fn ! runTests -> Bool
  (let [writeRed "(:step :op \"write\" :file \"subject.txt\" :content \"red\")"
        refused (cons writeRed (listAppend (map (fn [i] (str "(:step :op \"txn\" :owns (\"subject.txt\") (:edit :file \"subject.txt\" :old \"absent" (stringFromInt64 i) "\" :new \"x\"))")) (range 0 6)) (list "(:step :op \"done\")")))
        reads (cons writeRed (map (fn [i] (str "(:step :op \"read\" :file \"subject.txt\" :start " (stringFromInt64 (+ i 1)) " :end 1)")) (range 0 8)))
        refusedRun (recordedRun! "refused" refused)
        readRun (recordedRun! "reads" reads)]
    (do
      (assert (not (stringContains? refusedRun.journal ":signal :readStreak")) "refused txn turns are write attempts, not read-only turns, so no readStreak signal")
      (assert (stringContains? readRun.journal ":signal :readStreak") "control: pure read turns against a red gate still end the run with readStreak")
      true))
