(module aslAgent/tests/gateSameLoopTest
  :x [runTests]
  :i [(aslAgent/core :a c) (aslAgent/main :a m)
      (aslHarness/tests/agentLoopRecorderKit :a rk) (aslAgent/tests/gitInitKit :a gk)])

; (:m :ref LOOP-BASELINE-STORED-GATE :do "scripted runs over a counting gate script: what the first turn is told about the baseline, what a gate step gets back in the first turn and in later ones, and which closing line a turn gets after a green gate")

fn writeReply content: String -> String
  (str "(:step :op \"write\" :file \"subject.txt\" :content \"" content "\\n\")")

fn gateReply -> String
  "(:step :op \"gate\")"

(schema Ran
  (:f journal String)
  (:f runs Int64)
  (:f code Int64))

; (:m :ref LOOP-BASELINE-STORED-GATE :do "the gate script by kind: done is red until the subject holds done; dep is green on its first run only, standing for state outside :owns (grader scenario D1); gen appends to the owned subject on every run and stays red")
fn gateBody kind: String root: String runsLog: String -> String
  (str "echo run >> " runsLog "\n"
    (cond
      ((= kind "dep") (str "if test $(wc -l < " runsLog ") -le 1; then echo '1 assertion(s) executed (1 passed)'; else echo 'FAIL state changed since the baseline'; echo '1 assertion(s) executed (0 passed, 1 failed)'; exit 1; fi\n"))
      ((= kind "gen") (str "echo made >> " root "/subject.txt\necho 'FAIL subject lacks done'; echo '1 assertion(s) executed (0 passed, 1 failed)'; exit 1\n"))
      (else (str "if grep -q done " root "/subject.txt; then echo '3 assertion(s) executed (3 passed)'; else echo 'loading subject'; echo 'FAIL subject lacks done'; echo '3 assertion(s) executed (2 passed, 1 failed)'; exit 1; fi\n"))))

fn ! loopRun! tag: String kind: String start: String extra: String replies: (List String) -> Ran
  (let [root (rk/freshRecorderRoot! tag)
        wroteS (fileWrite (str root "/subject.txt") (str start "\n"))
        wroteCfg (fileWrite (str root "/.asl.config.asn") "(:aslConfig :agentLoop (:specCheck false))")
        logDir (dirCreate (str root "/.asl"))
        runsLog (str root "/.asl/gateRuns")
        wroteGate (fileWrite (str root "/.asl/gate.sh") (gateBody kind root runsLog))
        repo (gk/initGitRepo! root "gateSame" "gate-same@example.invalid")
        fixtureDir (str root "/tests/fixtures/agentLoop/mvp")
        dir (dirCreate fixtureDir)
        fixture (fileWrite (str fixtureDir "/same" tag ".asn") (rk/scriptFixtureTextFromReplies! (str "same" tag) replies))
        form (str "(:agent :task \"fix subject\" :backend \"script/same" tag "\" :root \""
               (c/escapeAsn root) "\" :owns (\"subject.txt\") :gates (\"sh " (c/escapeAsn root) "/.asl/gate.sh\" \"grep -q e " (c/escapeAsn root) "/subject.txt\") :budget 30 :contextTokens 8000 " extra ")")
        code (m/main (list form))
        names (resultOr (dirList (str root "/.asl/run/agentLoop")) (list))
        journalName (optionOr (listHead (filter (fn [n] (stringEndsWith? n ".journal")) names)) "")
        text (if (stringEmpty? journalName) "" (resultOr (fileReadString (str root "/.asl/run/agentLoop/" journalName)) ""))
        runs (listLength (filter (fn [l] (= l "run")) (stringSplit (resultOr (fileReadString runsLog) "") "\n")))
        cleaned (pathRemove root)]
    (Ran :journal text :runs runs :code code))

fn sentOf journal: String turn: Int64 -> String
  (optionOr (listHead (filter (fn [l] (stringStartsWith? l (str "(:turn " (stringFromInt64 turn) " :sent "))) (stringSplit journal "\n"))) "")

fn timesIn text: String part: String -> Int64
  (- (listLength (stringSplit text part)) 1)

fn ! runTests -> Bool
  (let [asked (loopRun! "asked" "done" "blue" ":mode \"scout\"" (list (gateReply) (writeReply "done") "(:step :op \"done\")"))
        first (sentOf asked.journal 1)
        second (sentOf asked.journal 2)
        moved (loopRun! "moved" "done" "blue" ":mode \"scout\"" (list (writeReply "teal") (gateReply) (writeReply "grey") (gateReply) (str (writeReply "pine") " " (gateReply)) (writeReply "done") "(:step :op \"done\")"))
        movedThird (sentOf moved.journal 3)
        movedSixth (sentOf moved.journal 6)
        green (loopRun! "green" "done" "done" ":mode \"implement\" :commit true" (list (writeReply "done kept") "(:done :commit \"(:c :a agentLoop :do \\\"gate same\\\" :g \\\"gateSameLoopTest\\\")\")"))
        greenSecond (sentOf green.journal 2)
        stale (loopRun! "stale" "dep" "blue" ":mode \"implement\"" (list "(:step :op \"run\" :argv \"true\")" (gateReply) "(:step :op \"note\" :text \"x\")" "(:step :op \"note\" :text \"y\")"))
        staleThird (sentOf stale.journal 3)
        made (loopRun! "made" "gen" "blue" ":mode \"scout\"" (list (gateReply) "(:step :op \"note\" :text \"x\")" "(:step :op \"note\" :text \"y\")"))
        madeSecond (sentOf made.journal 2)]
    (do
      (assert (stringContains? asked.journal "(:baseline :green (") "the asked run has a baseline row, so the scenario starts from known verdicts")
      (assert (stringContains? first "(:gatesBefore :turn 1 (:n 1 :cmd ") "the first turn's text carries the baseline verdict form")
      (assert (stringContains? first ":state red :exit 1 :asserts 3 :why \\\"FAIL subject lacks done\\\")") (str "the red gate shows its exit, executed assertions and first cause line, not the first output line: " first))
      (assert (and (stringContains? first "(:n 2 :cmd ") (stringContains? first ":state green)")) "the green gate is listed green, with no assertion count when its output states none")
      (refute (stringContains? (sentOf green.journal 2) "(:gatesBefore :turn 1 (:n 1 :cmd \\\"sh") "a later turn's own text does not restate the baseline; only the kept first turn shows it")
      (assert (stringContains? asked.journal "(:turn 1 :gateSame :since 0 :gates 1)") "a gate step before any write is answered from the baseline: the journal names it")
      (assert (stringContains? second ":exit 1 :same true :since 0 :tail ") (str "the gate step's receipt says the result is the stored one and from which turn: " second))
      (assert (stringContains? second "FAIL subject lacks done") "the stored answer still carries the gate output tail")
      (assert (= asked.runs 3) (str "the gate process ran for the baseline, after the write and for the closing revert check, never for the gate step; ran " (stringFromInt64 asked.runs)))
      (assert (stringContains? asked.journal "(:gate :cmd \"sh ") "the turn that asked still records the gate verdict rows")
      (assert (= (timesIn movedSixth ":status :failed :gates ((:n 1 :cmd ") 3) (str "the gate steps of turns 2, 4 and 5 each got a gate receipt: " movedSixth))
      (refute (stringContains? movedSixth ":same true") (str "a gate step after the first turn starts the gate, with or without a write since: none of the three receipts is a stored answer: " movedSixth))
      (refute (stringContains? moved.journal ":gateSame") "no later turn's gate pass is taken from the baseline")
      (assert (stringContains? stale.journal "(:baseline :green (\"sh ") "the stale scenario's gate is green at the baseline")
      (assert (stringContains? stale.journal "(:op :turn 1 :name \"run\" :file \"\" :status ok)") "its first turn runs a step that is no gate request")
      (assert (stringContains? staleThird "FAIL state changed since the baseline") (str "the gate step of turn 2 ran the gate and shows it red now: " staleThird))
      (refute (stringContains? staleThird ":same true") "a gate green at the baseline and red since is not answered green from the baseline")
      (assert (stringContains? made.journal "(:op :turn 1 :name \"gate\"") "the made scenario asks for the gate in its first turn")
      (assert (= (timesIn madeSecond ":status :failed :gates ((:n 1 :cmd ") 1) (str "its gate step got a gate receipt: " madeSecond))
      (refute (stringContains? madeSecond ":same true") "an owned file changed since the baseline digest, here by the gate itself, so the first-turn gate step is not answered from the baseline")
      (refute (stringContains? made.journal ":gateSame") "and the turn's gate pass is not taken from the baseline either")
      (assert (stringContains? movedThird "the last gate was red and nothing was written since") "after a red gate with nothing written since, the closing line says so")
      (assert (stringContains? green.journal "(:baseline :green (") "the green scenario starts from gates green before any edit")
      (assert (not (stringEmpty? greenSecond)) "the green scenario reaches a second turn after its write")
      (refute (stringContains? greenSecond "the last gate was red") (str "after a green gate the closing line does not call the gate red: " greenSecond))
      (assert (stringContains? greenSecond "the next form is a (:step :op ...) or the (:done).") "after a green gate the closing line offers a step or done")
      true))
