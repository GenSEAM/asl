(module aslAgent/tests/rawProtocolReplayTest
  :x [runTests]
  :i [(aslAgent/main :a m) (aslAgent/core :a c) (aslHarness/tests/agentLoopRecorderKit :a rk) (aslAgent/tests/gitInitKit :a gk)])

; (:m :ref LEON-RAW-PROTOCOL :do "replays of two node2 sessions with the model turns canned: c925fd5ad8167351 looped 31 turns on writes refused as ERR_USE_RAW and ERR_RAW_MISSING, the model echoing back the :error marker the harness had put into its step; 7de069c5874e6633 had its gate green from turn 1 on owned files changed before the session, sent (:step :op done) twice and still ran to a repeatFailure on rejected writes")

(schema Replay
  (:f seeded Bool)
  (:f journal String)
  (:f file String))

fn turnForm num: Int64 reply: String -> String
  (str "    (:turn :num " (stringFromInt64 num) " :reply \"" (c/escapeAsn reply) "\")\n")

fn greenGate -> String
  "grep -q green subject.txt && echo '1 assertion(s) executed (1 passed)'"

fn ! replay! id: String replies: (List String) seed: String change: String task: String gates: (List String) budget: Int64 -> Replay
  (let [(root (rk/freshRecorderRoot! id))
        (seeded (and (ok? (fileWrite (str root "/subject.txt") seed)) (gk/initGitRepo! root id "raw-protocol@example.invalid")))
        (changed (if (stringEmpty? change) true (ok? (fileWrite (str root "/subject.txt") change))))
        (fixtureDir (str root "/tests/fixtures/agentLoop/mvp"))
        (_ (dirCreate fixtureDir))
        (turns (map (fn [p] (turnForm (+ (pairFirst p) 1) (pairSecond p))) (enumerate replies)))
        (_ (fileWrite (str fixtureDir "/" id ".asn") (str "(:script :id \"" id "\" :mode :scout\n  :turns (\n" (stringJoin turns "") "  )\n)\n")))
        (gateText (if (listEmpty? gates) "" (str " :gates (" (stringJoin (map (fn [g] (str "\"" (c/escapeAsn g) "\"")) gates) " ") ")")))
        (form (str "(:agent :task \"" (c/escapeAsn task) "\" :backend \"script/" id "\" :root \"" (c/escapeAsn root)
                   "\" :mode \"scout\" :owns (\"subject.txt\" \"hint.txt\")" gateText " :budget " (stringFromInt64 budget) " :contextTokens 8000)"))
        (_ (m/main (list form)))
        (journalDir (str root "/.asl/run/agentLoop"))
        (name (optionOr (listHead (filter (fn [n] (stringEndsWith? n ".journal")) (resultOr (dirList journalDir) (list)))) ""))
        (journal (resultOr (fileReadString (str journalDir "/" name)) ""))
        (file (resultOr (fileReadString (str root "/hint.txt")) ""))
        (_ (pathRemove root))]
    (Replay :seeded (and seeded changed) :journal journal :file file))

fn rowsWith journal: String prefix: String part: String -> (List String)
  (filter (fn [l] (and (stringStartsWith? l prefix) (stringContains? l part))) (stringSplit journal "\n"))

fn replyCount journal: String -> Int64
  (listLength (filter (fn [l] (and (stringStartsWith? l "(:turn ") (stringContains? l " :reply \""))) (stringSplit journal "\n")))

fn obs journal: String n: Int64 -> String
  (optionOr (listHead (rowsWith journal (str "(:turn " (stringFromInt64 n) " :observation \"") "")) "")

fn replyAt journal: String n: Int64 -> String
  (optionOr (listHead (rowsWith journal (str "(:turn " (stringFromInt64 n) " :reply \"") "")) "")

fn escapedText -> String
  (stringJoin (map (fn [i] (str "(:hint :missing \"file" (stringFromInt64 i) "\" :near \"a \\\"quoted\\\" name\")\n")) (range 0 12)) "")

fn rawStep -> String
  "(:step :op \"write\" :file \"hint.txt\" :content :raw)"

fn echoStep -> String
  "(:step :op \"write\" :file \"hint.txt\" :content :raw :error \"ERR_RAW_MISSING\")"

fn fenced text: String -> String
  (str "```\n" text "\n```")

fn ! runTests -> Bool
  (let [(plain (replay! "rawPlain" (list (str "(:step :op \"write\" :file \"hint.txt\" :content \"" (c/escapeAsn (escapedText)) "\")") "(:done)")
                 "seed\n" "" "write hint.txt" (list) 4))
        (before (replay! "rawBefore" (list (str (fenced "hello raw") "\n" (rawStep)) "(:done)")
                  "seed\n" "" "write hint.txt" (list) 4))
        (missing (replay! "rawMissing" (list (rawStep) (str (rawStep) "\n" (fenced "second try")) "(:done)")
                   "seed\n" "" "write hint.txt" (list) 5))
        (echo (replay! "rawEcho" (list (echoStep) (echoStep) (echoStep) (echoStep) (str (rawStep) "\n" (fenced "after echo")) "(:done)")
                "seed\n" "" "write hint.txt" (list) 8))
        (nudge (replay! "greenOwned" (list "(:step :op \"gate\")" "(:step :op \"note\" :text \"item complete\")" "(:step :op \"note\" :text \"item complete\")"
                                           "(:step :op \"note\")" "(:step :op \"note\" :text \"item complete\")" "(:step :op \"note\")")
                 "before\n" "green\n" "make subject.txt say green and commit it" (list (greenGate)) 6))
        (stepDone (replay! "rawStepDone" (list (str (rawStep) "\n" (fenced "written")) "(:step :op \"done\")" "(:step :op \"note\")" "(:step :op \"note\" :text \"done\")" "(:step :op \"note\")")
                    "seed\n" "" "write hint.txt" (list) 5))
        (vacuous (replay! "greenVacuous" (list "(:step :op \"gate\")" "(:step :op \"done\")" "(:step :op \"note\")" "(:step :op \"note\" :text \"x\")")
                   "green\n" "" "make subject.txt say green and commit it" (list (greenGate)) 4))]
    (do
      (assert (and plain.seeded (and before.seeded (and missing.seeded (and echo.seeded (and nudge.seeded (and stepDone.seeded vacuous.seeded)))))) "the fixture repos are seeded")
      (assert (= plain.file (escapedText)) "c925 turn 1: a plain :content string over the raw size is written as sent, not refused as ERR_USE_RAW")
      (assert (not (stringContains? plain.journal "ERR_USE_RAW")) "no ERR_USE_RAW receipt for a plain string")
      (assert (= before.file "hello raw\n") (str "the only fenced block of the reply binds to the :raw step even before it: " before.file))
      (assert (not (stringContains? (replyAt missing.journal 1) "ERR_RAW_MISSING")) "the harness puts no :error marker into the step it shows back to the model")
      (assert (stringContains? (obs missing.journal 1) (c/escapeAsn (c/escapeAsn (str (rawStep) "\n```\n")))) (str "the rejection carries the accepted shape with the real target and its fence: " (obs missing.journal 1)))
      (assert (not (stringContains? (obs missing.journal 1) "missing raw block")) "the rejection is the corrective form, not the bare message")
      (assert (= missing.file "second try\n") "the next turn in the accepted shape writes")
      (assert (stringContains? (obs echo.journal 1) ":echoed true") "c925 turn 25: a step carrying an echoed :error is recognised as an echo")
      (assert (stringContains? (obs echo.journal 4) (c/escapeAsn (c/escapeAsn (str (rawStep) "\n```\n")))) "an echo gets the same corrective form")
      (assert (not (stringContains? echo.journal ":signal :repeatFailure")) "four echoes in a row are not counted as repeated attempts")
      (assert (= echo.file "after echo\n") (str "the write after the echoes lands: " echo.file))
      (assert (stringContains? echo.journal "(:result :status :ok") "the echo session ends ok")
      (assert (stringContains? nudge.journal "(:result :status :ok") "7de069: gates green on owned files changed before the session end it as done")
      (assert (= (replyCount nudge.journal) 1) (str "it ends on the first green turn: " (stringFromInt64 (replyCount nudge.journal)) " replies"))
      (assert (stringContains? stepDone.journal "(:result :status :ok") "7de069 turn 3: a (:step :op done) after a write is done")
      (assert (= (replyCount stepDone.journal) 2) (str "it ends on that turn: " (stringFromInt64 (replyCount stepDone.journal)) " replies"))
      (assert (not (stringContains? vacuous.journal "(:result :status :ok")) "green gates on unchanged owned files are not done")
      true))
