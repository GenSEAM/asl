(module aslAgent/tests/ownedMissingTest
  :x [runTests]
  :i [(aslAgent/core :a c) (aslAgent/main :a m)
      (aslHarness/tests/agentLoopRecorderKit :a rk) (aslAgent/tests/gitInitKit :a gk)])

; (:m :ref LEON-OWNED-MISSING :do "node2 2026-11-03: 13 of 18 readStreak stops read owned files that do not exist yet and got :nearest of unrelated files; the read answers owned file missing and not-found reads extend the streak at most two turns")

fn replies -> (List String)
  (listAppend (map (fn [i] (str "(:step :op \"read\" :file \"sub/m" (stringFromInt64 i) ".txt\")")) (range 0 8))
    (map (fn [_] "(:step :op \"done\")") (range 0 3)))

fn ! recordedRun! tag: String -> rk/RecordedRun
  (let [root (rk/freshRecorderRoot! tag)
        wroteS (fileWrite (str root "/other.txt") "green\n")
        wroteCfg (fileWrite (str root "/.asl.config.asn") "(:aslConfig :agentLoop (:specCheck false :readStreakNudge 2 :readStreakEscalate 4))")
        repo (gk/initGitRepo! root "ownedMissing" "owned-missing@example.invalid")
        fixtureDir (str root "/tests/fixtures/agentLoop/mvp")
        dir (dirCreate fixtureDir)
        fixture (fileWrite (str fixtureDir "/om" tag ".asn") (rk/scriptFixtureTextFromReplies! (str "om" tag) (replies)))
        form (str "(:agent :task \"create the module\" :backend \"script/om" tag "\" :root \""
               (c/escapeAsn root) "\" :mode \"implement\" :owns (\"sub/\") :gates (\"false\") :budget 30 :contextTokens 8000)")
        code (m/main (list form))
        names (resultOr (dirList (str root "/.asl/run/agentLoop")) (list))
        journalName (optionOr (listHead (filter (fn [n] (stringEndsWith? n ".journal")) names)) "")
        text (if (stringEmpty? journalName) "" (resultOr (fileReadString (str root "/.asl/run/agentLoop/" journalName)) ""))
        cleaned (pathRemove root)]
    (rk/RecordedRun :exitCode code :journal text :sentLines (list)))

fn replyCount journal: String -> Int64
  (listLength (filter (fn [l] (and (stringStartsWith? l "(:turn ") (stringContains? l " :reply \""))) (stringSplit journal "\n")))

fn ! runTests -> Bool
  (let [run (recordedRun! "base")]
    (do
      (assert (stringContains? run.journal "owned file missing: create it with one write") "a read of an owned file that does not exist says to create it")
      (assert (not (stringContains? run.journal ":signal :readStreak")) "not-found reads of owned files do not end the run with readStreak")
      (assert (>= (replyCount run.journal) 5) (str "the run goes past the readStreak limit of 4 turns, got " (stringFromInt64 (replyCount run.journal))))
      true))
