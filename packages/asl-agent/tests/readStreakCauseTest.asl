(module aslAgent/tests/readStreakCauseTest
  :x [runTests]
  :i [(aslAgent/context :a ctx) (aslAgent/core :a c) (asl-json/json :a j) (aslAgent/main :a m)
      (aslHarness/tests/agentLoopRecorderKit :a rk) (aslAgent/tests/gitInitKit :a gk)])

; (:m :ref READSTREAK-TUNE :do "node2 2026-11-02: readStreak stops came from runs that re-read the same file because every kept turn but the newest was clipped to 1500 bytes of a 120k window, never got a nudge before the stop, and could not move the thresholds; this suite holds the kept-turn cap, the nudge line and the config rows, and drives a recorded run through all three")

fn histEntry turn: Int64 sent: String got: String -> j/Json
  (j/jobj (list (pair "turn" (j/jint turn)) (pair "sent" (j/jstr sent)) (pair "got" (j/jstr got))
    (pair "ops" (j/jstr "read")) (pair "files" (j/jstr "a.txt")) (pair "gates" (j/jstr ""))))

fn padded marker: String n: Int64 -> String
  (str (stringJoin (map (fn [_] "abcdefghij") (range 0 n)) "") marker)

fn readReply file: String -> String
  (str "(:step :op \"read\" :file \"" file "\")")

fn replies -> (List String)
  (listAppend (list "(:step :op \"run\" :argv \"ls\")" (readReply "a.txt") (readReply "b.txt"))
    (listAppend (map (fn [_] (readReply "b.txt")) (range 0 12)) (list "(:done)")))

fn ! recordedRun! tag: String config: String -> rk/RecordedRun
  (let [root (rk/freshRecorderRoot! tag)
        wroteA (fileWrite (str root "/a.txt") (padded "ENDOFA" 500))
        wroteB (fileWrite (str root "/b.txt") (padded "ENDOFB" 10))
        wroteCfg (fileWrite (str root "/.asl.config.asn") config)
        repo (gk/initGitRepo! root "readStreakCause" "read-streak@example.invalid")
        fixtureDir (str root "/tests/fixtures/agentLoop/mvp")
        dir (dirCreate fixtureDir)
        fixture (fileWrite (str fixtureDir "/streak" tag ".asn") (rk/scriptFixtureTextFromReplies! (str "streak" tag) (replies)))
        form (str "(:agent :task \"read a.txt and b.txt then fix\" :backend \"script/streak" tag "\" :root \""
               (c/escapeAsn root) "\" :mode \"scout\" :owns (\"b.txt\") :gates (\"false\") :budget 30 :contextTokens 120000)")
        code (m/main (list form))
        names (resultOr (dirList (str root "/.asl/run/agentLoop")) (list))
        journalName (optionOr (listHead (filter (fn [n] (stringEndsWith? n ".journal")) names)) "")
        text (if (stringEmpty? journalName) "" (resultOr (fileReadString (str root "/.asl/run/agentLoop/" journalName)) ""))
        sent (filter (fn [l] (stringContains? l ":sent \"")) (stringSplit text "\n"))
        cleaned (pathRemove root)]
    (rk/RecordedRun :exitCode code :journal text :sentLines sent))

fn sentOf run: rk/RecordedRun turn: Int64 -> String
  (optionOr (listHead (filter (fn [l] (stringStartsWith? l (str "(:turn " (stringFromInt64 turn) " :sent "))) run.sentLines)) "")

fn ! runTests -> Bool
  (let [bigGot (padded "TAILMARK" 100)
        hist (list (histEntry 1 "s1" bigGot) (histEntry 2 "s2" bigGot) (histEntry 3 "s3" "small"))
        keptWhole (ctx/renderTranscriptKept hist 8 300 50 2000 2000)
        keptClipped (ctx/renderTranscriptKept hist 8 300 50 300 2000)
        bounded (ctx/renderTranscriptBounded hist 8 300 50 2000)
        cfg "(:aslConfig :agentLoop (:specCheck false :readStreakNudge 3 :readStreakEscalate 20 :readOnlyTurnCap 20))"
        run (recordedRun! "cfg" cfg)
        turn3 (sentOf run 4)
        turn5 (sentOf run 5)
        turn2 (sentOf run 2)]
    (do
      (assert (> (ctx/contextKeptCapBytes 120000 8 1500) 10000) "a 120k window keeps more than 10000 bytes of each kept turn")
      (assert (<= (ctx/contextKeptCapBytes 120000 8 1500) (ctx/contextLatestCapBytes 120000)) "a kept turn never keeps more than the newest turn")
      (assert (= (ctx/contextKeptCapBytes 8000 8 1500) 1500) "a small window keeps the toolCapBytes clip")
      (assert (= (listLength (stringSplit keptWhole "TAILMARK")) 3) "both big kept turns stay whole under a 2000-byte kept cap")
      (assert (= (listLength (stringSplit keptClipped "TAILMARK")) 1) "a 300-byte kept cap clips both big turns")
      (assert (= (listLength (stringSplit bounded "TAILMARK")) 1) "renderTranscriptBounded keeps its toolCapBytes clip for kept turns")
      (assert (= (ctx/readStreakNudgeIn cfg) (some 3)) "readStreakNudgeIn reads the :agentLoop row")
      (assert (= (ctx/readStreakEscalateIn cfg) (some 20)) "readStreakEscalateIn reads the :agentLoop row")
      (assert (= (ctx/readStreakEscalateFor! "/nonexistent-root-readStreakCause") 12) "no config file keeps the default 12")
      (assert (stringEmpty? (ctx/readStreakNudgeLine 5 true 6 12)) "no nudge below the nudge threshold")
      (assert (stringEmpty? (ctx/readStreakNudgeLine 9 false 6 12)) "no nudge while no declared gate is red")
      (assert (stringContains? (ctx/readStreakNudgeLine 6 true 6 12) "the run stops at 12") "the nudge names the stop turn")
      (assert (stringContains? turn3 "ENDOFA") (str "turn 4 still carries the whole a.txt read of turn 2, which a 1500-byte clip cut: " (stringFromInt64 (stringLength turn3))))
      (assert (not (stringContains? turn2 "the run stops at")) "no nudge on turn 2, before the configured nudge threshold")
      (assert (stringContains? turn5 "the run stops at 20") "the live prompt carries the nudge with the configured stop turn")
      (assert (not (stringContains? run.journal ":signal :readStreak")) "a configured readStreakEscalate 20 lets 15 turns without a write run past the default 12")
      true))
